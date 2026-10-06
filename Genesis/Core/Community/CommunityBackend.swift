import Foundation

/// Everything groups and the community need from the server. The live
/// version talks to Supabase; UI tests use `InMemoryCommunityBackend`.
protocol CommunityBackend: Sendable {
    /// The signed-in person, or nil.
    func currentUserID() async -> UUID?

    // Profile and safety
    func profile() async throws -> CommunityProfile?
    func setDisplayName(_ name: String) async throws
    func acceptCommunityTerms() async throws
    func blockedUsers() async throws -> Set<UUID>
    func block(_ user: UUID) async throws
    /// Blocks whoever wrote a community post, even an anonymous one.
    func blockAuthor(ofPost post: UUID) async throws
    func unblock(_ user: UUID) async throws
    func report(_ kind: ContentKind, id: UUID, reason: String) async throws
    func remove(_ kind: ContentKind, id: UUID) async throws

    // Groups
    func myGroups() async throws -> [GroupSummary]
    func createGroup(_ draft: GroupDraft) async throws -> UUID
    func joinGroup(code: String) async throws -> UUID
    func updateGroup(_ group: UUID, draft: GroupDraft) async throws
    func newInviteCode(_ group: UUID) async throws -> String
    func leaveGroup(_ group: UUID) async throws
    func deleteGroup(_ group: UUID) async throws
    func members(of group: UUID) async throws -> [GroupMember]
    func setRole(_ role: GroupRole, for user: UUID, in group: UUID) async throws
    func removeMember(_ user: UUID, from group: UUID) async throws
    func setNotifications(_ on: Bool, for group: UUID) async throws
    func progress(in group: UUID, day: Int) async throws -> [GroupProgress]
    func setDayDone(_ done: Bool, day: Int, in group: UUID) async throws
    /// Every member's days read and latest day (group_progress_summary).
    func progressSummary(in group: UUID) async throws -> [MemberProgress]
    func prayers(in group: UUID) async throws -> [GroupPrayer]
    func myPrayerMarks(_ prayers: [UUID]) async throws -> Set<UUID>
    func addPrayer(_ body: String, to group: UUID) async throws
    func setPrayed(_ prayed: Bool, prayer: UUID) async throws
    func setAnswered(_ answered: Bool, prayer: UUID) async throws
    func posts(in group: UUID) async throws -> [GroupPost]
    func addPost(_ body: String, day: Int?, to group: UUID) async throws
    func announcements(in group: UUID) async throws -> [GroupAnnouncement]
    /// Posts an announcement and asks the server to notify members.
    func addAnnouncement(title: String, body: String, to group: UUID) async throws

    // Community
    func feed(_ kind: CommunityPostKind, before: Date?) async throws -> [CommunityPost]
    func myReactions(_ posts: [UUID]) async throws -> Set<UUID>
    func addCommunityPost(_ draft: CommunityDraft) async throws
    func setReacted(_ reacted: Bool, post: UUID) async throws
    func comments(on post: UUID) async throws -> [CommunityComment]
    func addComment(_ body: String, on post: UUID) async throws

    // Notifications
    func registerPushToken(_ token: String, sandbox: Bool) async throws
    /// Stops notifications to this device for the signed-in account.
    func unregisterPushToken(_ token: String) async throws
}

/// Supabase: tables and actions from the groups/community migration.
final class SupabaseCommunityBackend: CommunityBackend {
    private let client: SupabaseClient
    private let auth: AuthService

    init(client: SupabaseClient, auth: AuthService) {
        self.client = client
        self.auth = auth
    }

    func currentUserID() async -> UUID? {
        await auth.user?.id
    }

    // MARK: Plumbing

    private func token() async throws -> String {
        guard await auth.isSignedIn else { throw CommunityError.signInRequired }
        do {
            return try await auth.accessToken()
        } catch {
            throw CommunityError.signInRequired
        }
    }

