import CloudKit
import Foundation

/// Attachment files in the person's own iCloud: the private CloudKit
/// database of the container in Info.plist's `GenesisICloudContainer`
/// (set by Config/Signing.xcconfig; without it, `UnavailableAttachmentStorage`).
/// Storage counts against their iCloud plan, not Genesis's servers.
///
/// One record zone per Genesis account ("Attachments-<user id>"), so
/// deleting the account deletes its files and nothing else; one record
/// (type `AttachmentFile`) per file, named after it ("<id>.jpg"), holding
/// the file as an asset. Rows still sync through Supabase.
struct ICloudAttachmentStorage: AttachmentStorage {
    static let recordType = "AttachmentFile"
    private static let fileKey = "file"
    /// CloudKit takes up to 400 records in one request.
    private static let batchSize = 400

    let containerIdentifier: String
    private let zones = ZoneCache()

    init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    /// The container named in Info.plist, if this build has iCloud turned on.
    static var configuredContainer: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "GenesisICloudContainer") as? String
        guard let value, value.hasPrefix("iCloud.") else { return nil }
        return value
    }

    private var database: CKDatabase {
        CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    // MARK: AttachmentStorage

    func upload(_ data: Data, path: String, contentType: String) async throws {
        let (zoneName, fileName) = try Self.split(path)
        let database = database
        try await ensureZone(zoneName, in: database)
        // CKAsset needs a file; a temporary copy, removed once sent.
        let temporary = FileManager.default.temporaryDirectory
            .appending(path: "icloud-\(UUID().uuidString)-\(fileName)")
        try data.write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let record = CKRecord(recordType: Self.recordType, recordID: Self.recordID(fileName, zone: zoneName))
        record[Self.fileKey] = CKAsset(fileURL: temporary)
        do {
            // Replaces an earlier version of the file (a Pencil page edited).
            let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys, atomically: true)
            for (_, result) in saved { _ = try result.get() }
        } catch {
            if (error as? CKError)?.code == .zoneNotFound { await zones.forget(zoneName) }
            throw Self.mapped(error)
        }
    }

    func download(path: String) async throws -> Data {
        let (zoneName, fileName) = try Self.split(path)
        do {
            let record = try await database.record(for: Self.recordID(fileName, zone: zoneName))
            guard let url = (record[Self.fileKey] as? CKAsset)?.fileURL else { throw AttachmentStorageError.notFound }
            return try Data(contentsOf: url)
        } catch {
            throw Self.mapped(error)
        }
    }

    func remove(paths: [String]) async throws {
        let ids = try paths.map { path in
            let (zoneName, fileName) = try Self.split(path)
            return Self.recordID(fileName, zone: zoneName)
        }
        let database = database
        for start in stride(from: 0, to: ids.count, by: Self.batchSize) {
            let batch = Array(ids[start..<min(start + Self.batchSize, ids.count)])
            do {
                let (_, deleted) = try await database.modifyRecords(saving: [], deleting: batch, savePolicy: .allKeys, atomically: false)
                for (_, result) in deleted {
                    do { try result.get() } catch where Self.isGone(error) {}
                }
            } catch where Self.isGone(error) {
                // Already gone: nothing to remove.
            } catch {
                throw Self.mapped(error)
            }
        }
    }

    func removeAll(userID: UUID) async throws {
        let zoneName = Self.zoneName(for: userID.uuidString.lowercased())
        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: [CKRecordZone.ID(zoneName: zoneName)])
            await zones.forget(zoneName)
        } catch where Self.isGone(error) {
            await zones.forget(zoneName)
        } catch {
            throw Self.mapped(error)
        }
    }

    // MARK: Zones and names

    private func ensureZone(_ zoneName: String, in database: CKDatabase) async throws {
        guard await !zones.isReady(zoneName) else { return }
        do {
            // Saving a zone that exists already is harmless.
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneName: zoneName)], deleting: [])
            await zones.markReady(zoneName)
        } catch {
            throw Self.mapped(error)
        }
    }

    static func zoneName(for folder: String) -> String {
        "Attachments-\(folder)"
    }

    private static func recordID(_ fileName: String, zone zoneName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: fileName, zoneID: CKRecordZone.ID(zoneName: zoneName))
    }

    /// "<user id>/<file name>" → the account's zone and the record name.
    static func split(_ path: String) throws -> (zone: String, fileName: String) {
        let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { throw AttachmentStorageError.notFound }
        return (zoneName(for: parts[0]), parts[1])
    }

    // MARK: Errors

    private static func isGone(_ error: any Error) -> Bool {
        guard let code = (error as? CKError)?.code else { return false }
        return code == .unknownItem || code == .zoneNotFound || code == .userDeletedZone
    }

    /// CloudKit's errors as the ones the app explains.
    static func mapped(_ error: any Error) -> any Error {
        guard let ckError = error as? CKError else { return error }
        switch ckError.code {
        case .unknownItem, .zoneNotFound, .userDeletedZone:
            return AttachmentStorageError.notFound
        case .notAuthenticated, .permissionFailure, .managedAccountRestricted, .badContainer, .missingEntitlement:
            return AttachmentStorageError.iCloudUnavailable
        case .quotaExceeded:
            return AttachmentStorageError.iCloudFull
        case .partialFailure:
            if let first = ckError.partialErrorsByItemID?.values.first { return mapped(first) }
            return error
        default:
            return error
        }
    }
}

/// Zones known to exist this launch, so each is created at most once.
private actor ZoneCache {
    private var ready: Set<String> = []

    func isReady(_ zone: String) -> Bool { ready.contains(zone) }
    func markReady(_ zone: String) { ready.insert(zone) }
    func forget(_ zone: String) { ready.remove(zone) }
}
