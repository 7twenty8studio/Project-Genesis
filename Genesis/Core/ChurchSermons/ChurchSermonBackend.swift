import Foundation
import SwiftUI

/// Church sermons on the server (VRS-18). Everything goes through the
/// database functions of migration 20261120000000, which check the
/// `church_sermons` switch, the church's own switch, membership and bans on
/// every call; the app never reads the tables. Readers get only the
/// published revision, never the draft. UI tests use
/// `InMemoryChurchSermonBackend`.
protocol ChurchSermonBackend: Sendable {
    /// The sermon behind a link, for whoever is asking (signed in or not).
    func sermon(slug: String) async throws -> ChurchSermonLookup
    /// A church's published sermons, newest first, for its members.
    /// Throws for a group whose sermons are off or that the person isn't in.
    func archive(group: UUID) async throws -> [ChurchSermonSummary]
    /// Churches that chose to be listed, by name (two characters or more).
    func searchChurches(_ query: String) async throws -> [SermonChurch]
    /// Reports a published sermon to its church's moderators (signed in only, once each).
    func report(slug: String, reason: String) async throws
    /// The cover picture, checked against the reader's access on every request.
    func cover(path: String) async throws -> Data?
    /// Counts an open, a passage opened or notes saved for the church's
    /// totals (no account, address or text is kept). Never throws.
    func count(_ event: ChurchSermonEvent, slug: String) async
}

enum ChurchSermonEvent: String, Sendable {
    case open, passage, save
}

extension EnvironmentValues {
    /// Where church sermons come from (Supabase, or in memory in UI tests).
    @Entry var churchSermons: any ChurchSermonBackend = UnavailableChurchSermonBackend()
}

enum ChurchSermonError {
    static let messages: [String: String] = [
        "not_signed_in": String(localized: "Sign in to report a sermon."),
        "not_found": String(localized: "This sermon is no longer available."),
        "not_allowed": String(localized: "This church's sermons aren't available to you."),
        "invalid_details": String(localized: "Keep the reason under 500 characters."),
    ]

    static func from(_ error: Error) -> CommunityError {
        if case let .http(_, message)? = error as? SupabaseError, let text = messages[message] {
            return .message(text)
        }
        return CommunityError.from(error)
    }
}

/// Supabase: published_sermon, group_sermons, search_sermon_churches and
/// report_church_sermon; covers through the sermon-cover function and
/// counts through sermon-events. Signed out, the anon key reads what
/// anyone with the link may read.
final class SupabaseChurchSermonBackend: ChurchSermonBackend {
    private let client: SupabaseClient
    private let auth: AuthService

    init(client: SupabaseClient, auth: AuthService) {
        self.client = client
        self.auth = auth
    }

    /// The person's token when signed in, else nil (the anon key).
    private func token() async -> String? {
        guard await auth.isSignedIn else { return nil }
        return try? await auth.accessToken()
    }

    private func rpc(_ name: String, _ params: [String: JSONValue], signedIn: Bool = false) async throws -> Data {
        let body = try JSONEncoder().encode(params)
        let token = await token()
        if signedIn, token == nil { throw CommunityError.signInRequired }
        do {
            return try await client.send("POST", path: "rest/v1/rpc/\(name)", body: body, accessToken: token)
        } catch {
            throw ChurchSermonError.from(error)
        }
    }

    func sermon(slug: String) async throws -> ChurchSermonLookup {
        guard ChurchSermonLink.isSlug(slug) else { return .notFound }
        return try ChurchSermonWire.lookup(from: try await rpc("published_sermon", ["p_slug": .string(slug)]))
    }

    func archive(group: UUID) async throws -> [ChurchSermonSummary] {
        try ChurchSermonWire.archive(from: try await rpc("group_sermons", ["p_group": .string(group.uuidString.lowercased())], signedIn: true))
    }

    func searchChurches(_ query: String) async throws -> [SermonChurch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        return try ChurchSermonWire.churches(from: try await rpc("search_sermon_churches", ["p_query": .string(String(trimmed.prefix(60)))]))
    }

    func report(slug: String, reason: String) async throws {
        _ = try await rpc("report_church_sermon", ["p_slug": .string(slug), "p_reason": .string(String(reason.prefix(500)))], signedIn: true)
    }

    func cover(path: String) async throws -> Data? {
        do {
            // private, no-store: URLSession keeps no copy.
            return try await client.send("GET", path: "functions/v1/sermon-cover", query: [URLQueryItem(name: "name", value: path)], accessToken: await token())
        } catch SupabaseError.http(let status, _) where status == 404 {
            return nil
        }
    }

    func count(_ event: ChurchSermonEvent, slug: String) async {
        guard let body = try? JSONEncoder().encode(["slug": slug, "kind": event.rawValue]) else { return }
        // Best effort, like the web page; no account is sent.
        _ = try? await client.callFunction("sermon-events", body: body, accessToken: nil, timeout: 15)
    }
}

/// No server (a build without Supabase): nothing to read.
struct UnavailableChurchSermonBackend: ChurchSermonBackend {
    func sermon(slug: String) async throws -> ChurchSermonLookup { throw CommunityError.notConfigured }
    func archive(group: UUID) async throws -> [ChurchSermonSummary] { throw CommunityError.notConfigured }
    func searchChurches(_ query: String) async throws -> [SermonChurch] { [] }
    func report(slug: String, reason: String) async throws { throw CommunityError.notConfigured }
    func cover(path: String) async throws -> Data? { nil }
    func count(_ event: ChurchSermonEvent, slug: String) async {}
}
