import Foundation

// Church groups and the public community. Rows mirror the Supabase tables in
// supabase/migrations/20261003000000_groups_community.sql.

/// Your name as others see it, and whether you've accepted the community
/// guidelines.
struct CommunityProfile: Codable, Hashable, Sendable {
    let userID: UUID
    var displayName: String
    var communityTermsAcceptedAt: Date?

    var hasAcceptedTerms: Bool { communityTermsAcceptedAt != nil }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case communityTermsAcceptedAt = "community_terms_accepted_at"
    }
}

enum GroupRole: String, Codable, Sendable {
    case leader, member
}

/// A group you belong to, with your role in it.
struct GroupSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var description: String
    var inviteCode: String
    var planID: String?
    var planTitle: String?
    var planBooks: [Int]?
    var planDays: Int?
    var planStart: Date?
    var role: GroupRole
    var notifications: Bool

    var isLeader: Bool { role == .leader }

    /// The group's reading plan, if it has one.
    var plan: ReadingPlan? {
        if let planID, let builtIn = ReadingPlan.builtIn(id: planID) { return builtIn }
        // Only real books, and a sensible length, whatever the server holds.
        let books = (planBooks ?? []).filter { (1...66).contains($0) }
        guard !books.isEmpty, let planDays, (1...730).contains(planDays) else { return nil }
        return ReadingPlan.custom(id: planID ?? "group-\(id.uuidString.lowercased())", title: planTitle ?? "Group plan", books: books, days: planDays)
    }

    /// Today's day number in the plan (1-based), 0 before it starts, nil
    /// without a plan. Past the end it stays on the last day.
    func planDay(on date: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let plan, let planStart else { return nil }
        let start = calendar.startOfDay(for: planStart)
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
        if days < 0 { return 0 }
        return min(days + 1, plan.dayCount)
    }

    /// The invite code as people type it: ABCDE-12345.
    var formattedInviteCode: String {
        guard inviteCode.count == 10 else { return inviteCode }
        return "\(inviteCode.prefix(5))-\(inviteCode.suffix(5))"
    }
}

/// What a leader fills in to create or edit a group.
struct GroupDraft: Hashable, Sendable {
    var name: String = ""
    var description: String = ""
    var plan: ReadingPlan?
    var planStart: Date = .now
}

struct GroupMember: Identifiable, Codable, Hashable, Sendable {
    let groupID: UUID
    let userID: UUID
    var role: GroupRole
    var displayName: String
    let joinedAt: Date

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case role
        case displayName = "display_name"
        case joinedAt = "joined_at"
    }
}

/// Who has read a plan day.
struct GroupProgress: Codable, Hashable, Sendable {
    let userID: UUID
    let day: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case day
    }
}

struct GroupPrayer: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let groupID: UUID
    let userID: UUID
    let displayName: String
    let body: String
    var prayedCount: Int
    let createdAt: Date
    var answeredAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case userID = "user_id"
        case displayName = "display_name"
        case body
        case prayedCount = "prayed_count"
        case createdAt = "created_at"
        case answeredAt = "answered_at"
    }
}

/// A message in a group's discussion; `day` ties it to a plan day.
struct GroupPost: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let groupID: UUID
    let userID: UUID
    let displayName: String
    let day: Int?
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case userID = "user_id"
        case displayName = "display_name"
        case day, body
        case createdAt = "created_at"
    }
}

struct GroupAnnouncement: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let groupID: UUID
    let userID: UUID
    let displayName: String
    let title: String
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case userID = "user_id"
        case displayName = "display_name"
        case title, body
        case createdAt = "created_at"
    }
}

enum CommunityPostKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case prayer, reflection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prayer: "Prayer Wall"
        case .reflection: "Reflections"
        }
    }

    /// The reaction: "I prayed" on a prayer request, "Amen" on a reflection.
    var reactionTitle: String {
        switch self {
        case .prayer: "I prayed"
        case .reflection: "Amen"
        }
    }

    var reactionSymbol: String {
        switch self {
        case .prayer: "hands.and.sparkles"
        case .reflection: "heart"
        }
    }
}

