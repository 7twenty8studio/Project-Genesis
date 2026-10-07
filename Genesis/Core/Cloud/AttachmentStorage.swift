import Foundation

/// Where attachment files are kept in the cloud: the person's own iCloud
/// (`ICloudAttachmentStorage`), the private Supabase bucket earlier versions
/// used (read only to move files out, `MovingAttachmentStorage`), or memory
/// in tests (no network). Paths are `AttachmentPaths.storagePath`.
protocol AttachmentStorage: Sendable {
    func upload(_ data: Data, path: String, contentType: String) async throws
    func download(path: String) async throws -> Data
    func remove(paths: [String]) async throws
    /// Every file of the account (deleting the account).
    func removeAll(userID: UUID) async throws
}

enum AttachmentStorageError: LocalizedError, Equatable {
    case signedOut
    case notFound
    /// iCloud is off for Genesis, or no one is signed in to iCloud.
    case iCloudUnavailable
    /// The person's iCloud storage is full.
    case iCloudFull

    var errorDescription: String? {
        switch self {
        case .signedOut: String(localized: "Sign in to sync attachments.")
        case .notFound: String(localized: "This attachment hasn't reached iCloud yet. Open it on the device where you added it, signed in to the same Apple Account.")
        case .iCloudUnavailable: String(localized: "Turn on iCloud for Genesis in Settings to sync attachments.")
        case .iCloudFull: String(localized: "Your iCloud storage is full, so attachments aren't syncing.")
        }
    }
}

/// iCloud, plus the Supabase bucket earlier versions uploaded to. Files go
/// only to iCloud; one found only in the bucket is copied to iCloud and
/// removed from the bucket, so the bucket empties over time.
struct MovingAttachmentStorage: AttachmentStorage {
    let iCloud: any AttachmentStorage
    let legacy: any AttachmentStorage

    func upload(_ data: Data, path: String, contentType: String) async throws {
        try await iCloud.upload(data, path: path, contentType: contentType)
        // An earlier version may have left the same file in the bucket.
        try? await legacy.remove(paths: [path])
    }

    func download(path: String) async throws -> Data {
        do {
            return try await iCloud.download(path: path)
        } catch {
            guard let data = try? await legacy.download(path: path) else { throw error }
            if (try? await iCloud.upload(data, path: path, contentType: "")) != nil {
                try? await legacy.remove(paths: [path])
            }
            return data
        }
    }

    func remove(paths: [String]) async throws {
        try? await legacy.remove(paths: paths)
        try await iCloud.remove(paths: paths)
    }

    func removeAll(userID: UUID) async throws {
        // The bucket is emptied by the delete-account function.
        try await iCloud.removeAll(userID: userID)
    }
}

/// No iCloud for Genesis (an unsigned build, or iCloud turned off): files
/// stay on the device and uploads wait.
struct UnavailableAttachmentStorage: AttachmentStorage {
    func upload(_ data: Data, path: String, contentType: String) async throws {
        throw AttachmentStorageError.iCloudUnavailable
    }

    func download(path: String) async throws -> Data {
        throw AttachmentStorageError.iCloudUnavailable
    }

    func remove(paths: [String]) async throws {
        throw AttachmentStorageError.iCloudUnavailable
    }

    func removeAll(userID: UUID) async throws {}
}

/// The `attachments` bucket (20261014000000_attachments.sql), with the
/// person's own token, so the bucket's policies apply. Only read and emptied
/// now: new files go to iCloud.
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
        try await client.uploadObject(data, bucket: AttachmentPaths.bucket, path: path, contentType: contentType, accessToken: try await token())
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

    func removeAll(userID: UUID) async throws {}
}

/// Files kept in memory: UI tests and unit tests (no network, no cost).
actor InMemoryAttachmentStorage: AttachmentStorage {
    private(set) var objects: [String: Data] = [:]
    /// Fails this many uploads before succeeding, for retry tests.
    private var failuresLeft: Int

    init(failingUploads: Int = 0) {
        failuresLeft = failingUploads
    }

    func upload(_ data: Data, path: String, contentType: String) async throws {
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

    func removeAll(userID: UUID) async throws {
        let folder = userID.uuidString.lowercased() + "/"
        objects = objects.filter { !$0.key.hasPrefix(folder) }
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

    func removeAll(userID: UUID) async throws {}
}
