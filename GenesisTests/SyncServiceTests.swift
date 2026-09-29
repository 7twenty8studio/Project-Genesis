import Foundation
import SwiftData
import Testing
@testable import Genesis

/// A fake server for URLSession: records every request and answers from a handler.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Recorded: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data
    }

    nonisolated(unsafe) static var handler: (@Sendable (Recorded) -> (Int, String))?
    nonisolated(unsafe) static var recorded: [Recorded] = []
    private static let lock = NSLock()

    static func reset(_ newHandler: @escaping @Sendable (Recorded) -> (Int, String)) {
        lock.withLock {
            handler = newHandler
            recorded = []
        }
    }

    static var requests: [Recorded] { lock.withLock { recorded } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.read(request.httpBodyStream)
        let recorded = Recorded(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body
        )
        let (status, text) = Self.lock.withLock { () -> (Int, String) in
            Self.recorded.append(recorded)
            return Self.handler?(recorded) ?? (404, "{}")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Talks to a fake Supabase server; runs serially because the fake is shared.
@Suite("Supabase client and sync", .serialized)
@MainActor
struct SyncServiceTests {
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let baseURL = URL(string: "https://example.supabase.co")!

    private func client() -> SupabaseClient {
        SupabaseClient(baseURL: baseURL, anonKey: "anon-key", session: StubURLProtocol.session())
    }

    // MARK: Client

    @Test func signInSendsCredentialsAndReadsSession() async throws {
        StubURLProtocol.reset { _ in
            (200, #"{"access_token":"tok","refresh_token":"ref","expires_in":3600,"user":{"id":"11111111-1111-1111-1111-111111111111","email":"a@b.co"}}"#)
        }
        let session = try await client().signIn(email: "a@b.co", password: "secret1")

        #expect(session.accessToken == "tok")
        #expect(session.user.id == userID)
        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.url.path == "/auth/v1/token")
        #expect(request.url.query?.contains("grant_type=password") == true)
        #expect(request.headers["apikey"] == "anon-key")
        let body = String(decoding: request.body, as: UTF8.self)
        #expect(body.contains("a@b.co"))
    }

    @Test func signUpNeedingConfirmationIsReported() async {
        StubURLProtocol.reset { _ in (200, #"{"id":"11111111-1111-1111-1111-111111111111","email":"a@b.co"}"#) }
        await #expect(throws: SupabaseError.emailConfirmationRequired) {
            _ = try await client().signUp(email: "a@b.co", password: "secret1")
        }
    }

    @Test func serverErrorsCarryTheirMessage() async {
        StubURLProtocol.reset { _ in (400, #"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#) }
        await #expect(throws: SupabaseError.http(status: 400, message: "Invalid login credentials")) {
            _ = try await client().signIn(email: "a@b.co", password: "wrong")
        }
    }

    @Test func cursorPlusSignIsEncoded() async throws {
        StubURLProtocol.reset { _ in (200, "[]") }
        let rows: [RemoteNote] = try await client().changes(in: "notes", since: "2026-09-29T17:46:00.123456+00:00", limit: 10, accessToken: "tok")
        #expect(rows.isEmpty)
        let url = try #require(StubURLProtocol.requests.first?.url.absoluteString)
        #expect(url.contains("%2B00:00"))
        #expect(StubURLProtocol.requests.first?.headers["Authorization"] == "Bearer tok")
    }

    // MARK: Full sync

    @Test func syncPullsRemoteChangesAndPushesLocalOnes() async throws {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let defaults = try #require(UserDefaults(suiteName: "sync-test-\(UUID())"))
        let keychain = KeychainStore(service: "genesis.tests.\(UUID())")
        defer { keychain.delete(account: "session") }
        keychain.save(
            AuthSession(accessToken: "tok", refreshToken: "ref", expiresAt: .now.addingTimeInterval(3600), user: AuthUser(id: userID, email: "a@b.co")),
            account: "session"
        )

        // Local data: a note written offline, and a deleted bookmark.
        let store = StudyStore(context: context)
        let localNote = store.createNote(kind: .study, anchor: .chapter(ChapterID(book: 43, chapter: 3)), body: "Born again")
        let deletedID = UUID()
        store.recordDeletion(of: deletedID, in: SyncTable.bookmarks)
        store.save()

        // Server data: a highlight made on another device.
        let remoteHighlightID = UUID(uuidString: "22222222-0000-0000-0000-000000000001")!
        let uid = userID
        StubURLProtocol.reset { request in
            switch (request.method, request.url.path) {
            case ("GET", "/rest/v1/highlights"):
                return (200, """
                [{"id":"\(remoteHighlightID.uuidString)","user_id":"\(uid.uuidString)","verse":43003016,"color":"blue",
                  "collection_id":null,"created_at":"2026-09-29T10:00:00.000000+00:00","updated_at":"2026-09-29T10:00:00.000000+00:00",
                  "deleted_at":null,"server_updated_at":"2026-09-29T10:00:01.123456+00:00"}]
                """)
            case ("GET", _):
                return (200, "[]")
            case ("POST", _):
                return (201, "")
            case ("PATCH", _):
                return (204, "")
            default:
                return (404, "{}")
            }
        }

        let auth = AuthService(client: client(), keychain: keychain)
        #expect(auth.user?.id == userID)
        let sync = SyncService(auth: auth, container: container, defaults: defaults)
        await sync.syncNow()

        #expect(sync.status == .idle)

        // Pulled: the remote highlight now exists locally.
        let highlights = try context.fetch(FetchDescriptor<Highlight>())
        #expect(highlights.count == 1)
        #expect(highlights.first?.id == remoteHighlightID)
        #expect(highlights.first?.color == .blue)

        // Pushed: the local note went up with this user's id.
        let requests = StubURLProtocol.requests
        let notePushMatch = requests.first { $0.method == "POST" && $0.url.path == "/rest/v1/notes" }
        let notePush = try #require(notePushMatch)
        let pushed = String(decoding: notePush.body, as: UTF8.self)
        #expect(pushed.contains(localNote.id.uuidString))
        #expect(pushed.contains(userID.uuidString))
        #expect(notePush.headers["Prefer"]?.contains("merge-duplicates") == true)

        // The deletion was sent and the tombstone cleared.
        let patchMatch = requests.first { $0.method == "PATCH" }
        let patch = try #require(patchMatch)
        #expect(patch.url.path == "/rest/v1/bookmarks")
        #expect(patch.url.query?.contains(deletedID.uuidString.lowercased()) == true)
        let tombstones = try context.fetchCount(FetchDescriptor<Tombstone>())
        #expect(tombstones == 0)

        // The pull cursor was saved at full precision.
        #expect(defaults.string(forKey: "sync.\(userID.uuidString).cursor.highlights") == "2026-09-29T10:00:01.123456+00:00")
    }

    @Test func signingIntoADifferentAccountClearsTheOldAccountsData() throws {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let defaults = try #require(UserDefaults(suiteName: "sync-test-\(UUID())"))
        StudyStore(context: container.mainContext).createNote(kind: .text, anchor: .none, body: "Someone else's note")
        defaults.set(UUID().uuidString, forKey: "sync.localDataOwner")

        let auth = AuthService(client: nil, restoresSession: false)
        let sync = SyncService(auth: auth, container: container, defaults: defaults)
        sync.accountDidSignIn(AuthUser(id: userID, email: nil))

        let notes = try container.mainContext.fetchCount(FetchDescriptor<Note>())
        #expect(notes == 0)
        #expect(defaults.string(forKey: "sync.localDataOwner") == userID.uuidString)
    }

    @Test func guestDataJoinsTheFirstAccount() throws {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let defaults = try #require(UserDefaults(suiteName: "sync-test-\(UUID())"))
        StudyStore(context: container.mainContext).createNote(kind: .text, anchor: .none, body: "My guest note")

        let sync = SyncService(auth: AuthService(client: nil, restoresSession: false), container: container, defaults: defaults)
        sync.accountDidSignIn(AuthUser(id: userID, email: nil))

        let notes = try container.mainContext.fetchCount(FetchDescriptor<Note>())
        #expect(notes == 1)
    }
}
