import Foundation
import SwiftData

// Personal study data stored on device with SwiftData.
//
// Every record has a stable UUID plus created/updated timestamps so Phase 2
// cloud sync (Supabase) can merge changes between devices. Verses are stored
// as translation-independent `VerseID` raw values, so highlights and notes
// follow the reader across translations.

@Model
final class Bookmark {
    @Attribute(.unique) var id: UUID
    var verseRaw: Int
    var createdAt: Date
    var updatedAt: Date

    init(verse: VerseID, date: Date = .now) {
        id = UUID()
        verseRaw = verse.rawValue
        createdAt = date
        updatedAt = date
    }

    var verse: VerseID { VerseID(rawValue: verseRaw) }
}

@Model
final class Highlight {
    @Attribute(.unique) var id: UUID
    /// One highlight per verse; highlighting again changes the colour.
    @Attribute(.unique) var verseRaw: Int
    var colorRaw: String
    var createdAt: Date
    var updatedAt: Date
    var collection: HighlightCollection? = nil

    init(verse: VerseID, color: HighlightColor, date: Date = .now) {
        id = UUID()
        verseRaw = verse.rawValue
        colorRaw = color.rawValue
        createdAt = date
        updatedAt = date
    }

    var verse: VerseID { VerseID(rawValue: verseRaw) }

    var color: HighlightColor {
        get { HighlightColor(rawValue: colorRaw) ?? .yellow }
        set { colorRaw = newValue.rawValue }
    }
}

/// A named group of highlights, e.g. "Promises" or "Verses on peace".
@Model
final class HighlightCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .nullify, inverse: \Highlight.collection)
    var highlights: [Highlight] = []

    init(name: String, date: Date = .now) {
        id = UUID()
        self.name = name
        createdAt = date
        updatedAt = date
    }
}

enum NoteKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// `prayer` is only read from older data: prayers live in the Prayer
    /// Journal, and `StudyStore.movePrayerNotesToJournal` moves them there.
    case text, prayer, study, journal

    /// The kinds a note can be written as.
    static var allCases: [NoteKind] { [.text, .study, .journal] }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: String(localized: "Note")
        case .prayer: String(localized: "Prayer")
        case .study: String(localized: "Study", comment: "Note kind")
        case .journal: String(localized: "Journal")
        }
    }

    var systemImage: String {
        switch self {
        case .text: "note.text"
        case .prayer: "hands.and.sparkles"
        case .study: "book.pages"
        case .journal: "book.closed"
        }
    }
}

/// What a note is attached to.
enum NoteAnchor: Hashable, Sendable {
    case verses(VerseID, VerseID)
    case chapter(ChapterID)
    case book(Int)
    case theme(String)
    case none

    var title: String {
        switch self {
        case let .verses(start, end):
            PassageReference(verses: [start, end])?.description ?? ""
        case let .chapter(chapter):
            chapter.description
        case let .book(book):
            BibleBook.withNumber(book).name
        case let .theme(theme):
            theme
        case .none:
            ""
        }
    }

    /// The chapter to open when the note is tapped, if any.
    var chapter: ChapterID? {
        switch self {
        case let .verses(start, _): start.chapterID
        case let .chapter(chapter): chapter
        case let .book(book): ChapterID(book: book, chapter: 1)
        case .theme, .none: nil
        }
    }
}

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String
    var kindRaw: String
    /// "verses", "chapter", "book", "theme" or "none".
    var anchorType: String
    var startVerseRaw: Int? = nil
    var endVerseRaw: Int? = nil
    var bookNumber: Int? = nil
    var chapterNumber: Int? = nil
    var theme: String? = nil
    /// A handwritten page: `PKDrawing.dataRepresentation()`, or nil for none.
    /// Optional with a default, so existing stores migrate automatically.
    @Attribute(.externalStorage) var drawing: Data? = nil
    var createdAt: Date
    var updatedAt: Date

    init(kind: NoteKind, anchor: NoteAnchor, title: String = "", body: String = "", date: Date = .now) {
        id = UUID()
        self.title = title
        self.body = body
        kindRaw = kind.rawValue
        anchorType = "none"
        createdAt = date
        updatedAt = date
        self.anchor = anchor
    }

    var kind: NoteKind {
        get { NoteKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var anchor: NoteAnchor {
        get {
            switch anchorType {
            case "verses":
                guard let startVerseRaw else { return .none }
                return .verses(VerseID(rawValue: startVerseRaw), VerseID(rawValue: endVerseRaw ?? startVerseRaw))
            case "chapter":
                guard let bookNumber, let chapterNumber else { return .none }
                return .chapter(ChapterID(book: bookNumber, chapter: chapterNumber))
            case "book":
                guard let bookNumber else { return .none }
                return .book(bookNumber)
            case "theme":
                return .theme(theme ?? "")
            default:
                return .none
            }
        }
        set {
            startVerseRaw = nil
            endVerseRaw = nil
            bookNumber = nil
            chapterNumber = nil
            theme = nil
            switch newValue {
            case let .verses(start, end):
                anchorType = "verses"
                startVerseRaw = start.rawValue
                endVerseRaw = end.rawValue
                bookNumber = start.book
                chapterNumber = start.chapter
            case let .chapter(chapter):
                anchorType = "chapter"
                bookNumber = chapter.book
                chapterNumber = chapter.chapter
            case let .book(book):
                anchorType = "book"
                bookNumber = book
            case let .theme(name):
                anchorType = "theme"
                theme = name
            case .none:
                anchorType = "none"
            }
        }
    }

    /// Title to show in lists: the note's own title, else its first line.
    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        let firstLine = body.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        return firstLine.isEmpty ? kind.title : firstLine
    }
}

enum UserDataSchema {
    static var models: [any PersistentModel.Type] { [
        Bookmark.self, Highlight.self, HighlightCollection.self, Note.self,
        PlanEnrollment.self, Prayer.self, MemoryVerse.self, Sermon.self, Attachment.self, Tombstone.self,
    ] }
}
