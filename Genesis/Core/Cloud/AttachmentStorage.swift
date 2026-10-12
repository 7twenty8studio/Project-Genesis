import Foundation

/// Where attachment files are kept in the cloud: the private Supabase bucket,
/// or memory in UI tests (no network). Paths are `AttachmentPaths.storagePath`.
protocol AttachmentStorage: Sendable {
    func upload(_ data: Data, path: String, contentType: String) async throws
    func download(path: String) async throws -> Data
    func remove(paths: [String]) async throws
}

enum AttachmentStorageError: LocalizedError, Equatable {
    case signedOut
    case notFound
    /// The bucket refused an upload: the server hasn't recorded Premium for
    /// this account (yet). See `AttachmentTransfers` (it asks premium-sync).
    case premiumRequired

    var errorDescription: String? {
        switch self {
        case .signedOut: String(localized: "Sign in to sync attachments.")
        case .notFound: String(localized: "This attachment hasn't reached the cloud yet. Open it on the device where you added it.")
        case .premiumRequired: String(localized: "Attachments sync to the cloud with Genesis Premium.")
        }
    }
}

/// The `attachments` bucket (20261014000000_attachments.sql), with the
/// person's own token, so the bucket's policies apply.
final class SupabaseAttachmentStorage: AttachmentStorage {
    private let client: SupabaseClient
    private let auth: AuthService

    init(client: SupabaseClient, auth: AuthService) {
        self.client = client
        self.auth = auth
    }

    private func token() async throws -> String {
        guard await auth.isSignedIn else { throw AttachmentStorageError.signedOut }
        return try await auth.accessToken()
    }

    func upload(_ data: Data, path: String, contentType: String) async throws {
        do {
            try await client.uploadObject(data, bucket: AttachmentPaths.bucket, path: path, contentType: contentType, accessToken: try await token())
        } catch SupabaseError.http(let status, let message) where AttachmentUploadRefusal.isPremiumRefusal(status: status, message: message) {
            throw AttachmentStorageError.premiumRequired
        }
    }

    func download(path: String) async throws -> Data {
        do {
            return try await client.downloadObject(bucket: AttachmentPaths.bucket, path: path, accessToken: try await token())
        } catch SupabaseError.http(let status, _) where status == 400 || status == 404 {
            // Storage answers 400 "not_found" for a missing object.
            throw AttachmentStorageError.notFound
        }
    }

    func remove(paths: [String]) async throws {
        // The API takes up to 1,000 paths at a time.
        let token = try await token()
        for start in stride(from: 0, to: paths.count, by: 500) {
            let batch = Array(paths[start..<min(start + 500, paths.count)])
            try await client.removeObjects(batch, bucket: AttachmentPaths.bucket, accessToken: token)
        }
    }
}

/// How Storage says an upload broke a bucket policy. Uploads into one's own
/// folder fail a policy only for want of Premium (20261016000000_premium_checks.sql).
/// Storage answers 403, or (older versions) 400 with "new row violates
/// row-level security policy".
enum AttachmentUploadRefusal {
    static func isPremiumRefusal(status: Int, message: String) -> Bool {
        if status == 403 { return true }
        let text = message.lowercased()
        return status == 400 && (text.contains("row-level security") || text.contains("row level security"))
    }
}

/// Files kept in memory: UI tests and unit tests (no network, no cost).
actor InMemoryAttachmentStorage: AttachmentStorage {
    private(set) var objects: [String: Data] = [:]
    /// Fails this many uploads before succeeding, for retry tests.
    private var failuresLeft: Int
    /// Refuses uploads as the bucket does until Premium is recorded.
    private var premiumRecorded: Bool

    init(failingUploads: Int = 0, premiumRecorded: Bool = true) {
        failuresLeft = failingUploads
        self.premiumRecorded = premiumRecorded
    }

    /// What premium-sync does on the server.
    func recordPremium() {
        premiumRecorded = true
    }

    func upload(_ data: Data, path: String, contentType: String) async throws {
        guard premiumRecorded else { throw AttachmentStorageError.premiumRequired }
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw URLError(.networkConnectionLost)
        }
        objects[path] = data
    }

    func download(path: String) async throws -> Data {
        guard let data = objects[path] else { throw AttachmentStorageError.notFound }
        return data
    }

    func remove(paths: [String]) async throws {
        for path in paths { objects[path] = nil }
    }
}

/// No account: nothing leaves the device.
struct SignedOutAttachmentStorage: AttachmentStorage {
    func upload(_ data: Data, path: String, contentType: String) async throws {
        throw AttachmentStorageError.signedOut
    }

    func download(path: String) async throws -> Data {
        throw AttachmentStorageError.signedOut
    }

    func remove(paths: [String]) async throws {
        throw AttachmentStorageError.signedOut
    }
}
