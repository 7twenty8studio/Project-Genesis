import Foundation

/// A group's challenges and everyone's progress in them.
@MainActor
@Observable
final class GroupChallengesModel {
    let groupID: UUID
    private(set) var challenges: [GroupChallenge] = []
    /// Everyone's progress, by challenge (loaded when shown).
    private(set) var progress: [UUID: [ChallengeProgress]] = [:]
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let backend: any GroupChallengeBackend
    @ObservationIgnored private let store: CommunityStore
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    /// Told what's ticked, so finishing a chapter in the reader doesn't
    /// tick it again.
    @ObservationIgnored var autoTick: ChallengeAutoTick?

    init(groupID: UUID, backend: any GroupChallengeBackend, store: CommunityStore, calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        self.groupID = groupID
        self.backend = backend
        self.store = store
        self.calendar = calendar
        self.now = now
    }

    var group: GroupSummary? { store.group(groupID) }
    /// Owners and moderators ('leader') start and end challenges.
    var canManage: Bool { group?.isLeader ?? false }
    var me: UUID? { store.userID }

    // MARK: Lists

    func status(of challenge: GroupChallenge) -> GroupChallengeStatus {
        challenge.status(on: now(), calendar: calendar)
    }

    var running: [GroupChallenge] { challenges.filter { status(of: $0) == .running } }
    var upcoming: [GroupChallenge] { challenges.filter { status(of: $0) == .upcoming }.sorted { $0.startDay < $1.startDay } }
    var finished: [GroupChallenge] { challenges.filter { status(of: $0) == .finished } }

    /// Running first, then the next to start.
    var current: [GroupChallenge] { running + upcoming }

    /// Whether another challenge can start (the server allows five at once).
    var canStartAnother: Bool { current.count < GroupChallengeRules.maximumRunning }

    func challenge(_ id: UUID) -> GroupChallenge? { challenges.first { $0.id == id } }

    // MARK: Progress

    /// Everyone's progress, without people you've blocked.
    func rows(for challenge: GroupChallenge) -> [ChallengeProgress] {
        (progress[challenge.id] ?? []).filter { $0.userID == me || !store.blocked.contains($0.userID) }
    }

    /// Members in name order (never ranked), you first.
    func memberRows(for challenge: GroupChallenge) -> [ChallengeProgress] {
        rows(for: challenge).sorted { lhs, rhs in
            if (lhs.userID == me) != (rhs.userID == me) { return lhs.userID == me }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    func summary(for challenge: GroupChallenge) -> GroupChallengeSummary {
        GroupChallengeSummary(challenge: challenge, rows: rows(for: challenge), me: me, on: now(), calendar: calendar)
    }

    func hasTicked(_ item: Int, in challenge: GroupChallenge) -> Bool {
        summary(for: challenge).myItems.contains(item)
    }

    func canTick(_ item: Int, in challenge: GroupChallenge) -> Bool {
        challenge.canTick(item, on: now(), calendar: calendar)
    }

    /// Today's day number in a challenge.
    func today(in challenge: GroupChallenge) -> Int {
        challenge.dayIndex(on: now(), calendar: calendar)
    }

    // MARK: Loading

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            challenges = try await backend.challenges(in: groupID)
            // Progress for what's on the group's page; finished ones load
            // when opened.
            for challenge in current {
                progress[challenge.id] = try await backend.progress(of: challenge.id)
            }
            errorMessage = nil
            shareProgress()
        } catch {
            errorMessage = GroupChallengeError.from(error).localizedDescription
        }
        hasLoaded = true
    }

    private func shareProgress() {
        autoTick?.update(group: groupID, challenges: challenges, progress: progress, me: me)
    }

    func loadProgress(_ challenge: GroupChallenge) async {
        do {
            progress[challenge.id] = try await backend.progress(of: challenge.id)
            errorMessage = nil
            shareProgress()
        } catch {
            errorMessage = GroupChallengeError.from(error).localizedDescription
        }
    }

    @discardableResult
    private func run(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            errorMessage = nil
            return true
        } catch {
            errorMessage = GroupChallengeError.from(error).localizedDescription
            return false
        }
    }

    // MARK: Ticking

    /// Ticks or unticks an item, showing it straight away and putting it
    /// back if saving fails.
    func setDone(_ done: Bool, item: Int, in challenge: GroupChallenge) async {
        guard let me, hasTicked(item, in: challenge) != done else { return }
        let before = progress[challenge.id]
        apply(done, item: item, user: me, challenge: challenge)
        let saved = await run { try await backend.setCheckin(done, item: item, challenge: challenge.id) }
        if !saved { progress[challenge.id] = before }
        shareProgress()
    }

    private func apply(_ done: Bool, item: Int, user: UUID, challenge: GroupChallenge) {
        var rows = progress[challenge.id] ?? []
        let index: Int
        if let found = rows.firstIndex(where: { $0.userID == user }) {
            index = found
        } else {
            rows.append(ChallengeProgress(userID: user, displayName: store.profile?.displayName ?? "", done: 0, items: []))
            index = rows.count - 1
        }
        var items = Set(rows[index].items ?? [])
        if done { items.insert(item) } else { items.remove(item) }
        rows[index].items = items.sorted()
        rows[index].done = items.count
        progress[challenge.id] = rows
    }

    // MARK: Leading

    /// Starts a challenge; returns its id.
    func create(_ draft: GroupChallengeDraft) async -> UUID? {
        var created: UUID?
        await run {
            created = try await backend.createChallenge(draft, in: groupID)
            challenges = try await backend.challenges(in: groupID)
            if let created { progress[created] = try await backend.progress(of: created) }
        }
        return created
    }

    /// Ends a challenge early: it moves to finished, keeping everyone's progress.
    @discardableResult
    func end(_ challenge: GroupChallenge) async -> Bool {
        await run {
            try await backend.endChallenge(challenge.id)
            challenges = try await backend.challenges(in: groupID)
            progress[challenge.id] = try await backend.progress(of: challenge.id)
        }
    }
}
