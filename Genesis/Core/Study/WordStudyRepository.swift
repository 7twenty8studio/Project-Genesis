import Foundation
import SwiftUI

/// Word study and commentary, read from the bundled WordStudy.sqlite: the
/// Hebrew and Greek words of every verse with their Strong's numbers, a
/// lexicon of definitions, and Matthew Henry's Concise Commentary.
///
/// Data: STEPBible TAHOT, TAGNT, TBESH and TBESG (CC BY 4.0, Tyndale House
/// Cambridge); Hebrew definitions from Strong's dictionary via the Open
/// Scriptures Hebrew Bible project (CC BY 4.0); Matthew Henry's Concise
/// Commentary (public domain). Built by Tools/StudyData/build_wordstudy.py.
/// It holds no English verse text: verses come from the Bible databases.
/// Verse ids follow the KJV's versification.
final class WordStudyRepository: Sendable {
    static let attribution = String(localized: "Hebrew and Greek words, glosses and Greek definitions from STEPBible.org, based on work at Tyndale House Cambridge (CC BY 4.0). Hebrew definitions from Strong's Hebrew Dictionary via the Open Scriptures Hebrew Bible project (CC BY 4.0). Commentary from Matthew Henry's Concise Commentary (public domain).")

    private let database: SQLiteDatabase

    init(url: URL) throws {
        database = try SQLiteDatabase(readOnly: url)
    }

    /// The bundled database, or nil if it's missing from the build.
    static func bundled(in bundle: Bundle = .main) -> WordStudyRepository? {
        bundle.url(forResource: "WordStudy", withExtension: "sqlite").flatMap { try? WordStudyRepository(url: $0) }
    }

    // MARK: Words

    /// The verse's Hebrew or Greek words, in the original order.
    func words(in verse: VerseID) throws -> [OriginalWord] {
        try database.query(
            "SELECT w.position, f.text, f.translit, f.strongs, f.gloss, f.morph FROM word_forms w JOIN forms f ON f.id = w.form WHERE w.verse = ? ORDER BY w.position",
            [.int(verse.rawValue)]
        ) {
            OriginalWord(
                verse: verse,
                position: $0.int(0),
                text: $0.text(1),
                transliteration: $0.text(2),
                strongs: $0.isNull(3) ? nil : $0.text(3),
                gloss: $0.text(4),
                morphology: $0.text(5)
            )
        }
    }

    // MARK: Lexicon

    /// The lexicon entry for a Strong's number ("H430", "H0430G", "g2316").
    /// An extended number with no entry of its own (H1254C) falls back to its
    /// plain number's first entry.
    func entry(strongs: String) throws -> LexiconEntry? {
        guard let tag = StrongsNumber.normalized(strongs) else { return nil }
        let columns = "SELECT strongs, lemma, translit, gloss, definition, derivation, usage, language FROM lexicon"
        if let exact = try database.query("\(columns) WHERE strongs = ?", [.text(tag)], map: Self.entry).first {
            return exact
        }
        let related = Self.family(of: StrongsNumber.base(of: tag))
        return try database.query("\(columns) WHERE \(related.sql) ORDER BY strongs LIMIT 1", related.arguments, map: Self.entry).first
    }

    /// How many words in the Bible carry the number. A plain number (H430)
    /// counts all its extended forms (H0430G, H0430H, …).
    func occurrences(of strongs: String) throws -> Int {
        guard let filter = Self.filter(for: strongs) else { return 0 }
        return try database.query("SELECT COALESCE(SUM(count), 0) FROM occurrences WHERE \(filter.sql)", filter.arguments) { $0.int(0) }.first ?? 0
    }

    /// Verses that use the number, in canonical order.
    func verses(using strongs: String, limit: Int = 200) throws -> [VerseID] {
        guard let filter = Self.filter(for: strongs), limit > 0 else { return [] }
        let lists = try database.query("SELECT verses FROM occurrences WHERE \(filter.sql)", filter.arguments) { $0.text(0) }
        let ids = lists.count == 1 ? Self.decodeVerses(lists[0]) : Array(Set(lists.flatMap(Self.decodeVerses))).sorted()
        return ids.prefix(limit).map(VerseID.init(rawValue:))
    }

    // MARK: Commentary

    /// Commentary passages that take in the verse (usually one).
    func commentary(for verse: VerseID) throws -> [CommentaryPassage] {
        // Passages never cross a chapter, so the chapter's start bounds the search.
        let chapterStart = VerseID(book: verse.book, chapter: verse.chapter, verse: 0).rawValue
        return try database.query(
            "\(Self.commentaryColumns) WHERE start_verse BETWEEN ? AND ? AND end_verse >= ? ORDER BY start_verse, id",
            [.int(chapterStart), .int(verse.rawValue), .int(verse.rawValue)], map: Self.passage
        )
    }

    /// Every commentary passage on a chapter, in order.
    func commentary(inChapter chapter: ChapterID) throws -> [CommentaryPassage] {
        let range = chapter.verseRange
        return try database.query(
            "\(Self.commentaryColumns) WHERE start_verse BETWEEN ? AND ? ORDER BY start_verse, id",
            [.int(range.lowerBound), .int(range.upperBound)], map: Self.passage
        )
    }

    /// Henry's introduction to a book (1–66), if he wrote one.
    func introduction(toBook book: Int) throws -> String? {
        try database.query("SELECT text FROM introductions WHERE book = ? LIMIT 1", [.int(book)]) { $0.text(0) }.first
    }

    // MARK: Rows