struct CommunityPost: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// Nil on someone else's anonymous post: the server never says who.
    let authorID: UUID?
    let isMine: Bool
    let kind: CommunityPostKind
    let body: String
    let startVerse: Int?
    let endVerse: Int?
    let displayName: String
    var reactionCount: Int
    var commentCount: Int
    let createdAt: Date
    let hiddenAt: Date?

    /// The passage a post is about (verse 0 means the whole chapter).
    var reference: PassageReference? {
        guard let startVerse, (1...66).contains(startVerse / 1_000_000) else { return nil }
        let start = VerseID(rawValue: startVerse)
        if start.verse == 0 {
            return PassageReference(book: .withNumber(start.book), chapter: start.chapter)
        }
        let end = VerseID(rawValue: endVerse ?? startVerse)
        return PassageReference(verses: [start, end])
    }

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case isMine = "is_mine"
        case kind, body
        case startVerse = "start_verse"
        case endVerse = "end_verse"
        case displayName = "display_name"
        case reactionCount = "reaction_count"
        case commentCount = "comment_count"
        case createdAt = "created_at"
        case hiddenAt = "hidden_at"
    }
}

/// What someone fills in to post to the community.
struct CommunityDraft: Hashable, Sendable {
    var kind: CommunityPostKind
    var body: String = ""
    var start: VerseID?
    var end: VerseID?
    var isAnonymous = false
}

struct CommunityComment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let postID: UUID
    let userID: UUID
    let displayName: String
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case userID = "user_id"
        case displayName = "display_name"
        case body
        case createdAt = "created_at"
    }
}

/// Anything people post, for reporting and removing.
enum ContentKind: String, Codable, Sendable {
    case communityPost = "community_post"
    case communityComment = "community_comment"
    case groupPrayer = "group_prayer"
    case groupPost = "group_post"
    case groupAnnouncement = "group_announcement"
}

enum CommunityError: LocalizedError, Equatable {
    case signInRequired
    case notConfigured
    case offline
    /// It was already there (a second report, "I prayed" twice).
    case duplicate
    case message(String)

    var errorDescription: String? {
        switch self {
        case .signInRequired: "Sign in to join groups and the community."
        case .notConfigured: "Groups and the community aren't set up in this build."
        case .offline: "You're offline. Groups and the community need an internet connection."
        case .duplicate: "That's already done."
        case let .message(text): text
        }
    }

    /// Turns the database's short error codes into something to show people.
    static func from(_ error: Error) -> CommunityError {
        if let error = error as? CommunityError { return error }
        if let error = error as? URLError, [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            return .offline
        }
        guard case let .http(status, message)? = error as? SupabaseError else {
            return .message(error.localizedDescription)
        }
        let friendly: [String: String] = [
            "objectionable_content": "Please rephrase. Some words aren't allowed in Genesis.",
            "rate_limited": "You've posted a lot in the last hour. Please try again later.",
            "name_required": "Choose a display name first.",
            "invalid_name": "Display names are 1 to 40 characters.",
            "invalid_code": "That invite code wasn't found. Check it with your group leader.",
            "group_full": "This group is full.",
            "groups_off": "Groups aren't available right now.",
            "too_many_groups": "You've created the most groups one person can lead.",
            "leaders_only": "Only group leaders can do that.",
            "last_leader": "Make someone else a leader first.",
            "not_allowed": "You can't do that.",
            "not_found": "That's no longer there.",
            "not_signed_in": "Sign in first.",
        ]
        if let text = friendly[message] { return .message(text) }
        if status == 409 || message.contains("duplicate key") { return .duplicate }
        if status == 401 { return .signInRequired }
        if status == 403 || message.contains("row-level security") {
            return .message("That isn't allowed. If you were removed from a group or the community is closed, pull to refresh.")
        }
        return .message("Something went wrong. Please try again.")
    }
}
