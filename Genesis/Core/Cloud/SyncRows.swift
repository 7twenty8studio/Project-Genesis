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
    /// Rough size of the row's large fields in bytes, so pushes can be
    /// split into requests of a sensible size.
    var payloadWeight: Int { get }
}

extension SyncRow {
    var payloadWeight: Int { 0 }
}

/// Splits rows into push requests: at most `maxCount` rows, and no more than
/// `maxWeight` bytes of large fields unless a single row is that big alone.
enum SyncBatching {
    static func ranges(weights: [Int], maxCount: Int, maxWeight: Int) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        var weight = 0
        for (index, rowWeight) in weights.enumerated() {
            if index > start, index - start >= maxCount || weight + rowWeight > maxWeight {
                result.append(start..<index)
                start = index
                weight = 0
            }
            weight += rowWeight
        }
        if start < weights.count { result.append(start..<weights.count) }
        return result
    }
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
    /// The handwritten page as base64 (JSON's usual encoding for `Data`).
    var drawing: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: String?
    /// False when the drawing is too large to sync: the push then leaves the
    /// `drawing` key out, so the server keeps what it had. Not sent.
    var sendsDrawing = true

    enum CodingKeys: String, CodingKey {
        case id, userId, title, body, kind, anchorType, startVerse, endVerse, book, chapter, theme, drawing
        case createdAt, updatedAt, deletedAt, serverUpdatedAt
    }

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
        let drawingData = note.drawing
        sendsDrawing = NoteDrawing.fitsSync(drawingData)
        drawing = sendsDrawing ? drawingData?.base64EncodedString() : nil
        createdAt = note.createdAt
        updatedAt = note.updatedAt
    }

    /// The drawing's PencilKit data; nil when there is none or it isn't valid base64.
    var drawingData: Data? {
        drawing.flatMap { Data(base64Encoded: $0) }
    }

    var payloadWeight: Int {
        (drawing?.utf8.count ?? 0) + body.utf8.count
    }

    // Written by hand so `drawing` goes up as an explicit null when a drawing
    // is cleared (every row in a request then has the same keys), and is left
    // out entirely when it's too large to sync.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(kind, forKey: .kind)
        try container.encode(anchorType, forKey: .anchorType)
        try container.encodeIfPresent(startVerse, forKey: .startVerse)
        try container.encodeIfPresent(endVerse, forKey: .endVerse)
        try container.encodeIfPresent(book, forKey: .book)
        try container.encodeIfPresent(chapter, forKey: .chapter)
        try container.encodeIfPresent(theme, forKey: .theme)
        if sendsDrawing {
            try container.encode(drawing, forKey: .drawing)
        }
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
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

/// A passage on a prayer, as stored in prayers.passages (jsonb): verse ids only.
struct RemotePrayerPassage: Codable, Equatable, Sendable {
    var startVerse: Int
    var endVerse: Int
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
    /// Nil when the row comes from a server without the column (before
    /// 20261012000000_prayer_journal.sql); the local passages are then kept.
    var passages: [RemotePrayerPassage]?
    var lastPrayedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, userId, title, body, category, isAnswered, answeredAt, answerNote, reminderAt, reminderRepeatsDaily
        case passages, lastPrayedAt, createdAt, updatedAt, deletedAt, serverUpdatedAt
    }

    init(_ prayer: Prayer, userID: UUID) {
        id = prayer.id
        userId = userID
        title = prayer.title
        body = prayer.body
        // Normalised, so an unusual saved value still passes the table's check.
        category = prayer.category.rawValue
        isAnswered = prayer.isAnswered
        answeredAt = prayer.answeredAt
        answerNote = prayer.answerNote
        reminderAt = prayer.reminderAt
        reminderRepeatsDaily = prayer.reminderRepeatsDaily
        passages = prayer.passages.map { RemotePrayerPassage(startVerse: $0.start.rawValue, endVerse: $0.end.rawValue) }
        lastPrayedAt = prayer.lastPrayedAt
        createdAt = prayer.createdAt
        updatedAt = prayer.updatedAt
    }

    /// The passages to keep locally, or nil to leave the local ones alone.
    var prayerPassages: [PrayerPassage]? {
        passages?.compactMap { passage in
            guard passage.startVerse > 1_000_000, passage.endVerse > 1_000_000 else { return nil }
            return PrayerPassage(start: VerseID(rawValue: passage.startVerse), end: VerseID(rawValue: passage.endVerse))
        }
    }

    // Written by hand so cleared values go up as explicit nulls (moving a
    // prayer back to Praying clears answered_at on the server too) and every
    // row in a request has the same keys.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(category, forKey: .category)
        try container.encode(isAnswered, forKey: .isAnswered)
        try container.encodeOrNull(answeredAt, forKey: .answeredAt)
        try container.encodeOrNull(answerNote, forKey: .answerNote)
        try container.encodeOrNull(reminderAt, forKey: .reminderAt)
        try container.encode(reminderRepeatsDaily, forKey: .reminderRepeatsDaily)
        try container.encode(passages ?? [], forKey: .passages)
        try container.encodeOrNull(lastPrayedAt, forKey: .lastPrayedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
    }
}

struct RemoteMemoryVerse: SyncRow, Equatable {
    var id: UUID
    var userId: UUID
    var startVerse: Int
    var endVerse: Int
    var translationId: String
    var ease: Double
    var intervalDays: Double
    var repetitions: Int
    var dueAt: Date
    var lastReviewedAt: Date?
    var reviewCount: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: String?

    init(_ verse: MemoryVerse, userID: UUID) {
        id = verse.id
        userId = userID
        startVerse = verse.startRaw
        endVerse = verse.endRaw
        translationId = verse.translationID
        ease = verse.ease
        intervalDays = verse.intervalDays
        repetitions = verse.repetitions
        dueAt = verse.dueAt
        lastReviewedAt = verse.lastReviewedAt
        reviewCount = verse.reviewCount
        createdAt = verse.createdAt
        updatedAt = verse.updatedAt
    }
}

extension KeyedEncodingContainer {
    /// The value, or an explicit JSON null (never a missing key).
    mutating func encodeOrNull<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
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