    private static let commentaryColumns = "SELECT id, source, start_verse, end_verse, title, text FROM commentary"

    private static func entry(_ row: SQLiteDatabase.Row) -> LexiconEntry {
        LexiconEntry(
            strongs: row.text(0),
            lemma: row.text(1),
            transliteration: row.text(2),
            gloss: row.text(3),
            definition: row.text(4),
            derivation: row.text(5),
            usage: row.text(6),
            language: OriginalLanguage(rawValue: row.text(7)) ?? (row.text(0).hasPrefix("G") ? .greek : .hebrew)
        )
    }

    private static func passage(_ row: SQLiteDatabase.Row) -> CommentaryPassage {
        CommentaryPassage(
            id: row.int(0),
            source: row.text(1),
            start: VerseID(rawValue: row.int(2)),
            end: VerseID(rawValue: row.int(3)),
            title: row.isNull(4) ? nil : row.text(4),
            text: row.text(5)
        )
    }

    /// A number with a letter (H0430G) matches only itself; a plain one
    /// (H0430) matches itself and its extended forms.
    private static func filter(for strongs: String) -> (sql: String, arguments: [SQLiteDatabase.Value])? {
        guard let tag = StrongsNumber.normalized(strongs) else { return nil }
        if tag == StrongsNumber.base(of: tag) {
            return family(of: tag)
        }
        return ("strongs = ?", [.text(tag)])
    }

    /// "H0430" and "H0430A"…"H0430Z", but not "H04300" (five-digit numbers exist in Greek).
    private static func family(of base: String) -> (sql: String, arguments: [SQLiteDatabase.Value]) {
        ("(strongs = ? OR (strongs BETWEEN ? AND ? AND length(strongs) = ?))",
         [.text(base), .text(base + "A"), .text(base + "Z"), .int(base.count + 1)])
    }

    /// "1001001,2,998" -> [1001001, 1001003, 1002001]: ascending ids stored as deltas.
    static func decodeVerses(_ text: String) -> [Int] {
        var total = 0
        return text.split(separator: ",").compactMap { part in
            guard let delta = Int(part) else { return nil }
            total += delta
            return total
        }
    }
}

/// The language of a word or lexicon entry. Hebrew includes the Bible's Aramaic.
enum OriginalLanguage: String, Hashable, Sendable {
    case hebrew
    case greek
}

/// One Hebrew or Greek word of a verse, verbatim from the source text.
struct OriginalWord: Identifiable, Hashable, Sendable {
    let verse: VerseID
    /// 1… in the original-language word order.
    let position: Int
    /// The word as written, with its pointing or accents.
    let text: String
    let transliteration: String
    /// STEPBible's extended Strong's number (H0430G, G2316), if tagged.
    let strongs: String?
    /// English gloss in this context.
    let gloss: String
    /// Morphology code (ETCBC for Hebrew, Robinson style for Greek).
    let morphology: String

    var id: Int { verse.rawValue * 100 + position }
    var language: OriginalLanguage { verse.book >= 40 ? .greek : .hebrew }
}

/// A lexicon entry for one Strong's number.
struct LexiconEntry: Identifiable, Hashable, Sendable {
    let strongs: String
    let lemma: String
    let transliteration: String
    let gloss: String
    /// Plain text; may contain line breaks. Empty when the source has none.
    let definition: String
    /// Strong's note on where the word comes from (Hebrew only).
    let derivation: String
    /// How the KJV renders the word, from Strong's (Hebrew only).
    let usage: String
    let language: OriginalLanguage

    var id: String { strongs }
}

/// A commentary section on a run of verses within one chapter.
struct CommentaryPassage: Identifiable, Hashable, Sendable {
    let id: Int
    /// "mhcc": Matthew Henry's Concise Commentary.
    let source: String
    let start: VerseID
    let end: VerseID
    /// Henry's heading for the section, when he gave one.
    let title: String?
    /// Paragraphs separated by blank lines.
    let text: String

    var paragraphs: [String] {
        text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
    }

    var reference: PassageReference {
        PassageReference(
            book: .withNumber(start.book),
            chapter: start.chapter,
            verseStart: start.verse,
            verseEnd: end.verse == start.verse ? nil : end.verse
        )
    }

    func covers(_ verse: VerseID) -> Bool {
        (start...end).contains(verse)
    }
}

/// Strong's numbers as WordStudy.sqlite stores them: H or G, at least four
/// digits, and an optional upper-case letter (H0430G, H1254A, G2316).
enum StrongsNumber {
    /// "h430" -> "H0430", "H1254a" -> "H1254A", "G2316" -> "G2316"; nil if it isn't one.
    static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard let letter = trimmed.first, letter == "H" || letter == "G" else { return nil }
        let rest = trimmed.dropFirst()
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        let suffix = rest.dropFirst(digits.count)
        guard !digits.isEmpty, digits.count <= 5, let number = Int(String(digits)),
              suffix.count <= 1, suffix.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return nil }
        let padded = String(number)
        let zeros = String(repeating: "0", count: max(0, 4 - padded.count))
        return "\(letter)\(zeros)\(padded)\(suffix)"
    }

    /// "H1254A" -> "H1254".
    static func base(of tag: String) -> String {
        guard let last = tag.last, last.isLetter, tag.count > 1 else { return tag }
        return String(tag.dropLast())
    }
}

extension EnvironmentValues {
    /// Original-language words, lexicon and commentary (nil if WordStudy.sqlite is missing from the build).
    @Entry var wordStudy: WordStudyRepository? = nil
}
