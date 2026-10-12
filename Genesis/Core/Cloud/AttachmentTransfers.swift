import Foundation
import Observation
import os
import SwiftData

/// Moves attachment files between this device and the person's iCloud.
///
/// - Uploads queue after the attachment's row has been pushed (SyncService
///   calls `run` at the end of each sync) and retry with a growing wait
///   (`AttachmentTransferQueue`) until they succeed.
/// - Downloads happen on demand, when an attachment is shown and its file
///   isn't on this device yet; screens show a placeholder meanwhile.
/// - Deleting an attachment removes its local file at once and its stored
///   object on the next run (best effort; retried like uploads).
@MainActor
@Observable
final class AttachmentTransfers {
    /// Attachments whose file is being downloaded.
    private(set) var downloading: Set<UUID> = []
    /// Attachments whose file couldn't be downloaded (not uploaded yet, or offline).
    private(set) var unavailable: Set<UUID> = []
    /// Why files aren't syncing (iCloud off or full), until a transfer works.
    private(set) var problem: AttachmentStorageError?

    @ObservationIgnored let files: AttachmentFiles
    @ObservationIgnored private let storage: any AttachmentStorage
    @ObservationIgnored private let defaults: UserDefaults
    /// Files an earlier version kept in the Supabase bucket go up again, to iCloud.
    @ObservationIgnored private let movesEarlierFiles: Bool
    @ObservationIgnored private var queue: AttachmentTransferQueue
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var retry: Task<Void, Never>?
    /// The signed-in account, whose storage folder files go to.
    @ObservationIgnored var userID: @MainActor () -> UUID? = { nil }
    /// Asks for a sync (which ends by calling `run`) when a retry is due.
    @ObservationIgnored var requestSync: (@MainActor () -> Void)?

    /// The app's instance, so StudyStore can discard files when deleting.
    static weak var app: AttachmentTransfers?

    private static let queueKey = "attachments.transferQueue"
    private static let movedKey = "attachments.movedToICloud"
    private static let log = Logger(subsystem: "com.7twenty8studio.genesis", category: "attachments")

    init(files: AttachmentFiles, storage: any AttachmentStorage, defaults: UserDefaults = .standard, movesEarlierFiles: Bool = false) {
        self.files = files
        self.storage = storage
        self.defaults = defaults
        self.movesEarlierFiles = movesEarlierFiles
        let saved = defaults.data(forKey: Self.queueKey).flatMap { try? JSONDecoder().decode(AttachmentTransferQueue.self, from: $0) }
        queue = saved ?? AttachmentTransferQueue()
    }

    var pendingOperations: [AttachmentTransferQueue.Operation] { queue.entries.map(\.operation) }

    // MARK: Local files

    /// The attachment's file, when it's on this device.
    func fileURL(for attachment: Attachment) -> URL? {
        files.exists(attachment.fileName) ? files.url(for: attachment.fileName) : nil
    }

    /// Removes a deleted attachment's file here, and later from cloud storage.
    func discard(fileName: String) {
        files.remove(fileName)
        queue.enqueue(.remove(fileName))
        saveQueue()
    }

    /// Signing out with "remove data": every file and pending transfer.
    func eraseAll() {
        retry?.cancel()
        files.removeAll()
        queue = AttachmentTransferQueue()
        saveQueue()
        downloading = []
        unavailable = []
        problem = nil
    }

    /// Deleting the account: every file it kept in iCloud. Best effort.
    func deleteCloudFiles(userID: UUID) async {
        do {
            try await storage.removeAll(userID: userID)
        } catch {
            let reason = error.localizedDescription
            Self.log.notice("Attachment files couldn't be deleted from iCloud: \(reason, privacy: .public)")
        }
    }

    // MARK: Downloads

