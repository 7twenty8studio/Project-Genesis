import Foundation

/// One verse exactly as stored in a translation database. `text` is verbatim
/// Scripture; the app never edits it. Poetry lines are separated by "\n".
struct Verse: Identifiable, Hashable, Sendable {
    let id: VerseID
    let text: String
    /// True when the verse opens a new paragraph or stanza.
    let startsParagraph: Bool
    /// True when the verse belongs to a poetic passage and is set line by line.
    let isPoetry: Bool

    /// Text on a single line, for copying, sharing and search results.
    var plainText: String { text.replacingOccurrences(of: "\n", with: " ") }
}

/// A heading that is part of the translation, e.g. a psalm superscription.
struct ChapterHeading: Hashable, Sendable {
    let beforeVerse: Int
    let text: String
}

struct Chapter: Identifiable, Hashable, Sendable {
    let id: ChapterID
    let verses: [Verse]
    let headings: [ChapterHeading]

    var book: BibleBook { id.bibleBook }
}

/// A Bible translation available to the app.
struct Translation: Identifiable, Hashable, Codable, Sendable {
    /// Short code, e.g. "KJV". Also the database file name.
    let id: String
    let name: String
    let year: String
    let license: String
    let summary: String
    /// The language of the text: "en", "es". Decides the narrating voice and
    /// the language of book names read aloud.
    let language: String

    var abbreviation: String { id }

    init(id: String, name: String, year: String, license: String, summary: String, language: String = "en") {
        self.id = id
        self.name = name
        self.year = year
        self.license = license
        self.summary = summary
        self.language = language
    }

    // Translations saved before languages were added have none: English.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        year = try container.decode(String.self, forKey: .year)
        license = try container.decode(String.self, forKey: .license)
        summary = try container.decode(String.self, forKey: .summary)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
    }
}

extension Translation {
    static let kjv = Translation(
        id: "KJV",
        name: "King James Version",
        year: "1769",
        license: "Public domain",
        summary: String(localized: "The classic English Bible, cherished for its majestic, poetic language.")
    )
    static let web = Translation(
        id: "WEB",
        name: "World English Bible",
        year: "2020",
        license: "Public domain. \u{201C}World English Bible\u{201D} is a trademark of eBible.org.",
        summary: String(localized: "A modern, readable translation in everyday English.")
    )
    static let asv = Translation(
        id: "ASV",
        name: "American Standard Version",
        year: "1901",
        license: "Public domain",
        summary: String(localized: "A precise, literal translation valued for careful study.")
    )

    /// Translations shipped inside the app bundle, in display order.
    static let bundled: [Translation] = [.kjv, .web, .asv]
}

/// A reference to a passage: a whole book, a chapter, or a verse range.
struct PassageReference: Hashable, Sendable, CustomStringConvertible {
    let book: BibleBook
    let chapter: Int?
    let verseStart: Int?
    let verseEnd: Int?

    init(book: BibleBook, chapter: Int? = nil, verseStart: Int? = nil, verseEnd: Int? = nil) {
        self.book = book
        self.chapter = chapter
        self.verseStart = verseStart
        self.verseEnd = verseEnd
    }

    init(verse: VerseID) {
        self.init(book: .withNumber(verse.book), chapter: verse.chapter, verseStart: verse.verse)
    }

    /// Builds a reference covering a set of verses in one chapter, e.g. "John 3:16–18".
    init?(verses: some Collection<VerseID>) {
        guard let first = verses.min(), let last = verses.max() else { return nil }
        self.init(
            book: .withNumber(first.book),
            chapter: first.chapter,
            verseStart: first.verse,
            verseEnd: last.chapterID == first.chapterID && last.verse != first.verse ? last.verse : nil
        )
    }

    var chapterID: ChapterID { ChapterID(book: book.id, chapter: chapter ?? 1) }

    var firstVerse: VerseID { VerseID(book: book.id, chapter: chapter ?? 1, verse: verseStart ?? 1) }

    var description: String {
        guard let chapter else { return book.name }
        // Single-chapter books are usually cited by verse alone ("Jude 3").
        guard let verseStart else { return "\(book.name) \(chapter)" }
        let prefix = book.chapterCount == 1 ? "\(book.name) " : "\(book.name) \(chapter):"
        if let verseEnd, verseEnd != verseStart {
            return "\(prefix)\(verseStart)\u{2013}\(verseEnd)"
        }
        return "\(prefix)\(verseStart)"
    }
}
