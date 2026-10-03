import Foundation
import Observation
import SwiftData

/// Keeps highlights, notes, bookmarks, reading plans and prayers in step
/// between this device and the person's Supabase account.
///
/// Each sync pulls server changes first (newest edit wins per record), then
/// pushes local changes and deletions. Everything works offline; sync simply
/// catches up the next time it runs.
@MainActor
@Observable
final class SyncService {
    enum Status: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastSyncedAt: Date?

    @ObservationIgnored let auth: AuthService
    /// Cloud backup is part of Premium; the app sets this from the entitlement.
    /// Signing in still works without it (the study assistant needs an account).
    @ObservationIgnored var isAllowed: @MainActor () -> Bool = { true }
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var runAgain = false
    @ObservationIgnored private var observer: NSObjectProtocol?

    private let pageSize = 500
    private let pushBatchSize = 200
    private static let ownerKey = "sync.localDataOwner"

    init(auth: AuthService, container: ModelContainer, defaults: UserDefaults = .standard) {
        self.auth = auth
        self.container = container
        self.defaults = defaults
        if let user = auth.user {
            lastSyncedAt = defaults.object(forKey: key("lastSyncedAt", user.id)) as? Date
        }
    }

    private var context: ModelContext { container.mainContext }

    /// Starts listening for local changes and syncs once if signed in.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .genesisUserDataDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule(after: .seconds(3)) }
        }
        schedule(after: .zero)
    }

    /// Syncs soon, coalescing bursts of edits into one sync.
    func schedule(after delay: Duration = .seconds(2)) {
        guard auth.isSignedIn, isAllowed() else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    func syncNow() async {
        guard let user = auth.user, let client = auth.client, isAllowed() else { return }
        guard !isRunning else {
            runAgain = true
            return
        }
        isRunning = true
        status = .syncing
        defer { isRunning = false }

        repeat {
            runAgain = false
            do {
                try await sync(user: user, client: client)
                lastSyncedAt = .now
                defaults.set(lastSyncedAt, forKey: key("lastSyncedAt", user.id))
                status = .idle
            } catch {
                status = .failed(Self.message(for: error))
                return
            }
        } while runAgain
    }

    // MARK: Account changes

    /// Call when someone signs in. Guest data joins their account; data left
    /// by a *different* account is removed first so it can't leak across.
    func accountDidSignIn(_ user: AuthUser) {
        let owner = defaults.string(forKey: Self.ownerKey).flatMap(UUID.init(uuidString:))
        if let owner, owner != user.id {
            eraseLocalData()
        }
        defaults.set(user.id.uuidString, forKey: Self.ownerKey)
        lastSyncedAt = defaults.object(forKey: key("lastSyncedAt", user.id)) as? Date
        schedule(after: .zero)
    }

    /// Call after signing out.
    func accountDidSignOut(removeLocalData: Bool) {
        scheduled?.cancel()
        status = .idle
        lastSyncedAt = nil
        if removeLocalData {
            eraseLocalData()
            defaults.removeObject(forKey: Self.ownerKey)
        }
    }

    /// Removes all personal data from this device (not from the cloud).
    func eraseLocalData() {
        do {
            try context.delete(model: Highlight.self)
            try context.delete(model: HighlightCollection.self)
            try context.delete(model: Bookmark.self)
            try context.delete(model: Note.self)
            try context.delete(model: PlanEnrollment.self)
            try context.delete(model: Prayer.self)
            try context.delete(model: MemoryVerse.self)
            try context.delete(model: Tombstone.self)
            try context.save()
        } catch {
            CrashReporter.record(error, context: "Sync.eraseLocalData")
        }
        NotificationCenter.default.post(name: .genesisUserDataDidChange, object: nil)
    }

    // MARK: Sync

    private func sync(user: AuthUser, client: SupabaseClient) async throws {
        let token = try await auth.accessToken()
        let pushStartedAt = Date.now

        // Pull, parents before children.
        try await pull(SyncTable.highlightCollections, RemoteCollection.self, client, token, user, apply: apply)
        try await pull(SyncTable.highlights, RemoteHighlight.self, client, token, user, apply: apply)
        try await pull(SyncTable.bookmarks, RemoteBookmark.self, client, token, user, apply: apply)
        try await pull(SyncTable.notes, RemoteNote.self, client, token, user, apply: apply)
        try await pull(SyncTable.readingPlans, RemotePlan.self, client, token, user, apply: apply)
        try await pull(SyncTable.prayers, RemotePrayer.self, client, token, user, apply: apply)
        try await pull(SyncTable.memoryVerses, RemoteMemoryVerse.self, client, token, user, apply: apply)

        // Push everything edited since the last successful push.
        let since = defaults.object(forKey: key("lastPushedAt", user.id)) as? Date ?? .distantPast
        try await push(changed(HighlightCollection.self, since).map { RemoteCollection($0, userID: user.id) }, SyncTable.highlightCollections, client, token)
        try await push(changed(Highlight.self, since).map { RemoteHighlight($0, userID: user.id) }, SyncTable.highlights, client, token)
        try await push(changed(Bookmark.self, since).map { RemoteBookmark($0, userID: user.id) }, SyncTable.bookmarks, client, token)
        try await push(changed(Note.self, since).map { RemoteNote($0, userID: user.id) }, SyncTable.notes, client, token)
        try await push(changed(PlanEnrollment.self, since).map { RemotePlan($0, userID: user.id) }, SyncTable.readingPlans, client, token)
        try await push(changed(Prayer.self, since).map { RemotePrayer($0, userID: user.id) }, SyncTable.prayers, client, token)
        try await push(changed(MemoryVerse.self, since).map { RemoteMemoryVerse($0, userID: user.id) }, SyncTable.memoryVerses, client, token)
        try await pushDeletions(client, token)

        defaults.set(pushStartedAt, forKey: key("lastPushedAt", user.id))
        NotificationCenter.default.post(name: .genesisDidSync, object: nil)
    }

    private func pull<Row: SyncRow>(
        _ table: String,
        _ type: Row.Type,
        _ client: SupabaseClient,
        _ token: String,
        _ user: AuthUser,
        apply: (Row) -> Void
    ) async throws {
        let cursorKey = key("cursor.\(table)", user.id)
        var cursor = defaults.string(forKey: cursorKey)
        while true {
            let rows: [Row] = try await client.changes(in: table, since: cursor, limit: pageSize, accessToken: token)
            for row in rows { apply(row) }
            try context.save()
            if let last = rows.last?.serverUpdatedAt {
                cursor = last
                defaults.set(last, forKey: cursorKey)
            }
            if rows.count < pageSize { break }
        }
    }

    private func push<Row: SyncRow>(_ rows: [Row], _ table: String, _ client: SupabaseClient, _ token: String) async throws {
        var start = 0
        while start < rows.count {
            let batch = Array(rows[start..<min(start + pushBatchSize, rows.count)])
            try await client.upsert(batch, into: table, accessToken: token)
            start += pushBatchSize
        }
    }

    private func pushDeletions(_ client: SupabaseClient, _ token: String) async throws {
        let tombstones = (try? context.fetch(FetchDescriptor<Tombstone>())) ?? []
        let byTable = Dictionary(grouping: tombstones, by: \.table)
        for (table, group) in byTable {
            try await client.markDeleted(ids: group.map(\.recordID), in: table, at: .now, accessToken: token)
            for tombstone in group { context.delete(tombstone) }
            try context.save()
        }
    }

    private func changed<Model: PersistentModel & SyncTimestamped>(_ type: Model.Type, _ since: Date) -> [Model] {
        let all = (try? context.fetch(FetchDescriptor<Model>())) ?? []
        return all.filter { $0.updatedAt > since }
    }

    // MARK: Applying server changes

    // One fetch per type: SwiftData predicates need concrete model types.
    private func existing(_ type: Bookmark.Type, id: UUID) -> Bookmark? {
        first(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == id }))
    }

    private func existing(_ type: Highlight.Type, id: UUID) -> Highlight? {
        first(FetchDescriptor<Highlight>(predicate: #Predicate { $0.id == id }))
    }

    private func existing(_ type: HighlightCollection.Type, id: UUID) -> HighlightCollection? {
        first(FetchDescriptor<HighlightCollection>(predicate: #Predicate { $0.id == id }))
    }

    private func existing(_ type: Note.Type, id: UUID) -> Note? {
        first(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id }))
    }

    private func existing(_ type: PlanEnrollment.Type, id: UUID) -> PlanEnrollment? {
        first(FetchDescriptor<PlanEnrollment>(predicate: #Predicate { $0.id == id }))
    }

    private func existing(_ type: Prayer.Type, id: UUID) -> Prayer? {
        first(FetchDescriptor<Prayer>(predicate: #Predicate { $0.id == id }))
    }

    private func existing(_ type: MemoryVerse.Type, id: UUID) -> MemoryVerse? {
        first(FetchDescriptor<MemoryVerse>(predicate: #Predicate { $0.id == id }))
    }

    private func first<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> Model? {
        var limited = descriptor
        limited.fetchLimit = 1
        return (try? context.fetch(limited))?.first
    }

    private func isDeletedLocally(_ id: UUID) -> Bool {
        let key = id
        let found = (try? context.fetchCount(FetchDescriptor<Tombstone>(predicate: #Predicate { $0.recordID == key }))) ?? 0
        return found > 0
    }

    private func decision(for row: some SyncRow, local: Date?) -> SyncMerge.Decision {
        if isDeletedLocally(row.id) { return .keepLocal }
        return SyncMerge.decide(remoteUpdatedAt: row.updatedAt, remoteDeleted: row.deletedAt != nil, localUpdatedAt: local)
    }

    private func apply(_ row: RemoteCollection) {
        let local = existing(HighlightCollection.self, id: row.id)
        switch decision(for: row, local: local?.updatedAt) {
        case .keepLocal: return
        case .deleteLocal: if let local { context.delete(local) }
        case .applyRemote:
            let collection = local ?? {
                let created = HighlightCollection(name: row.name)
                created.id = row.id
                context.insert(created)
                return created
            }()
            collection.name = row.name
            collection.createdAt = row.createdAt
            collection.updatedAt = row.updatedAt
        }
    }

    private func apply(_ row: RemoteHighlight) {
        let local = existing(Highlight.self, id: row.id)
        switch decision(for: row, local: local?.updatedAt) {
        case .keepLocal: return
        case .deleteLocal: if let local { context.delete(local) }
        case .applyRemote:
            // One highlight per verse: resolve a different record for the same verse.
            let verse = row.verse
            let rowID = row.id
            let sameVerse = (try? context.fetch(FetchDescriptor<Highlight>(predicate: #Predicate { $0.verseRaw == verse && $0.id != rowID }))) ?? []
            for other in sameVerse {
                if other.updatedAt > row.updatedAt {
                    StudyStore(context: context).recordDeletion(of: row.id, in: SyncTable.highlights)
                    return
                }
                StudyStore(context: context).recordDeletion(of: other.id, in: SyncTable.highlights)
                context.delete(other)
            }
            if !sameVerse.isEmpty { try? context.save() }

            let highlight = local ?? {
                let created = Highlight(verse: VerseID(rawValue: row.verse), color: HighlightColor(rawValue: row.color) ?? .yellow)
                created.id = row.id
                context.insert(created)
                return created
            }()
            highlight.colorRaw = row.color
            highlight.collection = row.collectionId.flatMap { existing(HighlightCollection.self, id: $0) }
            highlight.createdAt = row.createdAt
            highlight.updatedAt = row.updatedAt
        }
    }

    private func apply(_ row: RemoteBookmark) {
        let local = existing(Bookmark.self, id: row.id)
        switch decision(for: row, local: local?.updatedAt) {
        case .keepLocal: return
        case .deleteLocal: if let local { context.delete(local) }
        case .applyRemote:
            let bookmark = local ?? {
                let created = Bookmark(verse: VerseID(rawValue: row.verse))
                created.id = row.id
                context.insert(created)
                return created
            }()
            bookmark.verseRaw = row.verse
            bookmark.createdAt = row.createdAt
            bookmark.updatedAt = row.updatedAt
        }
    }

    private func apply(_ row: RemoteNote) {
        let local = existing(Note.self, id: row.id)
        switch decision(for: row, local: local?.updatedAt) {
        case .keepLocal: return
        case .deleteLocal: if let local { context.delete(local) }
        case .applyRemote:
            let note = local ?? {
                let created = Note(kind: NoteKind(rawValue: row.kind) ?? .text, anchor: .none)
                created.id = row.id
                context.insert(created)
                return created
            }()
            note.title = row.title
            note.body = row.body
            note.kindRaw = row.kind
            note.anchorType = row.anchorType
            note.startVerseRaw = row.startVerse
            note.endVerseRaw = row.endVerse
            note.bookNumber = row.book
            note.chapterNumber = row.chapter
            note.theme = row.theme
            note.createdAt = row.createdAt
            note.updatedAt = row.updatedAt
        }
    }

    private func apply(_ row: RemotePlan) {
        let local = existing(PlanEnrollment.self, id: row.id)
        switch decision(for: row, local: local?.updatedAt) {
        case .keepLocal: return
        case .deleteLocal: if let local { context.delete(local) }
        case .applyRemote:
            let startDate = Timestamp.day(from: row.startDate) ?? .now
            let enrollment = local ?? {
                let created = PlanEnrollment(id: row.id, planID: row.planId, title: row.title, startDate: startDate)
                context.insert(created)
                return created
            }()
            enrollment.planID = row.planId
            enrollment.title = row.title
            enrollment.startDate = startDate
            enrollment.completedDays = Set(row.completedDays)
            enrollment.customBooksRaw = row.customBooks.map { $0.map(String.init).joined(separator: ",") }
            enrollment.customDays = row.customDays
            enrollment.isActive = row.isActive
            enrollment.createdAt = row.createdAt
            enrollment.updatedAt = row.updatedAt
        }
    }

    private func apply(_ row: RemoteMemoryVerse) {
        let local = existing(MemoryVerse.self, id: row.id)
        switch decision(for: row, local: local?.updatedAt) {
        case .keepLocal: return
        case .deleteLocal: if let local { context.delete(local) }
        case .applyRemote:
            let verse = local ?? {
                let created = MemoryVerse(start: VerseID(rawValue: row.startVerse), end: VerseID(rawValue: row.endVerse), translationID: row.translationId)
                created.id = row.id
                context.insert(created)
                return created
            }()
            verse.startRaw = row.startVerse
            verse.endRaw = row.endVerse
            verse.translationID = row.translationId
            verse.ease = row.ease
            verse.intervalDays = row.intervalDays
            verse.repetitions = row.repetitions
            verse.dueAt = row.dueAt
            verse.lastReviewedAt = row.lastReviewedAt
            verse.reviewCount = row.reviewCount
            verse.createdAt = row.createdAt
            verse.updatedAt = row.updatedAt
        }
    }

    private func apply(_ row: RemotePrayer) {
        let local = existing(Prayer.self, id: row.id)
        switch decision(for: row, local: local?.updatedAt) {
        case .keepLocal: return
        case .deleteLocal:
            if let local {
                PrayerReminders.cancel(prayerID: local.id)
                context.delete(local)
            }
        case .applyRemote:
            let prayer = local ?? {
                let created = Prayer()
                created.id = row.id
                context.insert(created)
                return created
            }()
            prayer.title = row.title
            prayer.body = row.body
            prayer.categoryRaw = row.category
            prayer.isAnswered = row.isAnswered
            prayer.answeredAt = row.answeredAt
            prayer.answerNote = row.answerNote
            prayer.reminderAt = row.reminderAt
            prayer.reminderRepeatsDaily = row.reminderRepeatsDaily
            prayer.createdAt = row.createdAt
            prayer.updatedAt = row.updatedAt
            PrayerReminders.update(for: prayer)
        }
    }

    // MARK: Helpers

    private func key(_ name: String, _ userID: UUID) -> String {
        "sync.\(userID.uuidString).\(name)"
    }

    private static func message(for error: Error) -> String {
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(urlError.code) {
            return String(localized: "You're offline. Changes are saved on this device and will sync later.")
        }
        return error.localizedDescription
    }
}

extension Notification.Name {
    /// Posted after a sync finishes, so screens and widgets can refresh.
    static let genesisDidSync = Notification.Name("genesisDidSync")
}

/// Models that carry an edit timestamp.
protocol SyncTimestamped: AnyObject {
    var updatedAt: Date { get }
}

extension Bookmark: SyncTimestamped {}
extension Highlight: SyncTimestamped {}
extension HighlightCollection: SyncTimestamped {}
extension Note: SyncTimestamped {}
extension PlanEnrollment: SyncTimestamped {}
extension Prayer: SyncTimestamped {}
extension MemoryVerse: SyncTimestamped {}
