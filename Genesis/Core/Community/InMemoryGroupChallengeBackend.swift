import Foundation

/// Group challenges kept in memory, for UI tests and unit tests: no network,
/// repeatable. Membership and roles come from the community backend it's
/// given (its `myGroups()` and `members(of:)`), and the rules mirror the
/// server's: only owners and moderators ('leader') start and end
/// challenges, at most five run at once (ended ones don't count), days can't
/// be ticked ahead (a day's slack), and nothing changes once a challenge has
/// ended, by date or by a moderator (it stays, finished, with its progress).
actor InMemoryGroupChallengeBackend: GroupChallengeBackend {
    private let community: CommunityBackend
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var rows: [GroupChallenge] = []
    /// Ticks by challenge, then person.
    private var checkins: [UUID: [UUID: Set<Int>]] = [:]

    /// The group InMemoryCommunityBackend offers with its sample invite code.
    static let sampleGroupID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
    /// Its leader ("Pastor Ruth").
    static let sampleLeaderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!

    /// With `seeded`, the sample group has a reading streak that started two
    /// days ago (its leader has ticked every day so far) and a passage to
    /// learn this week.
    init(community: CommunityBackend, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { .now }, seeded: Bool = false) {
        self.community = community
        self.calendar = calendar
        self.now = now
        guard seeded else { return }
        let today = now()
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        let streak = GroupChallenge(
            id: UUID(), groupID: Self.sampleGroupID, createdBy: Self.sampleLeaderID, kind: .streak,
            title: "Read every day for 7 days", details: "A chapter a day, any chapter.",
            startDay: Timestamp.dayString(from: twoDaysAgo, calendar: calendar), days: 7, chapters: [],
            verseStart: nil, verseEnd: nil, translationID: nil, createdAt: twoDaysAgo
        )
        let memorise = GroupChallenge(
            id: UUID(), groupID: Self.sampleGroupID, createdBy: Self.sampleLeaderID, kind: .memorise,
            title: "Learn Psalm 23:1\u{2013}3 together", details: "",
            startDay: Timestamp.dayString(from: today, calendar: calendar), days: 7, chapters: [],
            verseStart: 19_023_001, verseEnd: 19_023_003, translationID: "KJV", createdAt: today
        )
        rows = [streak, memorise]
        checkins[streak.id] = [Self.sampleLeaderID: [1, 2, 3]]
    }

    // MARK: Who's asking

    private func me() async throws -> UUID {
        guard let id = await community.currentUserID() else { throw CommunityError.signInRequired }
        return id
    }

    private func role(in group: UUID) async throws -> GroupRole? {
        try await community.myGroups().first { $0.id == group }?.role
    }

    private static func fail(_ code: String) -> CommunityError {
        .message(GroupChallengeError.messages[code] ?? String(localized: "Something went wrong. Please try again."))
    }

    /// A challenge the person can see (they're in its group).
    private func visible(_ id: UUID) async throws -> GroupChallenge {
        guard let challenge = rows.first(where: { $0.id == id }), try await role(in: challenge.groupID) != nil else {
            throw CommunityError.message(String(localized: "That's no longer there."))
        }
        return challenge
    }

    // MARK: GroupChallengeBackend

    func challenges(in group: UUID) async throws -> [GroupChallenge] {
        guard try await role(in: group) != nil else { return [] }
        return rows.filter { $0.groupID == group }.sorted { $0.startDay > $1.startDay }
    }

    func createChallenge(_ draft: GroupChallengeDraft, in group: UUID) async throws -> UUID {
        let me = try await me()
        guard try await role(in: group) == .leader else { throw Self.fail("moderators_only") }
        let today = now()
        guard draft.isValid(today: today, calendar: calendar) else { throw Self.fail("invalid_challenge") }
        let running = rows.filter { $0.groupID == group && $0.endedAt == nil && $0.dayIndex(on: today, calendar: calendar) <= $0.days }
        guard running.count < GroupChallengeRules.maximumRunning else { throw Self.fail("too_many_challenges") }

        let challenge = GroupChallenge(
            id: UUID(), groupID: group, createdBy: me, kind: draft.kind,
            title: draft.trimmedTitle, details: draft.trimmedDetails,
            startDay: Timestamp.dayString(from: draft.startsOn, calendar: calendar), days: draft.days,
            chapters: draft.kind == .reading ? Array(Set(draft.chapters)).sorted() : [],
            verseStart: draft.kind == .memorise ? draft.verseStart?.rawValue : nil,
            verseEnd: draft.kind == .memorise ? draft.verseEnd?.rawValue : nil,
            translationID: draft.kind == .memorise ? draft.translationID : nil,
            createdAt: today
        )
        rows.append(challenge)
        return challenge.id
    }

    func endChallenge(_ challenge: UUID) async throws {
        guard let found = rows.first(where: { $0.id == challenge }), try await role(in: found.groupID) == .leader else {
            throw Self.fail("moderators_only")
        }
        if let index = rows.firstIndex(where: { $0.id == challenge }), rows[index].endedAt == nil {
            rows[index].endedAt = now()
        }
    }

    func setCheckin(_ done: Bool, item: Int, challenge: UUID) async throws {
        let me = try await me()
        let found = try await visible(challenge)
        let today = found.dayIndex(on: now(), calendar: calendar)
        if today < 0 { throw Self.fail("not_started") }
        if found.endedAt != nil || today > found.days + 1 { throw Self.fail("challenge_ended") }
        guard found.canTick(item, on: now(), calendar: calendar) else { throw Self.fail("invalid_item") }
        var mine = checkins[challenge]?[me] ?? []
        if done { mine.insert(item) } else { mine.remove(item) }
        checkins[challenge, default: [:]][me] = mine
    }

    func progress(of challenge: UUID) async throws -> [ChallengeProgress] {
        let me = try await me()
        let found = try await visible(challenge)
        let members = try await community.members(of: found.groupID)
        return members.map { member in
            let items = checkins[challenge]?[member.userID] ?? []
            // Other people's chapters stay private, as on the server.
            let shown: [Int]? = found.kind == .reading && member.userID != me ? nil : items.sorted()
            return ChallengeProgress(userID: member.userID, displayName: member.displayName, done: items.count, items: shown)
        }
    }
}
