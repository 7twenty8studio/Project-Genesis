import Foundation

/// A signed-in Supabase session.
struct AuthSession: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    /// True when the access token expires within the next minute.
    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

struct AuthUser: Codable, Sendable, Equatable {
    let id: UUID
    let email: String?
}

enum SupabaseError: LocalizedError, Equatable {
    case notConfigured
    case http(status: Int, message: String)
    case emailConfirmationRequired
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Cloud sync isn't set up in this build."
        case let .http(_, message):
            message
        case .emailConfirmationRequired:
            "Check your email to confirm your account, then sign in."
        case .invalidResponse:
            "The server sent an unexpected response."
        }
    }
}

/// A small client for Supabase's Auth (GoTrue) and REST (PostgREST) APIs,
/// built on URLSession so there is no third-party SDK to keep in step.
final class SupabaseClient: Sendable {
    let baseURL: URL
    private let anonKey: String
    private let session: URLSession

    init(baseURL: URL, anonKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
    }

    /// Built from Config/Secrets.xcconfig; nil when sync isn't configured.
    static func fromConfiguration(_ configuration: AppConfiguration = .current) -> SupabaseClient? {
        guard let url = configuration.supabaseURL, let key = configuration.supabaseAnonKey else { return nil }
        return SupabaseClient(baseURL: url, anonKey: key)
    }

    // MARK: Auth

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Double?
        let user: UserResponse?
        // Sign-up without a session (email confirmation on) returns the user at the top level.
        let id: UUID?
        let email: String?
    }

    private struct UserResponse: Decodable {
        let id: UUID
        let email: String?
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        try await tokenRequest(path: "auth/v1/signup", query: [], body: ["email": email, "password": password])
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        try await tokenRequest(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")], body: ["email": email, "password": password])
    }

    /// Exchanges an Apple identity token (from Sign in with Apple) for a session.
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        try await tokenRequest(
            path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "id_token")],
            body: ["provider": "apple", "id_token": idToken, "nonce": nonce]
        )
    }

    func refresh(_ current: AuthSession) async throws -> AuthSession {
        try await tokenRequest(
            path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: ["refresh_token": current.refreshToken]
        )
    }

    func signOut(_ current: AuthSession) async {
        var request = makeRequest(path: "auth/v1/logout", query: [], method: "POST", accessToken: current.accessToken)
        request.httpBody = Data("{}".utf8)
        _ = try? await session.data(for: request)
    }

    func sendPasswordReset(email: String) async throws {
        var request = makeRequest(path: "auth/v1/recover", query: [], method: "POST", accessToken: nil)
        request.httpBody = try JSONEncoder().encode(["email": email])
        _ = try await perform(request)
    }

    private func tokenRequest(path: String, query: [URLQueryItem], body: [String: String]) async throws -> AuthSession {
        var request = makeRequest(path: path, query: query, method: "POST", accessToken: nil)
        request.httpBody = try JSONEncoder().encode(body)
        let data = try await perform(request)
        let response = try SupabaseCoding.decoder().decode(TokenResponse.self, from: data)
        guard let accessToken = response.accessToken, let refreshToken = response.refreshToken, let user = response.user else {
            if response.id != nil { throw SupabaseError.emailConfirmationRequired }
            throw SupabaseError.invalidResponse
        }
        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(response.expiresIn ?? 3600),
            user: AuthUser(id: user.id, email: user.email)
        )
    }

    // MARK: REST

    /// Rows from `table` whose `server_updated_at` is after `cursor`, oldest first.
    func changes<Row: Decodable & Sendable>(
        in table: String,
        since cursor: String?,
        limit: Int,
        accessToken: String,
        as type: Row.Type = Row.self
    ) async throws -> [Row] {
        var query = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "server_updated_at.asc"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let cursor {
            query.append(URLQueryItem(name: "server_updated_at", value: "gt.\(cursor)"))
        }
        let request = makeRequest(path: "rest/v1/\(table)", query: query, method: "GET", accessToken: accessToken)
        let data = try await perform(request)
        return try SupabaseCoding.decoder().decode([Row].self, from: data)
    }

    /// Inserts or updates rows by primary key.
    func upsert<Row: Encodable & Sendable>(_ rows: [Row], into table: String, accessToken: String) async throws {
        guard !rows.isEmpty else { return }
        var request = makeRequest(
            path: "rest/v1/\(table)",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            method: "POST",
            accessToken: accessToken
        )
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try SupabaseCoding.encoder().encode(rows)
        _ = try await perform(request)
    }

    /// Marks rows as deleted so other devices remove them too.
    func markDeleted(ids: [UUID], in table: String, at date: Date, accessToken: String) async throws {
        guard !ids.isEmpty else { return }
        let list = ids.map { $0.uuidString.lowercased() }.joined(separator: ",")
        var request = makeRequest(
            path: "rest/v1/\(table)",
            query: [URLQueryItem(name: "id", value: "in.(\(list))")],
            method: "PATCH",
            accessToken: accessToken
        )
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let stamp = Timestamp.string(from: date)
        request.httpBody = try JSONEncoder().encode(["deleted_at": stamp, "updated_at": stamp])
        _ = try await perform(request)
    }

    // MARK: Plumbing

    func makeRequest(path: String, query: [URLQueryItem], method: String, accessToken: String?) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
            // "+" is legal in a query but PostgREST reads it as a space, which
            // would break timestamp cursors like "...+00:00".
            let encoded = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            components?.percentEncodedQuery = encoded
        }
        var request = URLRequest(url: components?.url ?? baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private struct ErrorBody: Decodable {
        let message: String?
        let msg: String?
        let errorDescription: String?
        let error: String?
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? SupabaseCoding.decoder().decode(ErrorBody.self, from: data)
            let message = body?.msg ?? body?.message ?? body?.errorDescription ?? body?.error
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SupabaseError.http(status: http.statusCode, message: message)
        }
        return data
    }
}
