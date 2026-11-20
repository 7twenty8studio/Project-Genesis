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
/// Verse ids follow the KJV's versification (`OriginalVersification` lines
/// other Bibles up with it). The Greek is held in four editions
/// (`GreekEdition`), each word marked with the editions that have it.
final class WordStudyRepository: Sendable {
    static let attribution = String(localized: "Hebrew and Greek words, glosses and Greek definitions from STEPBible.org, based on work at Tyndale House Cambridge (CC BY 4.0). Hebrew definitions from Strong's Hebrew Dictionary via the Open Scriptures Hebrew Bible project (CC BY 4.0). Commentary from Matthew Henry's Concise Commentary (public domain).")

    /// The lexicon's glosses, definitions and origins (lexicon_translations,
    /// Tools/StudyData/lexicon.py) and Matthew Henry's commentary
    /// (commentary_translations, Tools/StudyData/commentary.py) are also in
    /// these languages; the meanings in a verse and the grammar are English
    /// only, so screens say so when the Bible or the app is in another language.
    static func needsEnglishNote(bibleLanguage: String) -> Bool {
        bibleLanguage != "en" || AppLanguage.code != "en"
    }

    /// Languages the lexicon is translated into. Only these reach the SQL below.
    static let translatedLanguages: Set<String> = ["es", "pt"]

    /// Shown under a translated definition.
    static let translatedNote = String(localized: "Definitions translated from Strong's Hebrew Dictionary (1890) and Abbott-Smith's Greek Lexicon (1922). Not Scripture.")

    /// Shown under a translated commentary section or introduction.
    static let translatedCommentaryNote = String(localized: "Translated from Matthew Henry's Concise Commentary. Not Scripture.")

    /// The credit for the Bible words a translated section quotes (set in
    /// italics): the Reina-Valera 1909 in Spanish, the Bíblia Livre in
    /// Portuguese (its CC BY 4.0 Brasil licence asks for the credit).
    static func quotationCredit(language: String) -> String? {
        switch language {
        case "es": String(localized: "Scripture in italics: Reina-Valera 1909 (public domain).")
        case "pt": String(localized: "Scripture in italics: Bíblia Livre (BLIVRE), © Diego Santos, Mario Sérgio and Marco Teles, February 2018, CC BY 4.0 Brasil.")
        default: nil
        }
    }

    private let database: SQLiteDatabase
    /// "es" or "pt" when the database has that language's lexicon; nil for English.
    let language: String?
    /// "es" or "pt" when the database has Matthew Henry in that language
    /// (commentary_translations, Tools/StudyData/commentary.py); nil for English.
    let commentaryLanguage: String?
    /// The language of Versely's editorial notes on the commentary
    /// (editorial_notes): "es", "pt" or "en"; nil when the database has none.
    private let noteLanguage: String?
    private let hasQuotations: Bool

