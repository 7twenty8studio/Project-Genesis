import Foundation

// Rows as stored in Supabase (see supabase/migrations). Keys are converted to
// snake_case by SupabaseCoding. `serverUpdatedAt` is set by the database and
// read only; it is kept as the raw string so paging cursors keep full precision.

/// Fields every synced row has.
protocol SyncRow: Codable, Sendable {
    var id: UUID { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
    var serverUpdatedAt: String? { get }
}

struct RemoteBookmark: SyncRow, Equatable {
    var id: UUID
    var userId: UUID
    var verse: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: String?

    init(_ bookmark: Bookmark, userID: UUID) {
        id = bookmark.id
        userId = userID
        verse = bookmark.verseRaw
        createdAt = bookmark.createdAt
        updatedAt = bookmark.updatedAt
    }
}

struct RemoteCollection: SyncRow, Equatable {
    var id: UUID
    var userId: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: String?

    init(_ collection: HighlightCollection, userID: UUID) {
        id = collection.id
        userId = userID
        name = collection.name
        createdAt = collection.createdAt
        updatedAt = collection.updatedAt
    }
}

struct RemoteHighlight: SyncRow, Equatable {
    var id: UUID
    var userId: UUID
    var verse: Int
    var color: String
    var collectionId: UUID?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: String?

    init(_ highlight: Highlight, userID: UUID) {
        id = highlight.id
        userId = userID
        verse = highlight.verseRaw
        color = highlight.colorRaw
        collectionId = highlight.collection?.id
        createdAt = highlight.createdAt
        updatedAt = highlight.updatedAt
    }
}

struct RemoteNote: SyncRow, Equatable {
    var id: UUID
    var userId: UUID
    var title: String
    var body: String
    var kind: String
    var anchorType: String
    var startVerse: Int?
    var endVerse: Int?
    var book: Int?
    var chapter: Int?
    var theme: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: String?

    init(_ note: Note, userID: UUID) {
        id = note.id
        userId = userID
        title = note.title
        body = note.body
        kind = note.kindRaw
        anchorType = note.anchorType
        startVerse = note.startVerseRaw
        endVerse = note.endVerseRaw
        book = note.bookNumber
        chapter = note.chapterNumber
        theme = note.theme
        createdAt = note.createdAt
        updatedAt = note.updatedAt
    }
}

struct RemotePlan: SyncRow, Equatable {
    var id: UUID
    var userId: UUID
    var planId: String
    var title: String
    /// "yyyy-MM-dd".
    var startDate: String
    var completedDays: [Int]
    var customBooks: [Int]?
    var customDays: Int?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: String?

    init(_ enrollment: PlanEnrollment, userID: UUID) {
        id = enrollment.id
        userId = userID
        planId = enrollment.planID
        title = enrollment.title
        startDate = Timestamp.dayString(from: enrollment.startDate)
        completedDays = enrollment.completedDays.sorted()
        customBooks = enrollment.customBooksRaw == nil ? nil : enrollment.customBooks
        customDays = enrollment.customDays
        isActive = enrollment.isActive
        createdAt = enrollment.createdAt
        updatedAt = enrollment.updatedAt
    }
}

struct RemotePrayer: SyncRow, Equatable {
    var id: UUID
    var userId: UUID
    var title: String
    var body: String
    var category: String
    var isAnswered: Bool
    var answeredAt: Date?
    var answerNote: String?
    var reminderAt: Date?
    var reminderRepeatsDaily: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: String?

    init(_ prayer: Prayer, userID: UUID) {
        id = prayer.id
        userId = userID
        title = prayer.title
        body = prayer.body
        category = prayer.categoryRaw
        isAnswered = prayer.isAnswered
        answeredAt = prayer.answeredAt
        answerNote = prayer.answerNote
        reminderAt = prayer.reminderAt
        reminderRepeatsDaily = prayer.reminderRepeatsDaily
        createdAt = prayer.createdAt
        updatedAt = prayer.updatedAt
    }
}

/// Last-writer-wins decision for a pulled row against the local copy.
enum SyncMerge {
    enum Decision: Equatable {
        /// Create or overwrite the local record from the server.
        case applyRemote
        /// Delete the local record (deleted on another device).
        case deleteLocal
        /// Keep the local record; it is newer and will be pushed.
        case keepLocal
    }

    static func decide(remoteUpdatedAt: Date, remoteDeleted: Bool, localUpdatedAt: Date?) -> Decision {
        guard let localUpdatedAt else {
            return remoteDeleted ? .keepLocal : .applyRemote
        }
        // Timestamps round-trip through the server at millisecond precision.
        if localUpdatedAt.timeIntervalSince(remoteUpdatedAt) > 0.001 { return .keepLocal }
        return remoteDeleted ? .deleteLocal : .applyRemote
    }
}
