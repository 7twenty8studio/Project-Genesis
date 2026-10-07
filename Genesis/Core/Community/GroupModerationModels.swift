import Foundation

// Group owners, moderators and moderation tools. Rows mirror
// supabase/migrations/20261011000000_group_moderation_challenges.sql.
//
// Every group has one owner (groups.owner_id). Moderators are members whose
// role is 'leader' (the owner's role is 'leader' too), so `GroupRole.leader`
// means "moderator or owner" and is shown as Moderator.

/// How someone stands in a group, as people see it.
enum GroupStanding: Sendable, Hashable {
    case owner, moderator, member

    var title: String {
        switch self {
        case .owner: String(localized: "Owner", comment: "Group role: the one person who owns a group")
        case .moderator: String(localized: "Moderator", comment: "Group role: helps run a group")
        case .member: String(localized: "Member", comment: "Group role: an ordinary member")
        }
    }
}

/// What the signed-in person may do to others in a group. Mirrors the
/// server's genesis_can_moderate: moderators act on members, only the owner
/// acts on moderators, nobody acts on the owner or themselves.
struct GroupPermissions: Sendable, Hashable {
    let me: UUID?
    let ownerID: UUID?
    let myRole: GroupRole?

    init(me: UUID?, ownerID: UUID?, myRole: GroupRole?) {
        self.me = me
        self.ownerID = ownerID
        self.myRole = myRole
    }

    init(group: GroupSummary, me: UUID?) {
        self.init(me: me, ownerID: group.ownerID, myRole: group.role)
    }

    var isOwner: Bool { me != nil && ownerID == me }
    /// A moderator or the owner.
    var isModerator: Bool { myRole == .leader }

    func standing(of member: GroupMember) -> GroupStanding {
        if let ownerID, member.userID == ownerID { return .owner }
        return member.role == .leader ? .moderator : .member
    }

    /// Mute, remove and ban.
    func canModerate(_ member: GroupMember) -> Bool {
        guard let me, member.userID != me, isModerator else { return false }
        if let ownerID, member.userID == ownerID { return false }
        return isOwner || member.role != .leader
    }

    /// Make or unmake a moderator (owner only, never the owner themselves).
    func canChooseRole(of member: GroupMember) -> Bool {
        guard let me, isOwner else { return false }
        return member.userID != me
    }

    /// Hand the group to someone else (owner only).
    func canMakeOwner(_ member: GroupMember) -> Bool {
        canChooseRole(of: member)
    }
}

/// The result of using an invite code: in straight away, or asked to join a
/// group that approves its members.
struct GroupJoinOutcome: Decodable, Hashable, Sendable {
    enum Status: String, Decodable, Sendable {
        case joined, requested
    }

    let groupID: UUID
    let name: String
    let status: Status

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case name, status
    }
}

/// Someone waiting to be let into a group.
struct GroupJoinRequest: Identifiable, Codable, Hashable, Sendable {
    let groupID: UUID
    let userID: UUID
    let displayName: String
    let createdAt: Date
    /// The group's name, so the person waiting can see which group it is
    /// (they can't read the group itself until they're in).
    var groupName: String = ""

    var id: String { groupID.uuidString + "|" + userID.uuidString }

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case displayName = "display_name"
        case createdAt = "created_at"
        case groupName = "group_name"
    }
}

/// Someone kept out of a group, whatever invite code they have.
struct GroupBan: Identifiable, Codable, Hashable, Sendable {
    let groupID: UUID
    let userID: UUID
    let displayName: String
    let reason: String
    let createdAt: Date

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case displayName = "display_name"
        case reason
        case createdAt = "created_at"
    }
}

/// One reported post, prayer request or announcement in a group, with its
/// open reports (never who made them). From group_reports().
struct GroupReport: Identifiable, Hashable, Sendable {
    let contentType: String
    let contentID: UUID
    let authorID: UUID?
    let authorName: String
    let body: String
    let reportCount: Int
    let reasons: [String]
    let lastReportedAt: Date?
    let hidden: Bool

    var id: UUID { contentID }
    var kind: ContentKind? { ContentKind(rawValue: contentType) }

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case contentID = "content_id"
        case authorID = "author_id"
        case authorName = "author_name"
        case body
        case reportCount = "report_count"
        case reasons
        case lastReportedAt = "last_reported_at"
        case hidden
    }
}

extension GroupReport: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentType = try container.decode(String.self, forKey: .contentType)
        contentID = try container.decode(UUID.self, forKey: .contentID)
        authorID = try container.decodeIfPresent(UUID.self, forKey: .authorID)
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        reportCount = try container.decodeIfPresent(Int.self, forKey: .reportCount) ?? 0
        reasons = try container.decodeIfPresent([String].self, forKey: .reasons) ?? []
        lastReportedAt = try container.decodeIfPresent(Date.self, forKey: .lastReportedAt)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }
}

/// What a moderator decides about reported content.
enum ReportAction: String, Sendable {
    /// Takes it down.
    case remove
    /// Shows it again.
    case keep
}

/// How long a member is muted for (mute_member takes 1 to 720 hours).
enum MuteDuration: Int, CaseIterable, Identifiable, Sendable {
    case hour = 1
    case day = 24
    case week = 168

    var id: Int { rawValue }
    var hours: Int { rawValue }

    var title: String {
        switch self {
        case .hour: String(localized: "For 1 Hour")
        case .day: String(localized: "For 1 Day")
        case .week: String(localized: "For 1 Week")
        }
    }
}