    private func me() async throws -> UUID {
        guard let id = await auth.user?.id else { throw CommunityError.signInRequired }
        return id
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = Timestamp.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(text)")
            }
            return date
        }
        return decoder
    }

    private func get<Row: Decodable & Sendable>(_ table: String, _ query: [String: String], as type: Row.Type = Row.self) async throws -> [Row] {
        let items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        let data = try await wrap { try await self.client.send("GET", path: "rest/v1/\(table)", query: items, accessToken: try await self.token()) }
        return try Self.makeDecoder().decode([Row].self, from: data)
    }

    private func insert(_ table: String, _ row: [String: JSONValue]) async throws {
        let body = try JSONEncoder().encode(row)
        _ = try await wrap { try await self.client.send("POST", path: "rest/v1/\(table)", body: body, prefer: "return=minimal", accessToken: try await self.token()) }
    }

    @discardableResult
    private func rpc(_ name: String, _ params: [String: JSONValue] = [:]) async throws -> Data {
        let body = try JSONEncoder().encode(params)
        return try await wrap { try await self.client.send("POST", path: "rest/v1/rpc/\(name)", body: body, accessToken: try await self.token()) }
    }

    private func delete(_ table: String, _ filters: [String: String]) async throws {
        let items = filters.map { URLQueryItem(name: $0.key, value: $0.value) }
        _ = try await wrap { try await self.client.send("DELETE", path: "rest/v1/\(table)", query: items, prefer: "return=minimal", accessToken: try await self.token()) }
    }

    private func wrap<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw CommunityError.from(error)
        }
    }

    private static func uuid(_ data: Data) throws -> UUID {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        guard let id = UUID(uuidString: text) else { throw CommunityError.message(String(localized: "The server sent an unexpected response.")) }
        return id
    }

    // MARK: Profile and safety

    func profile() async throws -> CommunityProfile? {
        let rows: [CommunityProfile] = try await get("profiles", ["select": "user_id,display_name,community_terms_accepted_at", "user_id": "eq.\(try await me().uuidString.lowercased())"])
        return rows.first
    }

    func setDisplayName(_ name: String) async throws {
        try await rpc("set_display_name", ["p_name": .string(name)])
    }

    func acceptCommunityTerms() async throws {
        try await rpc("accept_community_terms")
    }

    func blockedUsers() async throws -> Set<UUID> {
        struct Row: Decodable, Sendable { let blocked: UUID }
        let rows: [Row] = try await get("user_blocks", ["select": "blocked"])
        return Set(rows.map(\.blocked))
    }

    func block(_ user: UUID) async throws {
        try await insert("user_blocks", ["blocked": .string(user.uuidString.lowercased())])
    }

    func blockAuthor(ofPost post: UUID) async throws {
        try await rpc("block_post_author", ["p_post": .string(post.uuidString.lowercased())])
    }

    func unblock(_ user: UUID) async throws {
        try await delete("user_blocks", ["blocked": "eq.\(user.uuidString.lowercased())", "blocker": "eq.\(try await me().uuidString.lowercased())"])
    }

    func report(_ kind: ContentKind, id: UUID, reason: String) async throws {
        do {
            try await insert("content_reports", [
                "content_type": .string(kind.rawValue),
                "content_id": .string(id.uuidString.lowercased()),
                "reason": .string(String(reason.prefix(500))),
            ])
        } catch CommunityError.duplicate {
            // Already reported by you: nothing more to do.
        }
    }

    func remove(_ kind: ContentKind, id: UUID) async throws {
        try await rpc("remove_content", ["p_type": .string(kind.rawValue), "p_id": .string(id.uuidString.lowercased())])
    }

    // MARK: Groups

    func myGroups() async throws -> [GroupSummary] {
        struct Row: Decodable, Sendable {
            struct Group: Decodable, Sendable {
                let id: UUID
                let name: String
                let description: String
                let invite_code: String
                let plan_id: String?
                let plan_title: String?
                let plan_books: [Int]?
                let plan_days: Int?
                let plan_start: String?
                let deleted_at: String?
            }
            let role: GroupRole
            let notifications: Bool
            let group: Group?
        }
        let rows: [Row] = try await get("group_members", [
            "select": "role,notifications,group:groups(id,name,description,invite_code,plan_id,plan_title,plan_books,plan_days,plan_start,deleted_at)",
            "user_id": "eq.\(try await me().uuidString.lowercased())",
        ])
        return rows.compactMap { row in
            guard let group = row.group, group.deleted_at == nil else { return nil }
            return GroupSummary(
                id: group.id, name: group.name, description: group.description, inviteCode: group.invite_code,
                planID: group.plan_id, planTitle: group.plan_title, planBooks: group.plan_books, planDays: group.plan_days,
                planStart: group.plan_start.flatMap { Timestamp.day(from: $0) }, role: row.role, notifications: row.notifications
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func planParameters(_ draft: GroupDraft) -> [String: JSONValue] {
        let plan = draft.plan
        var books: JSONValue = .null
        var days: JSONValue = .null
        if case let .custom(planBooks, planDays)? = plan?.kind {
            books = .array(planBooks.map { .number(Double($0)) })
            days = .number(Double(planDays))
        }
        return [
            "p_name": .string(draft.name.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_description": .string(draft.description.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_plan_id": plan.map { .string($0.id) } ?? .null,
            "p_plan_title": plan.map { .string($0.title) } ?? .null,
            "p_plan_books": books,
            "p_plan_days": days,
            // A calendar day in the leader's time zone, read back the same way.
            "p_plan_start": plan == nil ? .null : .string(Timestamp.dayString(from: draft.planStart)),
        ]
    }

    func createGroup(_ draft: GroupDraft) async throws -> UUID {
        try Self.uuid(try await rpc("create_group", Self.planParameters(draft)))
    }

    func joinGroup(code: String) async throws -> UUID {
        try Self.uuid(try await rpc("join_group", ["p_code": .string(code)]))
    }

    func updateGroup(_ group: UUID, draft: GroupDraft) async throws {
        var parameters = Self.planParameters(draft)
        parameters["p_group"] = .string(group.uuidString.lowercased())
        try await rpc("update_group", parameters)
    }

    func newInviteCode(_ group: UUID) async throws -> String {
        let data = try await rpc("new_invite_code", ["p_group": .string(group.uuidString.lowercased())])
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
    }

    func leaveGroup(_ group: UUID) async throws {
        try await rpc("leave_group", ["p_group": .string(group.uuidString.lowercased())])
    }

    func deleteGroup(_ group: UUID) async throws {
        try await rpc("delete_group", ["p_group": .string(group.uuidString.lowercased())])
    }

    func members(of group: UUID) async throws -> [GroupMember] {
        try await get("group_members", [
            "select": "group_id,user_id,role,display_name,joined_at",
            "group_id": "eq.\(group.uuidString.lowercased())",
            "order": "joined_at.asc",
        ])
    }

    func setRole(_ role: GroupRole, for user: UUID, in group: UUID) async throws {
        try await rpc("set_member_role", ["p_group": .string(group.uuidString.lowercased()), "p_user": .string(user.uuidString.lowercased()), "p_role": .string(role.rawValue)])
    }

    func removeMember(_ user: UUID, from group: UUID) async throws {
        try await rpc("remove_member", ["p_group": .string(group.uuidString.lowercased()), "p_user": .string(user.uuidString.lowercased())])
    }

    func setNotifications(_ on: Bool, for group: UUID) async throws {
        try await rpc("set_group_notifications", ["p_group": .string(group.uuidString.lowercased()), "p_on": .bool(on)])
    }

    func progress(in group: UUID, day: Int) async throws -> [GroupProgress] {
        try await get("group_progress", ["select": "user_id,day", "group_id": "eq.\(group.uuidString.lowercased())", "day": "eq.\(day)"])
    }

    func progressSummary(in group: UUID) async throws -> [MemberProgress] {
        let data = try await rpc("group_progress_summary", ["p_group": .string(group.uuidString.lowercased())])
        return try Self.makeDecoder().decode([MemberProgress].self, from: data)
    }

    func setDayDone(_ done: Bool, day: Int, in group: UUID) async throws {
        if done {
            do {
                try await insert("group_progress", ["group_id": .string(group.uuidString.lowercased()), "day": .number(Double(day))])
            } catch CommunityError.duplicate {
                // Already marked.
            }
        } else {
            try await delete("group_progress", [
                "group_id": "eq.\(group.uuidString.lowercased())",
                "day": "eq.\(day)",
                "user_id": "eq.\(try await me().uuidString.lowercased())",
            ])
        }
    }

    func prayers(in group: UUID) async throws -> [GroupPrayer] {
        try await get("group_prayers", [
            "select": "id,group_id,user_id,display_name,body,prayed_count,created_at,answered_at",
            "group_id": "eq.\(group.uuidString.lowercased())",
            "order": "created_at.desc",
            "limit": "200",
        ])
    }

    func myPrayerMarks(_ prayers: [UUID]) async throws -> Set<UUID> {
        guard !prayers.isEmpty else { return [] }
        struct Row: Decodable, Sendable { let prayer_id: UUID }
        let list = prayers.map { $0.uuidString.lowercased() }.joined(separator: ",")
        let rows: [Row] = try await get("group_prayer_marks", ["select": "prayer_id", "prayer_id": "in.(\(list))"])
        return Set(rows.map(\.prayer_id))
    }

    func addPrayer(_ body: String, to group: UUID) async throws {
        try await insert("group_prayers", ["group_id": .string(group.uuidString.lowercased()), "body": .string(body)])
    }

    func setPrayed(_ prayed: Bool, prayer: UUID) async throws {
        if prayed {
            do {
                try await insert("group_prayer_marks", ["prayer_id": .string(prayer.uuidString.lowercased())])
            } catch CommunityError.duplicate {}
        } else {
            try await delete("group_prayer_marks", ["prayer_id": "eq.\(prayer.uuidString.lowercased())", "user_id": "eq.\(try await me().uuidString.lowercased())"])
        }
    }

    func setAnswered(_ answered: Bool, prayer: UUID) async throws {
        try await rpc("set_prayer_answered", ["p_prayer": .string(prayer.uuidString.lowercased()), "p_answered": .bool(answered)])
    }

    func posts(in group: UUID) async throws -> [GroupPost] {
        // The newest 500, shown oldest first.
        let rows: [GroupPost] = try await get("group_posts", [
            "select": "id,group_id,user_id,display_name,day,body,created_at",
            "group_id": "eq.\(group.uuidString.lowercased())",
            "order": "created_at.desc",
            "limit": "500",
        ])
        return rows.reversed()
    }

    func addPost(_ body: String, day: Int?, to group: UUID) async throws {
        try await insert("group_posts", [
            "group_id": .string(group.uuidString.lowercased()),
            "body": .string(body),
            "day": day.map { .number(Double($0)) } ?? .null,
        ])
    }

    func announcements(in group: UUID) async throws -> [GroupAnnouncement] {
        try await get("group_announcements", [
            "select": "id,group_id,user_id,display_name,title,body,created_at",
            "group_id": "eq.\(group.uuidString.lowercased())",
            "order": "created_at.desc",
            "limit": "100",
        ])
    }

    func addAnnouncement(title: String, body: String, to group: UUID) async throws {
        let id = UUID()
        try await insert("group_announcements", [
            "id": .string(id.uuidString.lowercased()),
            "group_id": .string(group.uuidString.lowercased()),
            "title": .string(title),
            "body": .string(body),
        ])
        // Best effort: the announcement is posted even if notifying fails.
        let payload = try JSONEncoder().encode(["announcementID": id.uuidString.lowercased()])
        _ = try? await client.callFunction("group-notify", body: payload, accessToken: try await token())
    }

    // MARK: Community

    func feed(_ kind: CommunityPostKind, before: Date?) async throws -> [CommunityPost] {
        // Through community_feed(), which keeps anonymous authors anonymous.
        let data = try await rpc("community_feed", [
            "p_kind": .string(kind.rawValue),
            "p_before": before.map { .string(Timestamp.string(from: $0)) } ?? .null,
            "p_limit": .number(40),
        ])
        return try Self.makeDecoder().decode([CommunityPost].self, from: data)
    }

    func myReactions(_ posts: [UUID]) async throws -> Set<UUID> {
        guard !posts.isEmpty else { return [] }
        struct Row: Decodable, Sendable { let post_id: UUID }
        let list = posts.map { $0.uuidString.lowercased() }.joined(separator: ",")
        let rows: [Row] = try await get("community_reactions", ["select": "post_id", "post_id": "in.(\(list))"])
        return Set(rows.map(\.post_id))
    }

    func addCommunityPost(_ draft: CommunityDraft) async throws {
        try await insert("community_posts", [
            "kind": .string(draft.kind.rawValue),
            "body": .string(draft.body.trimmingCharacters(in: .whitespacesAndNewlines)),
            "start_verse": draft.start.map { .number(Double($0.rawValue)) } ?? .null,
            "end_verse": (draft.end ?? draft.start).map { .number(Double($0.rawValue)) } ?? .null,
            "is_anonymous": .bool(draft.isAnonymous),
        ])
    }

    func setReacted(_ reacted: Bool, post: UUID) async throws {
        if reacted {
            do {
                try await insert("community_reactions", ["post_id": .string(post.uuidString.lowercased())])
            } catch CommunityError.duplicate {}
        } else {
            try await delete("community_reactions", ["post_id": "eq.\(post.uuidString.lowercased())", "user_id": "eq.\(try await me().uuidString.lowercased())"])
        }
    }

    func comments(on post: UUID) async throws -> [CommunityComment] {
        // The newest 300, shown oldest first.
        let rows: [CommunityComment] = try await get("community_comments", [
            "select": "id,post_id,user_id,display_name,body,created_at",
            "post_id": "eq.\(post.uuidString.lowercased())",
            "order": "created_at.desc",
            "limit": "300",
        ])
        return rows.reversed()
    }

    func addComment(_ body: String, on post: UUID) async throws {
        try await insert("community_comments", ["post_id": .string(post.uuidString.lowercased()), "body": .string(body)])
    }

    // MARK: Notifications

    func registerPushToken(_ token: String, sandbox: Bool) async throws {
        let body = try JSONEncoder().encode([
            "token": JSONValue.string(token),
            "environment": .string(sandbox ? "sandbox" : "production"),
            "updated_at": .string(Timestamp.string(from: .now)),
        ])
        _ = try await wrap {
            try await self.client.send(
                "POST",
                path: "rest/v1/push_tokens",
                query: [URLQueryItem(name: "on_conflict", value: "user_id,token")],
                body: body,
                prefer: "resolution=merge-duplicates,return=minimal",
                accessToken: try await self.token()
            )
        }
    }

    func unregisterPushToken(_ token: String) async throws {
        try await delete("push_tokens", ["token": "eq.\(token)", "user_id": "eq.\(try await me().uuidString.lowercased())"])
    }
}

/// A JSON value for request bodies with mixed types and explicit nulls.
enum JSONValue: Encodable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value):
            if value.rounded() == value, abs(value) < 1e15 { try container.encode(Int64(value)) } else { try container.encode(value) }
        case let .bool(value): try container.encode(value)
        case let .array(values): try container.encode(values)
        case .null: try container.encodeNil()
        }
    }
}