    /// Downloads the attachment's file if it isn't here yet.
    func ensureFile(for attachment: Attachment) async {
        let id = attachment.id
        let fileName = attachment.fileName
        guard !files.exists(fileName), !downloading.contains(id), let user = userID() else { return }
        downloading.insert(id)
        defer { downloading.remove(id) }
        let path = AttachmentPaths.storagePath(userID: user, fileName: fileName)
        do {
            let data = try await storage.download(path: path)
            let store = files
            try await Task.detached { try store.write(data, to: fileName) }.value
            unavailable.remove(id)
        } catch {
            unavailable.insert(id)
            note(error)
            let reason = error.localizedDescription
            Self.log.notice("Attachment \(id.uuidString, privacy: .public) couldn't be downloaded: \(reason, privacy: .public)")
        }
    }

    // MARK: Uploads and removals

    /// Queues every attachment whose file hasn't reached cloud storage, then
    /// tries what's due. Called by SyncService after the rows are pushed.
    func run(context: ModelContext, now: Date = .now) async {
        guard !isRunning, let user = userID() else { return }
        isRunning = true
        defer { isRunning = false }
        if movesEarlierFiles { queueEarlierFiles(context: context) }
        let waiting = (try? context.fetch(FetchDescriptor<Attachment>(predicate: #Predicate { $0.needsUpload == true }))) ?? []
        for attachment in waiting { queue.enqueue(.upload(attachment.id), now: now) }
        for operation in queue.due(at: now) {
            await perform(operation, user: user, context: context, now: now)
        }
        saveQueue()
        scheduleRetry(now: now)
    }

    private func perform(_ operation: AttachmentTransferQueue.Operation, user: UUID, context: ModelContext, now: Date) async {
        do {
            switch operation {
            case let .upload(id):
                try await upload(id, user: user, context: context)
            case let .remove(fileName):
                try await storage.remove(paths: [AttachmentPaths.storagePath(userID: user, fileName: fileName)])
            }
            queue.succeeded(operation)
            problem = nil
        } catch {
            queue.failed(operation, at: now)
            note(error)
            let attempts = queue.attempts(for: operation)
            let reason = error.localizedDescription
            Self.log.notice("Attachment transfer failed (attempt \(attempts)): \(reason, privacy: .public)")
        }
    }

    private func upload(_ id: UUID, user: UUID, context: ModelContext) async throws {
        let key = id
        var descriptor = FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == key })
        descriptor.fetchLimit = 1
        // Deleted since it was queued, or its file never came to this device:
        // nothing to send.
        guard let attachment = try context.fetch(descriptor).first, attachment.needsUpload,
              files.exists(attachment.fileName) else { return }
        let fileName = attachment.fileName
        let contentType = attachment.kind.contentType
        let store = files
        let data = try await Task.detached { try store.read(fileName) }.value
        try await storage.upload(data, path: AttachmentPaths.storagePath(userID: user, fileName: fileName), contentType: contentType)
        // Local bookkeeping only: no edit time change and no sync notification.
        attachment.needsUpload = false
        try context.save()
    }

    /// Once: every file on this device goes up to iCloud (they were in the
    /// Supabase bucket, or recordings that stayed on the device), and the
    /// upload removes the bucket's copy.
    private func queueEarlierFiles(context: ModelContext) {
        guard !defaults.bool(forKey: Self.movedKey) else { return }
        let all = (try? context.fetch(FetchDescriptor<Attachment>())) ?? []
        for attachment in all where !attachment.needsUpload && files.exists(attachment.fileName) {
            attachment.needsUpload = true
        }
        do {
            try context.save()
            defaults.set(true, forKey: Self.movedKey)
        } catch {
            CrashReporter.record(error, context: "Attachments.queueEarlierFiles")
        }
    }

    /// Remembers why iCloud refused (shown under attachments).
    private func note(_ error: any Error) {
        if let error = error as? AttachmentStorageError, error == .iCloudUnavailable || error == .iCloudFull {
            problem = error
        }
    }

    private func scheduleRetry(now: Date) {
        retry?.cancel()
        guard let next = queue.nextDue else { return }
        let delay = max(1, next.timeIntervalSince(now))
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.requestSync?()
        }
    }

    private func saveQueue() {
        defaults.set(try? JSONEncoder().encode(queue), forKey: Self.queueKey)
    }
}