    /// - Parameter language: the app's language code ("en", "es", "pt");
    ///   nil or one without a translated lexicon shows the English.
    init(url: URL, language: String? = nil) throws {
        let database = try SQLiteDatabase(readOnly: url)
        func hasTable(_ name: String) throws -> Bool {
            try !database.query("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [.text(name)], map: { _ in true }).isEmpty
        }
        let translated = language.flatMap { Self.translatedLanguages.contains($0) ? $0 : nil }
        self.database = database
        self.language = try hasTable("lexicon_translations") ? translated : nil
        self.commentaryLanguage = try hasTable("commentary_translations") ? translated : nil
        self.noteLanguage = try hasTable("editorial_notes") ? (translated ?? "en") : nil
        self.hasQuotations = try hasTable("commentary_quotations")
    }

    /// The bundled database, or nil if it's missing from the build.
    static func bundled(in bundle: Bundle = .main, language: String? = AppLanguage.code) -> WordStudyRepository? {
        bundle.url(forResource: "WordStudy", withExtension: "sqlite").flatMap { try? WordStudyRepository(url: $0, language: language) }
    }

    // MARK: Words

    /// The verse's Hebrew or Greek words, in the original order. A New
    /// Testament verse is read from one Greek edition (`greek`), in its
    /// words, spelling and order.
    func words(in verse: VerseID, greek edition: GreekEdition = .textusReceptus) throws -> [OriginalWord] {
        try words(inVerses: [verse], greek: edition)[verse] ?? []
    }

    /// The words of several verses (KJV numbering) in one query, by verse,
    /// each in the original order, the Greek from one edition. Meant for a
    /// chapter's verses, which lie close together; verses with no words are
    /// left out.
    func words(inVerses verses: some Collection<VerseID>, greek edition: GreekEdition = .textusReceptus) throws -> [VerseID: [OriginalWord]] {
        guard let low = verses.min(), let high = verses.max() else { return [:] }
        let wanted = Set(verses)
        var rows: [OriginalWord] = []
        if low.book < 40 {
            rows += try database.query(
                "\(Self.hebrewColumns) WHERE w.verse BETWEEN ? AND ? ORDER BY w.verse, w.position",
                [.int(low.rawValue), .int(high.rawValue)], map: Self.hebrewWord
            )
        }
        if high.book >= 40 {
            rows += try database.query(
                "\(Self.greekColumns) WHERE g.verse BETWEEN ? AND ? AND (g.editions & ?) != 0 ORDER BY g.verse, g.slot, g.number",
                [.int(low.rawValue), .int(high.rawValue), .int(edition.rawValue)]
            ) { Self.greekWord($0, edition: edition) }
        }
        return Dictionary(grouping: rows.filter { wanted.contains($0.verse) }, by: \.verse)
    }

    /// The word another edition has at the same place as a Greek word, if
    /// it has one there (Luke 2:14: Nestle-Aland's εὐδοκίας where the
    /// Textus Receptus has εὐδοκία). Nil when it has no word there.
    func reading(at word: OriginalWord, in edition: GreekEdition) throws -> String? {
        guard word.language == .greek else { return nil }
        return try database.query(
            "SELECT f.text FROM greek_words g JOIN forms f ON f.id = g.form WHERE g.verse = ? AND g.number = ? AND (g.editions & ?) != 0 LIMIT 1",
            [.int(word.verse.rawValue), .int(word.position), .int(edition.rawValue)]
        ) { $0.text(0) }.first
    }

    // MARK: Lexicon

    /// The lexicon entry for a Strong's number ("H430", "H0430G", "g2316").
    /// An extended number with no entry of its own (H1254C) falls back to its
    /// plain number's first entry.
    func entry(strongs: String) throws -> LexiconEntry? {
        guard let tag = StrongsNumber.normalized(strongs) else { return nil }
        let columns = entryColumns
        if let exact = try database.query("\(columns) WHERE lexicon.strongs = ?", [.text(tag)], map: Self.entry).first {
            return exact
        }
        let related = Self.family(of: StrongsNumber.base(of: tag), column: "lexicon.strongs")
        return try database.query("\(columns) WHERE \(related.sql) ORDER BY lexicon.strongs LIMIT 1", related.arguments, map: Self.entry).first
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
        return try withEditorialNotes(database.query(
            "\(commentaryColumns) WHERE c.start_verse BETWEEN ? AND ? AND c.end_verse >= ? ORDER BY c.start_verse, c.id",
            [.int(chapterStart), .int(verse.rawValue), .int(verse.rawValue)], map: Self.passage
        ))
    }

    /// Every commentary passage on a chapter, in order.
    func commentary(inChapter chapter: ChapterID) throws -> [CommentaryPassage] {
        let range = chapter.verseRange
        return try withEditorialNotes(database.query(
            "\(commentaryColumns) WHERE c.start_verse BETWEEN ? AND ? ORDER BY c.start_verse, c.id",
            [.int(range.lowerBound), .int(range.upperBound)], map: Self.passage
        ))
    }

    /// Henry's introduction to a book (1–66), if he wrote one.
    func introduction(toBook book: Int) throws -> String? {
        try bookIntroduction(book)?.text
    }

    /// Henry's introduction to a book, in the app's language where it's
    /// translated (`isTranslated`: show `translatedCommentaryNote`).
    func bookIntroduction(_ book: Int) throws -> (text: String, isTranslated: Bool)? {
        guard let commentaryLanguage else {
            return try database.query("SELECT text FROM introductions WHERE book = ? LIMIT 1", [.int(book)]) { ($0.text(0), false) }.first
        }
        return try database.query(
            """
            SELECT COALESCE(tr.text, i.text), tr.book IS NOT NULL FROM introductions i
            LEFT JOIN introduction_translations tr ON tr.lang = ? AND tr.source = i.source AND tr.book = i.book
            WHERE i.book = ? LIMIT 1
            """,
            [.text(commentaryLanguage), .int(book)]
        ) { ($0.text(0), $0.int(1) != 0) }.first
    }

    /// Versely's editorial notes (editorial_notes) and the translation's
    /// Bible quotations (commentary_quotations), set on their passages.
    private func withEditorialNotes(_ passages: [CommentaryPassage]) throws -> [CommentaryPassage] {
        guard !passages.isEmpty else { return passages }
        let ids = passages.map(\.id)
        let marks = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        var passages = passages
        if let commentaryLanguage, hasQuotations {
            let quotations = try database.query(
                "SELECT id, text FROM commentary_quotations WHERE lang = ? AND id IN (\(marks)) ORDER BY id, n",
                [.text(commentaryLanguage)] + ids.map { .int($0) }
            ) { (id: $0.int(0), text: $0.text(1)) }
            for index in passages.indices where passages[index].isTranslated {
                passages[index].quotations = quotations.filter { $0.id == passages[index].id }.map(\.text)
                passages[index].quotationLanguage = commentaryLanguage
            }
        }
        guard let noteLanguage else { return passages }
        let notes = try database.query(
            "SELECT section, paragraph, text FROM editorial_notes WHERE lang = ? AND section IN (\(marks))",
            [.text(noteLanguage)] + ids.map { .int($0) }
        ) { (section: $0.int(0), paragraph: $0.int(1), text: $0.text(2)) }
        guard !notes.isEmpty else { return passages }
        return passages.map { passage in
            var passage = passage
            for note in notes where note.section == passage.id && passage.source == "mhcc" {
                passage.editorialNotes[note.paragraph] = note.text
            }
            return passage
        }
    }

    // MARK: Rows

    private static let hebrewColumns = """
        SELECT w.verse, w.position, f.text, f.translit, f.strongs, f.gloss, f.morph
        FROM word_forms w JOIN forms f ON f.id = w.form
        """

    private static let greekColumns = """
        SELECT g.verse, g.number, f.text, f.translit, f.strongs, f.gloss, f.morph, g.found
        FROM greek_words g JOIN forms f ON f.id = g.form
        """

    private static func hebrewWord(_ row: SQLiteDatabase.Row) -> OriginalWord {
        OriginalWord(
            verse: VerseID(rawValue: row.int(0)),
            position: row.int(1),
            text: row.text(2),
            transliteration: row.text(3),
            strongs: row.isNull(4) ? nil : row.text(4),
            gloss: row.text(5),
            morphology: row.text(6)
        )
    }

    private static func greekWord(_ row: SQLiteDatabase.Row, edition: GreekEdition) -> OriginalWord {
        OriginalWord(
            verse: VerseID(rawValue: row.int(0)),
            position: row.int(1),
            text: row.text(2),
            transliteration: row.text(3),
            strongs: row.isNull(4) ? nil : row.text(4),
            gloss: row.text(5),
            morphology: row.text(6),
            edition: edition,
            foundIn: GreekEditions(rawValue: row.int(7))
        )
    }

    /// The lexicon's columns, with the translation's gloss, definition and
    /// origin where it has them (and whether it did, last).
    private var entryColumns: String {
        let english = "SELECT lexicon.strongs, lemma, translit, gloss, definition, derivation, usage, language, 0 FROM lexicon"
        guard let language else { return english }
        return """
            SELECT lexicon.strongs, lemma, translit, COALESCE(tr.gloss, lexicon.gloss), COALESCE(tr.definition, lexicon.definition),
                COALESCE(tr.derivation, lexicon.derivation), usage, language, tr.strongs IS NOT NULL
            FROM lexicon LEFT JOIN lexicon_translations tr ON tr.lang = '\(language)' AND tr.strongs = lexicon.strongs
            """
    }

    /// The commentary's columns, with the translation's title and text
    /// where it has them (and whether it did, last).
    private var commentaryColumns: String {
        guard let commentaryLanguage else {
            return "SELECT c.id, c.source, c.start_verse, c.end_verse, c.title, c.text, 0 FROM commentary c"
        }
        return """
            SELECT c.id, c.source, c.start_verse, c.end_verse, COALESCE(tr.title, c.title), COALESCE(tr.text, c.text), tr.id IS NOT NULL
            FROM commentary c LEFT JOIN commentary_translations tr ON tr.lang = '\(commentaryLanguage)' AND tr.id = c.id
            """
    }

    private static func entry(_ row: SQLiteDatabase.Row) -> LexiconEntry {
        LexiconEntry(
            strongs: row.text(0),
            lemma: row.text(1),
            transliteration: row.text(2),
            gloss: row.text(3),
            definition: row.text(4),
            derivation: row.text(5),
            usage: row.text(6),
            language: OriginalLanguage(rawValue: row.text(7)) ?? (row.text(0).hasPrefix("G") ? .greek : .hebrew),
            isTranslated: row.int(8) != 0
        )
    }

    private static func passage(_ row: SQLiteDatabase.Row) -> CommentaryPassage {
        CommentaryPassage(
            id: row.int(0),
            source: row.text(1),
            start: VerseID(rawValue: row.int(2)),
            end: VerseID(rawValue: row.int(3)),
            title: row.isNull(4) ? nil : row.text(4),
            text: row.text(5),
            isTranslated: row.int(6) != 0
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
    private static func family(of base: String, column: String = "strongs") -> (sql: String, arguments: [SQLiteDatabase.Value]) {
        ("(\(column) = ? OR (\(column) BETWEEN ? AND ? AND length(\(column)) = ?))",
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

    /// Hebrew (and Aramaic) is written right to left.
    var isRightToLeft: Bool { self == .hebrew }
}

/// One Hebrew or Greek word of a verse, verbatim from the source text.
struct OriginalWord: Identifiable, Hashable, Sendable {
    let verse: VerseID
    /// Hebrew: 1… in the original-language order. Greek: TAGNT's number for
    /// the word in the verse (Nestle-Aland's order); an edition may put it
    /// elsewhere, and words come in the edition's own order.
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
    /// The Greek edition the word was read from; nil for Hebrew.
    var edition: GreekEdition? = nil
    /// The Greek editions that have this word here, in any spelling.
    var foundIn: GreekEditions = []

    var id: Int { verse.rawValue * 100 + position }
    var language: OriginalLanguage { verse.book >= 40 ? .greek : .hebrew }

    /// A Greek word the edition it's compared with (`GreekEdition.comparison`)
    /// doesn't have here: it leaves it out or has another word. The reader
    /// dots it. Never for Hebrew.
    var isNotInComparison: Bool {
        guard let edition else { return false }
        return !foundIn.contains(edition.comparison)
    }
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
    /// The gloss, definition and origin are a translation of the English
    /// lexicon (`WordStudyRepository.translatedNote`); usage stays English.
    var isTranslated = false

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
    /// The title and text are a translation of Henry's English
    /// (`WordStudyRepository.translatedCommentaryNote`).
    var isTranslated = false
    /// Versely's editorial notes (not Henry's words), by the paragraph
    /// (from 0) each is shown before, set apart from the commentary.
    var editorialNotes: [Int: String] = [:]
    /// In a translation, the Bible's own words it quotes (RV1909 or Bíblia
    /// Livre, verbatim), shown in italics and credited
    /// (`WordStudyRepository.quotationCredit`).
    var quotations: [String] = []
    /// The language of `quotations` ("es", "pt").
    var quotationLanguage: String?

    /// A paragraph with the quoted Bible words in italics.
    func attributed(_ paragraph: String) -> AttributedString {
        var text = AttributedString(paragraph)
        for quotation in quotations {
            var searchStart = text.startIndex
            while let range = text[searchStart...].range(of: quotation) {
                text[range].inlinePresentationIntent = .emphasized
                searchStart = range.upperBound
            }
        }
        return text
    }

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
