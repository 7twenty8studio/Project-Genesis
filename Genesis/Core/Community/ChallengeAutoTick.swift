import Foundation

/// Which of the person's reading challenges a finished chapter ticks.
enum ChallengeAutoTickRule {
    /// Running "Read Together" challenges, in groups the person is in, that
    /// list `chapter` and haven't had it ticked yet.
    static func challenges(
        toTick chapter: ChapterID,
        in challenges: [GroupChallenge],
        ticked: [UUID: Set<Int>],
        groups: Set<UUID>,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> [GroupChallenge] {
        let item = ReadingChallengeChapters.raw(chapter)
        return challenges.filter { challenge in
            challenge.kind == .reading
                && groups.contains(challenge.groupID)
                && challenge.status(on: date, calendar: calendar) == .running
                && challenge.chapters.contains(item)
                && !(ticked[challenge.id] ?? []).contains(item)
        }
    }

    /// Whether a cache loaded at `loadedAt` is due a refresh.
    static func isStale(loadedAt: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let loadedAt else { return true }
        return now.timeIntervalSince(loadedAt) >= interval
    }
}

/// Ticks a chapter in the person's running reading challenges when they
/// finish it in the reader. The reader only tells it which chapter; this
/// keeps a small cache of those challenges (and what's already ticked), so
/// nothing is asked of the server unless a tick is needed. Quiet: does
/// nothing when signed out or when groups are off or hidden, and failures
/// are ignored (the chapter can still be ticked by hand).
@MainActor
@Observable
final class ChallengeAutoTick {
    /// Running reading challenges by id.
    private(set) var challenges: [UUID: GroupChallenge] = [:]
    /// My ticked chapters, by challenge.
    private(set) var ticked: [UUID: Set<Int>] = [:]

    @ObservationIgnored private let backend: any GroupChallengeBackend
    @ObservationIgnored private let community: CommunityStore
    @ObservationIgnored private let flags: FeatureFlagService
    @ObservationIgnored private let features: FeaturePreferences
    @ObservationIgnored private let isEnabled: Bool
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var loadedAt: Date?
    /// Who's signed in, and their groups, as of the last refresh.
    @ObservationIgnored private var me: UUID?
    @ObservationIgnored private var groupIDs: Set<UUID> = []
    @ObservationIgnored private var isRefreshing = false

    /// How often coming back to the app may reload the cache.
    static let refreshInterval: TimeInterval = 5 * 60

    init(
        backend: any GroupChallengeBackend,
        community: CommunityStore,
        flags: FeatureFlagService,
        features: FeaturePreferences,
        isEnabled: Bool = true,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.backend = backend
        self.community = community
        self.flags = flags
        self.features = features
        self.isEnabled = isEnabled
        self.calendar = calendar
        self.now = now
    }

    /// Groups are switched on, wanted, and there's an account.
    private var isAllowed: Bool {
        isEnabled && flags.isOn(.groups) && features.isOn(.together)
    }

    // MARK: The reader

    /// The reader finished a chapter.
    func chapterFinished(_ chapter: ChapterID) {
        guard isAllowed else { return }
        Task { await tick(chapter) }
    }

    /// Ticks `chapter` wherever it's still needed (loading the cache first
    /// if it never has been).
    func tick(_ chapter: ChapterID) async {
        guard isAllowed else { return }
        if loadedAt == nil { await refresh() }
        guard me != nil else { return }
        let due = ChallengeAutoTickRule.challenges(
            toTick: chapter,
            in: Array(challenges.values),
            ticked: ticked,
            groups: currentGroups,
            on: now(),
            calendar: calendar
        )
        let item = ReadingChallengeChapters.raw(chapter)
        for challenge in due {
            // Marked first, so finishing it twice never sends it twice.
            ticked[challenge.id, default: []].insert(item)
            do {
                try await backend.setCheckin(true, item: item, challenge: challenge.id)
            } catch {
                ticked[challenge.id]?.remove(item)
            }
        }
    }

    // MARK: Keeping up

    /// Reloads the person's running reading challenges, at most every few
    /// minutes unless `force`d.
    func refresh(force: Bool = false) async {
        guard isAllowed else {
            clear()
            return
        }
        guard !isRefreshing, force || ChallengeAutoTickRule.isStale(loadedAt: loadedAt, now: now(), interval: Self.refreshInterval) else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // Straight from the server, so the Together screens' state is left alone.
        let backendCommunity = community.backend
        guard let me = await backendCommunity.currentUserID() else {
            clear()
            loadedAt = now()
            return
        }
        // Offline: keep what was known.
        guard let groups = try? await backendCommunity.myGroups() else { return }
        var found: [UUID: GroupChallenge] = [:]
        var mine: [UUID: Set<Int>] = [:]
        for group in groups {
            guard let list = try? await backend.challenges(in: group.id) else { continue }
            for challenge in list where challenge.kind == .reading && challenge.status(on: now(), calendar: calendar) == .running {
                guard let rows = try? await backend.progress(of: challenge.id) else { continue }
                found[challenge.id] = challenge
                mine[challenge.id] = Set(rows.first { $0.userID == me }?.items ?? [])
            }
        }
        self.me = me
        groupIDs = Set(groups.map(\.id))
        challenges = found
        ticked = mine
        loadedAt = now()
    }

    /// The person's groups: the Together screens' list once it's loaded (so
    /// leaving a group counts at once), otherwise the last refresh's.
    private var currentGroups: Set<UUID> {
        community.hasLoaded && community.userID == me ? Set(community.groups.map(\.id)) : groupIDs
    }

    /// A group's page loaded its challenges: take what it knows.
    func update(group: UUID, challenges list: [GroupChallenge], progress: [UUID: [ChallengeProgress]], me: UUID?) {
        guard isAllowed, let me else { return }
        self.me = me
        groupIDs.insert(group)
        for (id, challenge) in challenges where challenge.groupID == group {
            challenges[id] = nil
            ticked[id] = nil
        }
        for challenge in list where challenge.kind == .reading && challenge.status(on: now(), calendar: calendar) == .running {
            guard let rows = progress[challenge.id] else { continue }
            challenges[challenge.id] = challenge
            ticked[challenge.id] = Set(rows.first { $0.userID == me }?.items ?? [])
        }
    }

    private func clear() {
        challenges = [:]
        ticked = [:]
        me = nil
        groupIDs = []
        loadedAt = nil
    }
}
