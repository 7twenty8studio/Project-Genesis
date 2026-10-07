import Foundation
import SwiftUI

/// Group challenges on the server. The live version talks to Supabase; UI
/// tests use `InMemoryGroupChallengeBackend`.
protocol GroupChallengeBackend: Sendable {
    /// The group's challenges (running, waiting to start and finished).
    func challenges(in group: UUID) async throws -> [GroupChallenge]
    /// Owners and moderators only; returns the new challenge's id.
    func createChallenge(_ draft: GroupChallengeDraft, in group: UUID) async throws -> UUID
    /// Owners and moderators only: it stops early and moves to finished,
    /// keeping everyone's progress.
    func endChallenge(_ challenge: UUID) async throws
    /// Ticks (or unticks) a chapter, a day, or "I've learned it".
    func setCheckin(_ done: Bool, item: Int, challenge: UUID) async throws
    /// Every member's progress.
    func progress(of challenge: UUID) async throws -> [ChallengeProgress]
}

extension EnvironmentValues {
    /// Where group challenges are kept (Supabase, or in memory in UI tests).
    @Entry var groupChallenges: any GroupChallengeBackend = SignedOutGroupChallengeBackend()
}

/// Supabase: the group_challenges table and the challenge functions in
/// 20261011000000_group_moderation_challenges.sql.
final class SupabaseGroupChallengeBackend: GroupChallengeBackend {
    private let client: SupabaseClient
    private let auth: AuthService

    init(client: SupabaseClient, auth: AuthService) {
        self.client = client
        self.auth = auth
    }

    // MARK: Plumbing (as in SupabaseCommunityBackend)

    private func token() async throws -> String {
        guard await auth.isSignedIn else { throw CommunityError.signInRequired }
        do {
            return try await auth.accessToken()
        } catch {
            throw CommunityError.signInRequired
        }
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

    private func wrap<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw GroupChallengeError.from(error)
        }
    }

    @discardableResult
    private func rpc(_ name: String, _ params: [String: JSONValue]) async throws -> Data {
        let body = try JSONEncoder().encode(params)
        return try await wrap { try await self.client.send("POST", path: "rest/v1/rpc/\(name)", body: body, accessToken: try await self.token()) }
    }

    private static func id(_ value: UUID) -> JSONValue { .string(value.uuidString.lowercased()) }

    // MARK: Challenges

    /// A row of public.group_challenges.
    private struct Row: Decodable, Sendable {
        let id: UUID
        let group_id: UUID
        let created_by: UUID?
        let kind: String
        let title: String
        let details: String?
        let starts_on: String
        let days: Int
        let chapters: [Int]?
        let verse_start: Int?
        let verse_end: Int?
        let translation_id: String?
        let created_at: Date
        let ended_at: Date?

        var challenge: GroupChallenge? {
            guard let kind = GroupChallengeKind(rawValue: kind), GroupChallengeRules.dayRange.contains(days) else { return nil }
            return GroupChallenge(
                id: id, groupID: group_id, createdBy: created_by, kind: kind, title: title, details: details ?? "",
                startDay: String(starts_on.prefix(10)), days: days,
                // Only real chapters, whatever the server holds.
                chapters: (chapters ?? []).filter { (1...66).contains($0 / 1_000) && $0 % 1_000 > 0 },
                verseStart: verse_start, verseEnd: verse_end, translationID: translation_id, createdAt: created_at,
                endedAt: ended_at
            )
        }
    }

    func challenges(in group: UUID) async throws -> [GroupChallenge] {
        // Members can read their groups' challenges, ended ones included.
        let query = [
            URLQueryItem(name: "select", value: "id,group_id,created_by,kind,title,details,starts_on,days,chapters,verse_start,verse_end,translation_id,created_at,ended_at"),
            URLQueryItem(name: "group_id", value: "eq.\(group.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "starts_on.desc,created_at.desc"),
            URLQueryItem(name: "limit", value: "60"),
        ]
        let data = try await wrap { try await self.client.send("GET", path: "rest/v1/group_challenges", query: query, accessToken: try await self.token()) }
        let rows = try Self.makeDecoder().decode([Row].self, from: data)
        return rows.compactMap(\.challenge)
    }

    func createChallenge(_ draft: GroupChallengeDraft, in group: UUID) async throws -> UUID {
        // Worked out one at a time, to keep the type checker quick.
        var chapters = JSONValue.null
        var verseStart = JSONValue.null
        var verseEnd = JSONValue.null
        var translation = JSONValue.null
        if draft.kind == .reading {
            chapters = .array(draft.chapters.map { JSONValue.number(Double($0)) })
        }
        if draft.kind == .memorise {
            if let start = draft.verseStart { verseStart = .number(Double(start.rawValue)) }
            if let end = draft.verseEnd { verseEnd = .number(Double(end.rawValue)) }
            if let id = draft.translationID { translation = .string(id) }
        }
        let parameters: [String: JSONValue] = [
            "p_group": Self.id(group),
            "p_kind": .string(draft.kind.rawValue),
            "p_title": .string(draft.trimmedTitle),
            "p_details": .string(draft.trimmedDetails),
            // A calendar day in the leader's time zone, read back the same way.
            "p_starts_on": .string(Timestamp.dayString(from: draft.startsOn)),
            "p_days": .number(Double(draft.days)),
            "p_chapters": chapters,
            "p_verse_start": verseStart,
            "p_verse_end": verseEnd,
            "p_translation": translation,
        ]
        let data = try await rpc("create_group_challenge", parameters)
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        guard let id = UUID(uuidString: text) else { throw CommunityError.message(String(localized: "The server sent an unexpected response.")) }
        return id
    }

    func endChallenge(_ challenge: UUID) async throws {
        try await rpc("end_group_challenge", ["p_challenge": Self.id(challenge)])
    }

    func setCheckin(_ done: Bool, item: Int, challenge: UUID) async throws {
        try await rpc("set_challenge_checkin", [
            "p_challenge": Self.id(challenge),
            "p_item": .number(Double(item)),
            "p_done": .bool(done),
        ])
    }

    func progress(of challenge: UUID) async throws -> [ChallengeProgress] {
        let data = try await rpc("group_challenge_progress", ["p_challenge": Self.id(challenge)])
        return try Self.makeDecoder().decode([ChallengeProgress].self, from: data)
    }
}

/// No account: no challenges, and every action asks the person to sign in.
struct SignedOutGroupChallengeBackend: GroupChallengeBackend {
    func challenges(in group: UUID) async throws -> [GroupChallenge] { [] }
    func createChallenge(_ draft: GroupChallengeDraft, in group: UUID) async throws -> UUID { throw CommunityError.signInRequired }
    func endChallenge(_ challenge: UUID) async throws { throw CommunityError.signInRequired }
    func setCheckin(_ done: Bool, item: Int, challenge: UUID) async throws { throw CommunityError.signInRequired }
    func progress(of challenge: UUID) async throws -> [ChallengeProgress] { [] }
}
