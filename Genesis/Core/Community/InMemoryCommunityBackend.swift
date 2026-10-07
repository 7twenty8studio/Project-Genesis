import Foundation

/// Groups and community kept in memory, for UI tests: no network, no
/// account, repeatable. Mirrors the server's rules closely enough to test the
/// screens (moderators only for announcements, owner-only choices, bans,
/// mutes, join requests, one reaction each, reports hide after three, blocked
/// people disappear). Unit tests can act as other people with `actAs`.
actor InMemoryCommunityBackend: CommunityBackend {
    /// The person signed in when the backend starts.
    nonisolated static let defaultUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    /// Owns the sample groups.
    nonisolated static let sampleOwnerID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
    /// A group that exists for "join with a code".
    static let sampleInviteCode = "GRACE12345"
    /// A group that approves new members.
    static let sampleApprovalInviteCode = "HOPE123456"

    private var me = InMemoryCommunityBackend.defaultUserID
    private let neighbour = InMemoryCommunityBackend.sampleOwnerID

    private var profiles: [UUID: CommunityProfile] = [:]
    private var blocks: Set<UUID> = []
    private var reportRows: [ReportRow] = []
    private var groups: [UUID: GroupSummary] = [:]
    private var members: [UUID: [GroupMember]] = [:]
    private var bansByGroup: [UUID: [GroupBan]] = [:]
    private var requests: [GroupJoinRequest] = []
    private var progressRows: [UUID: Set<String>] = [:]
    private var prayerRows: [GroupPrayer] = []
    private var marks: Set<UUID> = []
    private var postRows: [GroupPost] = []
    private var announcementRows: [GroupAnnouncement] = []
    private var communityRows: [CommunityPost] = []
    /// Who really wrote each community post (anonymous ones hide it).
    private var postAuthors: [UUID: UUID] = [:]
    private var reactions: Set<UUID> = []
    private var commentRows: [CommunityComment] = []
    /// Strictly increasing times, so "longest-standing" is never a tie.
    private var clock = Date.now.addingTimeInterval(-60)

    private struct ReportRow {
        let kind: ContentKind
        let id: UUID
        let group: UUID?
        let reporter: UUID
        let reason: String
        let createdAt: Date
        var resolved = false
    }

    init() {
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
        groups[groupID] = GroupSummary(
            id: groupID, name: "Grace Fellowship", description: "Wednesday evening study.",
            inviteCode: Self.sampleInviteCode, planID: ReadingPlan.gospelsID, planTitle: nil, planBooks: nil, planDays: nil,
            planStart: Calendar.current.date(byAdding: .day, value: -2, to: .now), role: .member, notifications: true,
            ownerID: neighbour
        )
        members[groupID] = [GroupMember(groupID: groupID, userID: neighbour, role: .leader, displayName: "Pastor Ruth", joinedAt: .now.addingTimeInterval(-86_400 * 30))]
        let approvalID = UUID(uuidString: "00000000-0000-0000-0000-00000000A9A1")!
        groups[approvalID] = GroupSummary(
            id: approvalID, name: "Hope Church Youth", description: "Friday nights.",
            inviteCode: Self.sampleApprovalInviteCode, planID: nil, planTitle: nil, planBooks: nil, planDays: nil,
            planStart: nil, role: .member, notifications: true,
            ownerID: neighbour, requiresApproval: true
        )
        members[approvalID] = [GroupMember(groupID: approvalID, userID: neighbour, role: .leader, displayName: "Pastor Ruth", joinedAt: .now.addingTimeInterval(-86_400 * 60))]
        profiles[neighbour] = CommunityProfile(userID: neighbour, displayName: "Pastor Ruth", communityTermsAcceptedAt: .now)
        announcementRows = [GroupAnnouncement(id: UUID(), groupID: groupID, userID: neighbour, displayName: "Pastor Ruth", title: "Welcome!", body: "We meet Wednesdays at 7.", createdAt: .now.addingTimeInterval(-3_600))]
        defer { for post in communityRows { postAuthors[post.id] = post.authorID } }
        communityRows = [
            CommunityPost(id: UUID(), authorID: neighbour, isMine: false, kind: .prayer, body: "Please pray for my father's surgery on Friday.", startVerse: nil, endVerse: nil, displayName: "Ruth", reactionCount: 4, commentCount: 0, createdAt: .now.addingTimeInterval(-7_200), hiddenAt: nil),
            CommunityPost(id: UUID(), authorID: neighbour, isMine: false, kind: .reflection, body: "Reading this today reminded me how patient God is with us.", startVerse: 19_103_008, endVerse: 19_103_008, displayName: "Ruth", reactionCount: 2, commentCount: 0, createdAt: .now.addingTimeInterval(-9_000), hiddenAt: nil),
        ]
    }

    // MARK: Testing

    /// Act as someone else from now on, giving them a display name if they
    /// don't have one yet. For unit tests of rules between people.
    func actAs(_ user: UUID, name: String) {
        me = user
        if profiles[user] == nil {
            profiles[user] = CommunityProfile(userID: user, displayName: name, communityTermsAcceptedAt: nil)
        }
    }

    /// Joins with a code and returns the group's id (or the id of the group
    /// asked to join). A shortcut for tests; the app uses `requestToJoin`.
    func joinGroup(code: String) async throws -> UUID {
        try await requestToJoin(code: code).groupID
    }

    // MARK: Rules

    private var profileRow: CommunityProfile? {
        get { profiles[me] }
        set { profiles[me] = newValue }
    }

    private func now() -> Date {
        clock = max(clock.addingTimeInterval(0.001), .now)
        return clock
    }

    private func requireProfile() throws -> CommunityProfile {
        guard let profileRow else { throw CommunityError.message(String(localized: "Choose a display name first.")) }
        return profileRow
    }

    private static let blockedWords: Set<String> = ["damn", "shit"]

    private func check(_ text: String) throws {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.contains(where: Self.blockedWords.contains) {
            throw CommunityError.message(String(localized: "Please rephrase. Some words aren't allowed in Genesis."))
        }
    }

    private static var notAllowed: CommunityError { .message(String(localized: "You can't do that.")) }
    private static var ownerOnly: CommunityError { .message(String(localized: "Only the group's owner can do that.")) }
    private static var moderatorsOnly: CommunityError { .message(String(localized: "Only the group's owner and moderators can do that.")) }
    private static var notFound: CommunityError { .message(String(localized: "That's no longer there.")) }
    /// What the server says when row-level security refuses an insert.
    private static var refused: CommunityError {
        .message(String(localized: "That isn't allowed. If you were removed from a group or the community is closed, pull to refresh."))
    }

    private func member(_ user: UUID, in group: UUID) -> GroupMember? {
        members[group]?.first { $0.userID == user }
    }

    private func myRole(in group: UUID) -> GroupRole? {
        member(me, in: group)?.role
    }

    private func isLeader(_ group: UUID) -> Bool {
        myRole(in: group) == .leader
    }

    private func isOwner(_ group: UUID) -> Bool {
        groups[group]?.ownerID == me && member(me, in: group) != nil
    }

    /// genesis_can_moderate: moderators act on members; only the owner acts
    /// on moderators; nobody acts on the owner or themselves.
    private func canModerate(_ user: UUID, in group: UUID) -> Bool {
        guard user != me, isLeader(group), groups[group]?.ownerID != user else { return false }
        return isOwner(group) || member(user, in: group)?.role != .leader
    }

    private func isBanned(_ user: UUID, from group: UUID) -> Bool {
        bansByGroup[group]?.contains { $0.userID == user } ?? false
    }

    private func updateMember(_ user: UUID, in group: UUID, _ change: (inout GroupMember) -> Void) {
        guard let index = members[group]?.firstIndex(where: { $0.userID == user }) else { return }
        change(&members[group]![index])
    }

    /// When the owner goes, the longest-standing moderator (else member)
    /// becomes the owner; the last person out closes the group.
    private func afterLeaving(_ user: UUID, group: UUID) {
        let remaining = members[group] ?? []
        if remaining.isEmpty {
            groups[group] = nil
            members[group] = nil
            return
        }
        let owner = groups[group]?.ownerID
        guard owner == nil || owner == user else { return }
        let next = remaining.sorted { lhs, rhs in
            if (lhs.role == .leader) != (rhs.role == .leader) { return lhs.role == .leader }
            return lhs.joinedAt < rhs.joinedAt
        }.first
        guard let next else { return }
        updateMember(next.userID, in: group) { member in
            member.role = .leader
            member.mutedUntil = nil
        }
        groups[group]?.ownerID = next.userID
    }

    private func newCode() -> String {
        "NEW" + String(UUID().uuidString.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(7))
    }

    // MARK: Profile and safety

    func currentUserID() async -> UUID? { me }

    func profile() async throws -> CommunityProfile? { profileRow }

    func setDisplayName(_ name: String) async throws {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(cleaned.count) else { throw CommunityError.message(String(localized: "Display names are 1 to 40 characters.")) }
        try check(cleaned)
        profileRow = CommunityProfile(userID: me, displayName: cleaned, communityTermsAcceptedAt: profileRow?.communityTermsAcceptedAt)
        for group in members.keys {
            updateMember(me, in: group) { $0.displayName = cleaned }
        }
    }

    func acceptCommunityTerms() async throws {
        var profile = try requireProfile()
        profile.communityTermsAcceptedAt = .now
        profileRow = profile
    }

    func blockedUsers() async throws -> Set<UUID> { blocks }
    func block(_ user: UUID) async throws { blocks.insert(user) }
    func unblock(_ user: UUID) async throws { blocks.remove(user) }
    func blockAuthor(ofPost post: UUID) async throws {
        if let author = postAuthors[post], author != me { blocks.insert(author) }
    }

    private func openReporters(of id: UUID) -> Set<UUID> {
        Set(reportRows.filter { $0.id == id && !$0.resolved }.map(\.reporter))
    }

    private func contentGroup(of kind: ContentKind, id: UUID) -> UUID? {
        switch kind {
        case .groupPrayer: prayerRows.first { $0.id == id }?.groupID
        case .groupPost: postRows.first { $0.id == id }?.groupID
        case .groupAnnouncement: announcementRows.first { $0.id == id }?.groupID
        case .communityPost, .communityComment: nil
        }
    }

    func report(_ kind: ContentKind, id: UUID, reason: String) async throws {
        // One report each, ever, like the server's unique key.
        guard !reportRows.contains(where: { $0.id == id && $0.reporter == me }) else { return }
        reportRows.append(ReportRow(kind: kind, id: id, group: contentGroup(of: kind, id: id), reporter: me, reason: String(reason.prefix(500)), createdAt: now()))
        // Three reports from different people hide it until it's reviewed.
        guard openReporters(of: id).count >= 3 else { return }
        if let index = prayerRows.firstIndex(where: { $0.id == id }), prayerRows[index].hiddenAt == nil {
            prayerRows[index].hiddenAt = .now
        }
        if let index = postRows.firstIndex(where: { $0.id == id }), postRows[index].hiddenAt == nil {
            postRows[index].hiddenAt = .now
        }
    }

    func remove(_ kind: ContentKind, id: UUID) async throws {
        // Like the server: your own, or someone you may moderate (moderators
        // can't remove a moderator's or the owner's posts).
        prayerRows.removeAll { $0.id == id && ($0.userID == me || canModerate($0.userID, in: $0.groupID)) }
        postRows.removeAll { $0.id == id && ($0.userID == me || canModerate($0.userID, in: $0.groupID)) }
        announcementRows.removeAll { $0.id == id && ($0.userID == me || canModerate($0.userID, in: $0.groupID)) }
        communityRows.removeAll { $0.id == id && $0.isMine }
        commentRows.removeAll { $0.id == id && $0.userID == me }
    }

    // MARK: Groups

    func myGroups() async throws -> [GroupSummary] {
        groups.values.compactMap { group in
            guard let membership = member(me, in: group.id) else { return nil }
            var mine = group
            mine.role = membership.role
            mine.isOwner = group.ownerID == me
            return mine
        }
        .sorted { $0.name < $1.name }
    }

    func createGroup(_ draft: GroupDraft) async throws -> UUID {
        let profile = try requireProfile()
        try check(draft.name)
        let id = UUID()
        var books: [Int]?
        var days: Int?
        if case let .custom(planBooks, planDays)? = draft.plan?.kind {
            books = planBooks
            days = planDays
        }
        groups[id] = GroupSummary(
            id: id, name: draft.name, description: draft.description, inviteCode: "TEST" + String(id.uuidString.prefix(6)),
            planID: draft.plan?.id, planTitle: draft.plan?.title, planBooks: books, planDays: days,
            planStart: draft.plan == nil ? nil : Calendar.current.startOfDay(for: draft.planStart), role: .leader, notifications: true,
            ownerID: me
        )
        members[id] = [GroupMember(groupID: id, userID: me, role: .leader, displayName: profile.displayName, joinedAt: now())]
        return id
    }

    func requestToJoin(code: String) async throws -> GroupJoinOutcome {
        let profile = try requireProfile()
        let cleaned = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard let group = groups.values.first(where: { $0.inviteCode == cleaned }) else {
            throw CommunityError.message(String(localized: "That invite code wasn't found. Check it with your group leader."))
        }
        if isBanned(me, from: group.id) {
            throw CommunityError.message(String(localized: "You can't join this group."))
        }
        if myRole(in: group.id) != nil {
            // Already in: any request left over is stale.
            requests.removeAll { $0.groupID == group.id && $0.userID == me }
            return GroupJoinOutcome(groupID: group.id, name: group.name, status: .joined)
        }
        if group.requiresApproval {
            // Asking again is fine, whatever the limit.
            if requests.contains(where: { $0.groupID == group.id && $0.userID == me }) {
                return GroupJoinOutcome(groupID: group.id, name: group.name, status: .requested)
            }
            guard requests.filter({ $0.userID == me }).count < 20 else {
                throw CommunityError.message(String(localized: "You've asked to join a lot of groups, so withdraw a request or wait for an answer first."))
            }
            requests.append(GroupJoinRequest(groupID: group.id, userID: me, displayName: profile.displayName, createdAt: now(), groupName: group.name))
            return GroupJoinOutcome(groupID: group.id, name: group.name, status: .requested)
        }
        members[group.id, default: []].append(GroupMember(groupID: group.id, userID: me, role: .member, displayName: profile.displayName, joinedAt: now()))
        requests.removeAll { $0.groupID == group.id && $0.userID == me }
        return GroupJoinOutcome(groupID: group.id, name: group.name, status: .joined)
    }

    func updateGroup(_ group: UUID, draft: GroupDraft) async throws {
        guard isLeader(group), var existing = groups[group] else { throw CommunityError.message(String(localized: "Only group leaders can do that.")) }
        existing.name = draft.name
        existing.description = draft.description
        existing.planID = draft.plan?.id
        existing.planTitle = draft.plan?.title
        existing.planStart = draft.plan == nil ? nil : draft.planStart
        groups[group] = existing
    }

    func newInviteCode(_ group: UUID) async throws -> String {
        guard isLeader(group) else { throw CommunityError.message(String(localized: "Only group leaders can do that.")) }
        let code = newCode()
        groups[group]?.inviteCode = code
        return code
    }

    func leaveGroup(_ group: UUID) async throws {
        members[group]?.removeAll { $0.userID == me }
        afterLeaving(me, group: group)
    }

    func deleteGroup(_ group: UUID) async throws {
        guard isOwner(group) else { throw Self.ownerOnly }
        groups[group] = nil
        members[group] = nil
        requests.removeAll { $0.groupID == group }
    }

    func members(of group: UUID) async throws -> [GroupMember] {
        members[group] ?? []
    }

    func setRole(_ role: GroupRole, for user: UUID, in group: UUID) async throws {
        guard isOwner(group) else { throw Self.ownerOnly }
        guard user != me else { throw CommunityError.message(String(localized: "Make someone else the owner first.")) }
        updateMember(user, in: group) { member in
            member.role = role
            if role == .leader { member.mutedUntil = nil }
        }
    }

    func removeMember(_ user: UUID, from group: UUID) async throws {
        guard user != me else { throw CommunityError.message(String(localized: "To leave the group, use Leave Group.")) }
        guard canModerate(user, in: group) else { throw Self.notAllowed }
        members[group]?.removeAll { $0.userID == user }
        // A new code, so they can't simply rejoin with the old one.
        groups[group]?.inviteCode = newCode()
    }

    func setNotifications(_ on: Bool, for group: UUID) async throws {
        groups[group]?.notifications = on
    }

    func progress(in group: UUID, day: Int) async throws -> [GroupProgress] {
        (progressRows[group] ?? []).compactMap { key in
            let parts = key.split(separator: "|")
            guard parts.count == 2, let user = UUID(uuidString: String(parts[0])), Int(parts[1]) == day else { return nil }
            return GroupProgress(userID: user, day: day)
        }
    }

    func setDayDone(_ done: Bool, day: Int, in group: UUID) async throws {
        let key = "\(me.uuidString)|\(day)"
        if done { progressRows[group, default: []].insert(key) } else { progressRows[group]?.remove(key) }
    }

    func myReadDays(in group: UUID) async throws -> Set<Int> {
        let mine = Substring(me.uuidString)
        return Set((progressRows[group] ?? []).compactMap { key -> Int? in
            let parts = key.split(separator: "|")
            guard parts.count == 2, parts[0] == mine else { return nil }
            return Int(parts[1])
        })
    }

    func progressSummary(in group: UUID) async throws -> [MemberProgress] {
        let rows = (progressRows[group] ?? []).compactMap { key -> (UUID, Int)? in
            let parts = key.split(separator: "|")
            guard parts.count == 2, let user = UUID(uuidString: String(parts[0])), let day = Int(parts[1]) else { return nil }
            return (user, day)
        }
        return (members[group] ?? []).map { member in
            let days = rows.filter { $0.0 == member.userID }.map(\.1)
            return MemberProgress(userID: member.userID, daysDone: days.count, lastDay: days.max() ?? 0)
        }
    }

    /// Hidden content stays visible to its author and the group's moderators.
    private func canSee(hiddenAt: Date?, author: UUID, group: UUID) -> Bool {
        hiddenAt == nil || author == me || isLeader(group)
    }

    func prayers(in group: UUID) async throws -> [GroupPrayer] {
        prayerRows
            .filter { $0.groupID == group && canSee(hiddenAt: $0.hiddenAt, author: $0.userID, group: group) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func myPrayerMarks(_ prayers: [UUID]) async throws -> Set<UUID> {
        marks.intersection(prayers)
    }

    /// The name to post under; muted members are refused like the server's
    /// row-level security refuses them.
    private func posterName(in group: UUID) throws -> String {
        guard let membership = member(me, in: group) else { throw Self.notAllowed }
        if membership.isMuted() { throw Self.refused }
        return membership.displayName
    }

    func addPrayer(_ body: String, to group: UUID) async throws {
        try check(body)
        let name = try posterName(in: group)
        prayerRows.append(GroupPrayer(id: UUID(), groupID: group, userID: me, displayName: name, body: body, prayedCount: 0, createdAt: now(), answeredAt: nil))
    }

    func setPrayed(_ prayed: Bool, prayer: UUID) async throws {
        guard let index = prayerRows.firstIndex(where: { $0.id == prayer }) else { return }
        if prayed, !marks.contains(prayer) {
            marks.insert(prayer)
            prayerRows[index].prayedCount += 1
        } else if !prayed, marks.contains(prayer) {
            marks.remove(prayer)
            prayerRows[index].prayedCount -= 1
        }
    }

    func setAnswered(_ answered: Bool, prayer: UUID) async throws {
        guard let index = prayerRows.firstIndex(where: { $0.id == prayer && $0.userID == me }) else { throw Self.notAllowed }
        prayerRows[index].answeredAt = answered ? .now : nil
    }

    func posts(in group: UUID) async throws -> [GroupPost] {
        postRows.filter { $0.groupID == group && canSee(hiddenAt: $0.hiddenAt, author: $0.userID, group: group) }
    }

    func addPost(_ body: String, day: Int?, to group: UUID) async throws {
        try check(body)
        let name = try posterName(in: group)
        postRows.append(GroupPost(id: UUID(), groupID: group, userID: me, displayName: name, day: day, body: body, createdAt: now()))
    }

    func announcements(in group: UUID) async throws -> [GroupAnnouncement] {
        announcementRows.filter { $0.groupID == group }.sorted { $0.createdAt > $1.createdAt }
    }

    func addAnnouncement(title: String, body: String, to group: UUID) async throws {
        guard isLeader(group), let name = member(me, in: group)?.displayName else {
            throw CommunityError.message(String(localized: "Only group leaders can do that."))
        }
        try check(title + " " + body)
        announcementRows.append(GroupAnnouncement(id: UUID(), groupID: group, userID: me, displayName: name, title: title, body: body, createdAt: now()))
    }

    // MARK: Group moderation

    func myJoinRequests() async throws -> [GroupJoinRequest] {
        requests.filter { $0.userID == me }.sorted { $0.createdAt > $1.createdAt }
    }

    func withdrawJoinRequest(to group: UUID) async throws {
        requests.removeAll { $0.groupID == group && $0.userID == me }
    }

    func joinRequests(in group: UUID) async throws -> [GroupJoinRequest] {
        // Like the server: your own, or all of them if you moderate.
        requests.filter { $0.groupID == group && (isLeader(group) || $0.userID == me) }
    }

    func answerJoinRequest(from user: UUID, in group: UUID, accept: Bool) async throws {
        guard isLeader(group) else { throw Self.moderatorsOnly }
        guard let request = requests.first(where: { $0.groupID == group && $0.userID == user }) else { throw Self.notFound }
        requests.removeAll { $0.groupID == group && $0.userID == user }
        guard accept else { return }
        if isBanned(user, from: group) { throw CommunityError.message(String(localized: "You can't join this group.")) }
        if member(user, in: group) == nil {
            let name = profiles[user]?.displayName ?? request.displayName
            members[group, default: []].append(GroupMember(groupID: group, userID: user, role: .member, displayName: name, joinedAt: now()))
        }
    }

    func setRequiresApproval(_ required: Bool, for group: UUID) async throws {
        guard isLeader(group) else { throw Self.moderatorsOnly }
        groups[group]?.requiresApproval = required
        guard !required else { return }
        // Opening the group lets in everyone waiting (not the banned), up to 500 members.
        let waiting = requests
            .filter { $0.groupID == group && !isBanned($0.userID, from: group) && member($0.userID, in: group) == nil }
            .sorted { $0.createdAt < $1.createdAt }
        for request in waiting where (members[group]?.count ?? 0) < 500 {
            let name = profiles[request.userID]?.displayName ?? request.displayName
            members[group, default: []].append(GroupMember(groupID: group, userID: request.userID, role: .member, displayName: name, joinedAt: now()))
        }
        requests.removeAll { $0.groupID == group }
    }

    func transferOwnership(of group: UUID, to user: UUID) async throws {
        guard isOwner(group) else { throw Self.ownerOnly }
        guard user != me else { return }
        guard member(user, in: group) != nil else { throw CommunityError.message(String(localized: "They're no longer in this group.")) }
        updateMember(user, in: group) { member in
            member.role = .leader
            member.mutedUntil = nil
        }
        groups[group]?.ownerID = user
    }

    func banMember(_ user: UUID, from group: UUID, reason: String) async throws {
        guard user != me else { throw CommunityError.message(String(localized: "To leave the group, use Leave Group.")) }
        guard canModerate(user, in: group) else { throw Self.notAllowed }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 300 else { throw CommunityError.message(String(localized: "Keep the reason under 300 characters.")) }
        let name = member(user, in: group)?.displayName ?? requests.first { $0.groupID == group && $0.userID == user }?.displayName
        guard let name else { throw Self.notFound }
        bansByGroup[group, default: []].removeAll { $0.userID == user }
        bansByGroup[group, default: []].insert(GroupBan(groupID: group, userID: user, displayName: name, reason: trimmed, createdAt: now()), at: 0)
        members[group]?.removeAll { $0.userID == user }
        requests.removeAll { $0.groupID == group && $0.userID == user }
    }

    func unbanMember(_ user: UUID, from group: UUID) async throws {
        guard isLeader(group) else { throw Self.moderatorsOnly }
        bansByGroup[group]?.removeAll { $0.userID == user }
    }

    func bans(in group: UUID) async throws -> [GroupBan] {
        isLeader(group) ? (bansByGroup[group] ?? []) : []
    }

    func muteMember(_ user: UUID, in group: UUID, hours: Int) async throws {
        guard canModerate(user, in: group) else { throw Self.notAllowed }
        guard (0...720).contains(hours) else { throw CommunityError.message(String(localized: "Choose how long to mute them for.")) }
        updateMember(user, in: group) { member in
            member.mutedUntil = hours == 0 ? nil : Date.now.addingTimeInterval(Double(hours) * 3_600)
        }
    }

    func reports(in group: UUID) async throws -> [GroupReport] {
        guard isLeader(group) else { throw Self.moderatorsOnly }
        let openRows = reportRows.filter { $0.group == group && !$0.resolved }
        var seen: Set<UUID> = []
        var result: [GroupReport] = []
        for row in openRows where !seen.contains(row.id) {
            seen.insert(row.id)
            guard let content = reportedContent(row.kind, id: row.id) else { continue }
            let rows = openRows.filter { $0.id == row.id }
            result.append(GroupReport(
                contentType: row.kind.rawValue, contentID: row.id, authorID: content.author, authorName: content.name,
                body: content.body, reportCount: Set(rows.map(\.reporter)).count,
                reasons: rows.map(\.reason).filter { !$0.isEmpty },
                lastReportedAt: rows.map(\.createdAt).max(), hidden: content.hidden
            ))
        }
        return result.sorted { ($0.lastReportedAt ?? .distantPast) > ($1.lastReportedAt ?? .distantPast) }
    }

    private func reportedContent(_ kind: ContentKind, id: UUID) -> (author: UUID, name: String, body: String, hidden: Bool)? {
        switch kind {
        case .groupPrayer:
            guard let row = prayerRows.first(where: { $0.id == id }) else { return nil }
            return (row.userID, row.displayName, row.body, row.hiddenAt != nil)
        case .groupPost:
            guard let row = postRows.first(where: { $0.id == id }) else { return nil }
            return (row.userID, row.displayName, row.body, row.hiddenAt != nil)
        case .groupAnnouncement:
            guard let row = announcementRows.first(where: { $0.id == id }) else { return nil }
            return (row.userID, row.displayName, row.title + "\n" + row.body, false)
        case .communityPost, .communityComment:
            return nil
        }
    }

    func reviewReport(_ kind: ContentKind, id: UUID, action: ReportAction) async throws {
        guard let group = contentGroup(of: kind, id: id), isLeader(group) else { throw Self.moderatorsOnly }
        switch action {
        case .remove:
            prayerRows.removeAll { $0.id == id }
            postRows.removeAll { $0.id == id }
            announcementRows.removeAll { $0.id == id }
        case .keep:
            if let index = prayerRows.firstIndex(where: { $0.id == id }) { prayerRows[index].hiddenAt = nil }
            if let index = postRows.firstIndex(where: { $0.id == id }) { postRows[index].hiddenAt = nil }
        }
        switch action {
        case .remove:
            // Closed.
            for index in reportRows.indices where reportRows[index].id == id {
                reportRows[index].resolved = true
            }
        case .keep:
            // Cleared, so people can report it again if it becomes a problem.
            reportRows.removeAll { $0.id == id && !$0.resolved }
        }
    }

    // MARK: Community

    func feed(_ kind: CommunityPostKind, before: Date?) async throws -> [CommunityPost] {
        communityRows
            .filter { post in
                let author = postAuthors[post.id] ?? neighbour
                return post.kind == kind && !blocks.contains(author) && (openReporters(of: post.id).count < 3 || post.isMine)
            }
            .filter { before == nil || $0.createdAt < before! }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func myReactions(_ posts: [UUID]) async throws -> Set<UUID> {
        reactions.intersection(posts)
    }

    func addCommunityPost(_ draft: CommunityDraft) async throws {
        guard let profile = profileRow, profile.hasAcceptedTerms else { throw CommunityError.message(String(localized: "Accept the community guidelines first.")) }
        try check(draft.body)
        let id = UUID()
        postAuthors[id] = me
        communityRows.append(CommunityPost(
            id: id, authorID: me, isMine: true, kind: draft.kind, body: draft.body,
            startVerse: draft.start?.rawValue, endVerse: (draft.end ?? draft.start)?.rawValue,
            displayName: draft.isAnonymous ? "Someone" : profile.displayName,
            reactionCount: 0, commentCount: 0, createdAt: .now, hiddenAt: nil
        ))
    }

    func setReacted(_ reacted: Bool, post: UUID) async throws {
        guard let index = communityRows.firstIndex(where: { $0.id == post }) else { return }
        if reacted, !reactions.contains(post) {
            reactions.insert(post)
            communityRows[index].reactionCount += 1
        } else if !reacted, reactions.contains(post) {
            reactions.remove(post)
            communityRows[index].reactionCount -= 1
        }
    }

    func comments(on post: UUID) async throws -> [CommunityComment] {
        commentRows.filter { $0.postID == post && !blocks.contains($0.userID) }
    }

    func addComment(_ body: String, on post: UUID) async throws {
        guard let profile = profileRow, profile.hasAcceptedTerms else { throw CommunityError.message(String(localized: "Accept the community guidelines first.")) }
        try check(body)
        commentRows.append(CommunityComment(id: UUID(), postID: post, userID: me, displayName: profile.displayName, body: body, createdAt: .now))
        if let index = communityRows.firstIndex(where: { $0.id == post }) { communityRows[index].commentCount += 1 }
    }

    func registerPushToken(_ token: String, sandbox: Bool) async throws {}
    func unregisterPushToken(_ token: String) async throws {}
}

/// No account (Supabase isn't configured, or a UI test of the signed-out
/// screens): every action asks the person to sign in.
struct SignedOutCommunityBackend: CommunityBackend {
    func currentUserID() async -> UUID? { nil }
    func profile() async throws -> CommunityProfile? { nil }
    func setDisplayName(_ name: String) async throws { throw CommunityError.signInRequired }
    func acceptCommunityTerms() async throws { throw CommunityError.signInRequired }
    func blockedUsers() async throws -> Set<UUID> { [] }
    func block(_ user: UUID) async throws { throw CommunityError.signInRequired }
    func blockAuthor(ofPost post: UUID) async throws { throw CommunityError.signInRequired }
    func unblock(_ user: UUID) async throws { throw CommunityError.signInRequired }
    func report(_ kind: ContentKind, id: UUID, reason: String) async throws { throw CommunityError.signInRequired }
    func remove(_ kind: ContentKind, id: UUID) async throws { throw CommunityError.signInRequired }
    func myGroups() async throws -> [GroupSummary] { [] }
    func createGroup(_ draft: GroupDraft) async throws -> UUID { throw CommunityError.signInRequired }
    func requestToJoin(code: String) async throws -> GroupJoinOutcome { throw CommunityError.signInRequired }
    func updateGroup(_ group: UUID, draft: GroupDraft) async throws { throw CommunityError.signInRequired }
    func newInviteCode(_ group: UUID) async throws -> String { throw CommunityError.signInRequired }
    func leaveGroup(_ group: UUID) async throws { throw CommunityError.signInRequired }
    func deleteGroup(_ group: UUID) async throws { throw CommunityError.signInRequired }
    func members(of group: UUID) async throws -> [GroupMember] { [] }
    func setRole(_ role: GroupRole, for user: UUID, in group: UUID) async throws { throw CommunityError.signInRequired }
    func removeMember(_ user: UUID, from group: UUID) async throws { throw CommunityError.signInRequired }
    func setNotifications(_ on: Bool, for group: UUID) async throws { throw CommunityError.signInRequired }
    func progress(in group: UUID, day: Int) async throws -> [GroupProgress] { [] }
    func setDayDone(_ done: Bool, day: Int, in group: UUID) async throws { throw CommunityError.signInRequired }
    func progressSummary(in group: UUID) async throws -> [MemberProgress] { [] }
    func myReadDays(in group: UUID) async throws -> Set<Int> { [] }
    func prayers(in group: UUID) async throws -> [GroupPrayer] { [] }
    func myPrayerMarks(_ prayers: [UUID]) async throws -> Set<UUID> { [] }
    func addPrayer(_ body: String, to group: UUID) async throws { throw CommunityError.signInRequired }
    func setPrayed(_ prayed: Bool, prayer: UUID) async throws { throw CommunityError.signInRequired }
    func setAnswered(_ answered: Bool, prayer: UUID) async throws { throw CommunityError.signInRequired }
    func posts(in group: UUID) async throws -> [GroupPost] { [] }
    func addPost(_ body: String, day: Int?, to group: UUID) async throws { throw CommunityError.signInRequired }
    func announcements(in group: UUID) async throws -> [GroupAnnouncement] { [] }
    func addAnnouncement(title: String, body: String, to group: UUID) async throws { throw CommunityError.signInRequired }
    func myJoinRequests() async throws -> [GroupJoinRequest] { [] }
    func withdrawJoinRequest(to group: UUID) async throws { throw CommunityError.signInRequired }
    func joinRequests(in group: UUID) async throws -> [GroupJoinRequest] { [] }
    func answerJoinRequest(from user: UUID, in group: UUID, accept: Bool) async throws { throw CommunityError.signInRequired }
    func setRequiresApproval(_ required: Bool, for group: UUID) async throws { throw CommunityError.signInRequired }
    func transferOwnership(of group: UUID, to user: UUID) async throws { throw CommunityError.signInRequired }
    func banMember(_ user: UUID, from group: UUID, reason: String) async throws { throw CommunityError.signInRequired }
    func unbanMember(_ user: UUID, from group: UUID) async throws { throw CommunityError.signInRequired }
    func bans(in group: UUID) async throws -> [GroupBan] { [] }
    func muteMember(_ user: UUID, in group: UUID, hours: Int) async throws { throw CommunityError.signInRequired }
    func reports(in group: UUID) async throws -> [GroupReport] { [] }
    func reviewReport(_ kind: ContentKind, id: UUID, action: ReportAction) async throws { throw CommunityError.signInRequired }
    func feed(_ kind: CommunityPostKind, before: Date?) async throws -> [CommunityPost] { [] }
    func myReactions(_ posts: [UUID]) async throws -> Set<UUID> { [] }
    func addCommunityPost(_ draft: CommunityDraft) async throws { throw CommunityError.signInRequired }
    func setReacted(_ reacted: Bool, post: UUID) async throws { throw CommunityError.signInRequired }
    func comments(on post: UUID) async throws -> [CommunityComment] { [] }
    func addComment(_ body: String, on post: UUID) async throws { throw CommunityError.signInRequired }
    func registerPushToken(_ token: String, sandbox: Bool) async throws {}
    func unregisterPushToken(_ token: String) async throws {}
}
