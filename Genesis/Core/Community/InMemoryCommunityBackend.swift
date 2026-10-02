import Foundation

/// Groups and community kept in memory, for UI tests: no network, no
/// account, repeatable. Mirrors the server's rules closely enough to test the
/// screens (leaders only for announcements, one reaction each, reports hide
/// after three, blocked people disappear).
actor InMemoryCommunityBackend: CommunityBackend {
    private let me = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    private let neighbour = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!

    private var profileRow: CommunityProfile?
    private var blocks: Set<UUID> = []
    private var reports: [UUID: Int] = [:]
    private var groups: [UUID: GroupSummary] = [:]
    private var members: [UUID: [GroupMember]] = [:]
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
    /// A group that exists for "join with a code".
    static let sampleInviteCode = "GRACE12345"

    init() {
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
        groups[groupID] = GroupSummary(
            id: groupID, name: "Grace Fellowship", description: "Wednesday evening study.",
            inviteCode: Self.sampleInviteCode, planID: ReadingPlan.gospelsID, planTitle: nil, planBooks: nil, planDays: nil,
            planStart: Calendar.current.date(byAdding: .day, value: -2, to: .now), role: .member, notifications: true
        )
        members[groupID] = [GroupMember(groupID: groupID, userID: neighbour, role: .leader, displayName: "Pastor Ruth", joinedAt: .now.addingTimeInterval(-86_400 * 30))]
        announcementRows = [GroupAnnouncement(id: UUID(), groupID: groupID, userID: neighbour, displayName: "Pastor Ruth", title: "Welcome!", body: "We meet Wednesdays at 7.", createdAt: .now.addingTimeInterval(-3_600))]
        defer { for post in communityRows { postAuthors[post.id] = post.authorID } }
        communityRows = [
            CommunityPost(id: UUID(), authorID: neighbour, isMine: false, kind: .prayer, body: "Please pray for my father's surgery on Friday.", startVerse: nil, endVerse: nil, displayName: "Ruth", reactionCount: 4, commentCount: 0, createdAt: .now.addingTimeInterval(-7_200), hiddenAt: nil),
            CommunityPost(id: UUID(), authorID: neighbour, isMine: false, kind: .reflection, body: "Reading this today reminded me how patient God is with us.", startVerse: 19_103_008, endVerse: 19_103_008, displayName: "Ruth", reactionCount: 2, commentCount: 0, createdAt: .now.addingTimeInterval(-9_000), hiddenAt: nil),
        ]
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

    private func myRole(in group: UUID) -> GroupRole? {
        members[group]?.first { $0.userID == me }?.role
    }

    // MARK: Profile and safety

    func currentUserID() async -> UUID? { me }

    func profile() async throws -> CommunityProfile? { profileRow }

    func setDisplayName(_ name: String) async throws {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(cleaned.count) else { throw CommunityError.message(String(localized: "Display names are 1 to 40 characters.")) }
        try check(cleaned)
        profileRow = CommunityProfile(userID: me, displayName: cleaned, communityTermsAcceptedAt: profileRow?.communityTermsAcceptedAt)
        for (group, list) in members {
            members[group] = list.map { member in
                var member = member
                if member.userID == me { member.displayName = cleaned }
                return member
            }
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

    func report(_ kind: ContentKind, id: UUID, reason: String) async throws {
        reports[id, default: 0] += 1
    }

    func remove(_ kind: ContentKind, id: UUID) async throws {
        prayerRows.removeAll { $0.id == id && ($0.userID == me || myRole(in: $0.groupID) == .leader) }
        postRows.removeAll { $0.id == id && ($0.userID == me || myRole(in: $0.groupID) == .leader) }
        announcementRows.removeAll { $0.id == id && ($0.userID == me || myRole(in: $0.groupID) == .leader) }
        communityRows.removeAll { $0.id == id && $0.isMine }
        commentRows.removeAll { $0.id == id && $0.userID == me }
    }

    // MARK: Groups

    func myGroups() async throws -> [GroupSummary] {
        groups.values.compactMap { group in
            guard let member = members[group.id]?.first(where: { $0.userID == me }) else { return nil }
            var mine = group
            mine.role = member.role
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
            planStart: draft.plan == nil ? nil : Calendar.current.startOfDay(for: draft.planStart), role: .leader, notifications: true
        )
        members[id] = [GroupMember(groupID: id, userID: me, role: .leader, displayName: profile.displayName, joinedAt: .now)]
        return id
    }

    func joinGroup(code: String) async throws -> UUID {
        let profile = try requireProfile()
        let cleaned = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard let group = groups.values.first(where: { $0.inviteCode == cleaned }) else {
            throw CommunityError.message(String(localized: "That invite code wasn't found. Check it with your group leader."))
        }
        if myRole(in: group.id) == nil {
            members[group.id, default: []].append(GroupMember(groupID: group.id, userID: me, role: .member, displayName: profile.displayName, joinedAt: .now))
        }
        return group.id
    }

    func updateGroup(_ group: UUID, draft: GroupDraft) async throws {
        guard myRole(in: group) == .leader, var existing = groups[group] else { throw CommunityError.message(String(localized: "Only group leaders can do that.")) }
        existing.name = draft.name
        existing.description = draft.description
        existing.planID = draft.plan?.id
        existing.planTitle = draft.plan?.title
        existing.planStart = draft.plan == nil ? nil : draft.planStart
        groups[group] = existing
    }

    func newInviteCode(_ group: UUID) async throws -> String {
        guard myRole(in: group) == .leader else { throw CommunityError.message(String(localized: "Only group leaders can do that.")) }
        let code = "NEW" + String(UUID().uuidString.prefix(7)).uppercased().filter { $0.isLetter || $0.isNumber }
        groups[group]?.inviteCode = code
        return code
    }

    func leaveGroup(_ group: UUID) async throws {
        members[group]?.removeAll { $0.userID == me }
    }

    func deleteGroup(_ group: UUID) async throws {
        guard myRole(in: group) == .leader else { throw CommunityError.message(String(localized: "Only group leaders can do that.")) }
        groups[group] = nil
        members[group] = nil
    }

    func members(of group: UUID) async throws -> [GroupMember] {
        members[group] ?? []
    }

    func setRole(_ role: GroupRole, for user: UUID, in group: UUID) async throws {
        guard myRole(in: group) == .leader else { throw CommunityError.message(String(localized: "Only group leaders can do that.")) }
        members[group] = members[group]?.map { member in
            var member = member
            if member.userID == user { member.role = role }
            return member
        }
    }

    func removeMember(_ user: UUID, from group: UUID) async throws {
        guard myRole(in: group) == .leader else { throw CommunityError.message(String(localized: "Only group leaders can do that.")) }
        members[group]?.removeAll { $0.userID == user }
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

    func prayers(in group: UUID) async throws -> [GroupPrayer] {
        prayerRows.filter { $0.groupID == group }.sorted { $0.createdAt > $1.createdAt }
    }

    func myPrayerMarks(_ prayers: [UUID]) async throws -> Set<UUID> {
        marks.intersection(prayers)
    }

    func addPrayer(_ body: String, to group: UUID) async throws {
        try check(body)
        guard let name = members[group]?.first(where: { $0.userID == me })?.displayName else { throw CommunityError.message(String(localized: "You can't do that.")) }
        prayerRows.append(GroupPrayer(id: UUID(), groupID: group, userID: me, displayName: name, body: body, prayedCount: 0, createdAt: .now, answeredAt: nil))
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
        guard let index = prayerRows.firstIndex(where: { $0.id == prayer && $0.userID == me }) else { throw CommunityError.message(String(localized: "You can't do that.")) }
        prayerRows[index].answeredAt = answered ? .now : nil
    }

    func posts(in group: UUID) async throws -> [GroupPost] {
        postRows.filter { $0.groupID == group }
    }

    func addPost(_ body: String, day: Int?, to group: UUID) async throws {
        try check(body)
        guard let name = members[group]?.first(where: { $0.userID == me })?.displayName else { throw CommunityError.message(String(localized: "You can't do that.")) }
        postRows.append(GroupPost(id: UUID(), groupID: group, userID: me, displayName: name, day: day, body: body, createdAt: .now))
    }

    func announcements(in group: UUID) async throws -> [GroupAnnouncement] {
        announcementRows.filter { $0.groupID == group }.sorted { $0.createdAt > $1.createdAt }
    }

    func addAnnouncement(title: String, body: String, to group: UUID) async throws {
        guard myRole(in: group) == .leader, let name = members[group]?.first(where: { $0.userID == me })?.displayName else {
            throw CommunityError.message(String(localized: "Only group leaders can do that."))
        }
        try check(title + " " + body)
        announcementRows.append(GroupAnnouncement(id: UUID(), groupID: group, userID: me, displayName: name, title: title, body: body, createdAt: .now))
    }

    // MARK: Community

    func feed(_ kind: CommunityPostKind, before: Date?) async throws -> [CommunityPost] {
        communityRows
            .filter { post in
                let author = postAuthors[post.id] ?? neighbour
                return post.kind == kind && !blocks.contains(author) && (reports[post.id, default: 0] < 3 || post.isMine)
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
    func joinGroup(code: String) async throws -> UUID { throw CommunityError.signInRequired }
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
    func prayers(in group: UUID) async throws -> [GroupPrayer] { [] }
    func myPrayerMarks(_ prayers: [UUID]) async throws -> Set<UUID> { [] }
    func addPrayer(_ body: String, to group: UUID) async throws { throw CommunityError.signInRequired }
    func setPrayed(_ prayed: Bool, prayer: UUID) async throws { throw CommunityError.signInRequired }
    func setAnswered(_ answered: Bool, prayer: UUID) async throws { throw CommunityError.signInRequired }
    func posts(in group: UUID) async throws -> [GroupPost] { [] }
    func addPost(_ body: String, day: Int?, to group: UUID) async throws { throw CommunityError.signInRequired }
    func announcements(in group: UUID) async throws -> [GroupAnnouncement] { [] }
    func addAnnouncement(title: String, body: String, to group: UUID) async throws { throw CommunityError.signInRequired }
    func feed(_ kind: CommunityPostKind, before: Date?) async throws -> [CommunityPost] { [] }
    func myReactions(_ posts: [UUID]) async throws -> Set<UUID> { [] }
    func addCommunityPost(_ draft: CommunityDraft) async throws { throw CommunityError.signInRequired }
    func setReacted(_ reacted: Bool, post: UUID) async throws { throw CommunityError.signInRequired }
    func comments(on post: UUID) async throws -> [CommunityComment] { [] }
    func addComment(_ body: String, on post: UUID) async throws { throw CommunityError.signInRequired }
    func registerPushToken(_ token: String, sandbox: Bool) async throws {}
    func unregisterPushToken(_ token: String) async throws {}
}
