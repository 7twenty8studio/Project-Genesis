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
    /// The last verse when the translation joins several into one ("16–17",
    /// as some licensed Bibles do); the text is on the first.
    var lastVerse: Int? = nil

    /// Text on a single line, for copying, sharing and search results.
    var plainText: String { text.replacingOccurrences(of: "\n", with: " ") }

    /// The number printed before the verse: "16", or "16–17" for joined verses.
    var numberLabel: String {
        guard let lastVerse, lastVerse > id.verse else { return "\(id.verse)" }
        return "\(id.verse)\u{2013}\(lastVerse)"
    }
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
    /// The publisher's copyright notice, shown under the chapter, for a
    /// licensed Bible (nil for public-domain ones).
    var copyrightNotice: String? = nil

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
    /// Only with Premium: a Bible whose publisher charges Versely a licence
    /// fee (bible_translations.premium). Every Bible Versely may offer free
    /// is free for everyone.
    var requiresPremium: Bool = false

    var abbreviation: String { id }

    /// A Bible used under a publisher's licence (from the Digital Bible
    /// Library): its `license` is the copyright statement the licence
    /// requires, shown under every chapter. Public-domain Bibles say so in
    /// `license` ("Public domain", "Dominio público").
    var isLicensed: Bool {
        TranslationProfile.rights(fromLicense: license) != .publicDomain
    }

    init(id: String, name: String, year: String, license: String, summary: String, language: String = "en", requiresPremium: Bool = false) {
        self.id = id
        self.name = name
        self.year = year
        self.license = license
        self.summary = summary
        self.language = language
        self.requiresPremium = requiresPremium
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
        requiresPremium = try container.decodeIfPresent(Bool.self, forKey: .requiresPremium) ?? false
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

    var description: String { description(in: AppLanguage.code) }

    /// The reference with the book named in a given language ("en", "es").
    func description(in language: String) -> String {
        let name = book.name(in: language)
        guard let chapter else { return name }
        // Single-chapter books are usually cited by verse alone ("Jude 3").
        guard let verseStart else { return "\(name) \(chapter)" }
        let prefix = book.chapterCount == 1 ? "\(name) " : "\(name) \(chapter):"
        if let verseEnd, verseEnd != verseStart {
            return "\(prefix)\(verseStart)\u{2013}\(verseEnd)"
        }
        return "\(prefix)\(verseStart)"
    }
}
