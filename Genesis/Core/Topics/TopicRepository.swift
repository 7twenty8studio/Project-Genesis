import Foundation

/// A topic from the topical index (Nave's Topical Bible).
struct TopicSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let referenceCount: Int
}

/// A heading within a topic and the passages under it. Entries nest one
/// level ("Instances of" › "Joseph forgives his brothers").
struct TopicEntry: Identifiable, Hashable, Sendable {
    let id: Int
    let parentID: Int?
    let label: String
    let passages: [TopicPassage]
}

/// A verse or verse range (a whole chapter when it spans every verse).
struct TopicPassage: Identifiable, Hashable, Sendable {
    let start: VerseID
    let end: VerseID
    var id: String { "\(start.rawValue)-\(end.rawValue)" }

    /// Whole chapters are stored as verse 1 to the last verse; they read
    /// better as "Numbers 17" (the builder marks them with `isWholeChapter`).
    let isWholeChapter: Bool

    var reference: PassageReference {
        if isWholeChapter { return PassageReference(book: .withNumber(start.book), chapter: start.chapter) }
        return PassageReference(book: .withNumber(start.book), chapter: start.chapter, verseStart: start.verse, verseEnd: end.verse == start.verse ? nil : end.verse)
    }
}

struct Topic: Hashable, Sendable {
    let summary: TopicSummary
    let entries: [TopicEntry]
    let seeAlso: [TopicSummary]
    /// The name or any heading is a translation of Nave's English.
    var isTranslated = false
}

/// Topics.sqlite: topic names, headings and verse ids only (never verse
/// text). CC BY 4.0, see Resources/Study/LICENSE.txt.
///
/// In Spanish and Portuguese, names and headings come from the
/// `translations` table (Tools/TopicData/add_topic_translations.py), each
/// falling back to the English where it has none. Search finds both.
final class TopicRepository: Sendable {
    private let database: SQLiteDatabase
    /// "es" or "pt" when the database has that language; nil for English.
    let language: String?

    /// Languages Topics.sqlite has names for. Only these reach the SQL below.
    static let translatedLanguages: Set<String> = ["es", "pt"]

    /// - Parameter language: the app's language code ("en", "es", "pt");
    ///   nil or one without translations shows the English.
    init(url: URL, language: String? = nil) throws {
        let database = try SQLiteDatabase(readOnly: url)
        let hasTranslations = try !database.query("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'translations'", map: { _ in true }).isEmpty
        self.database = database
        self.language = language.flatMap { Self.translatedLanguages.contains($0) && hasTranslations ? $0 : nil }
    }

    static func bundled(in bundle: Bundle = .main, language: String? = AppLanguage.code) -> TopicRepository? {
        bundle.url(forResource: "Topics", withExtension: "sqlite").flatMap { try? TopicRepository(url: $0, language: language) }
    }

    static let attribution = String(localized: "Topics from Nave's Topical Bible (public domain), via BibleData by Brady Stephenson, CC BY 4.0.")
    static let translatedNote = String(localized: "Topic names and headings translated from Nave's Topical Bible (1896). Not Scripture.")

    /// Topics whose name starts with the query first, then those containing
    /// it. In Spanish and Portuguese the translated name counts too, accents
    /// aside ("expiacion" finds Expiación).
    func search(_ query: String, limit: Int = 12) throws -> [TopicSummary] {
        // "Lord's" and "Lords" both match "lord's" in the index (apostrophes ignored).
        let words = Self.searchWords(query.lowercased())
        guard let first = words.first, first.count >= 3 || words.count > 1 else { return [] }
        let phrase = words.joined(separator: " ")
        let escaped = Self.escapeLike(phrase)
        guard language != nil else {
            return try database.query(
                """
                SELECT id, name, reference_count FROM topics
                WHERE reference_count > 0 AND (search_key LIKE ?1 ESCAPE '\\' OR search_key LIKE ?2 ESCAPE '\\')
                ORDER BY (search_key = ?3) DESC, (search_key LIKE ?1 ESCAPE '\\') DESC, reference_count DESC
                LIMIT ?4
                """,
                [.text(escaped + "%"), .text("% " + escaped + "%"), .text(phrase), .int(limit)],
                map: Self.summary
            )
        }
        let folded = Self.searchWords(Self.folded(query)).joined(separator: " ")
        let foldedEscaped = Self.escapeLike(folded)
        return try database.query(
            """
            SELECT t.id, \(name("tr", "t.name")), t.reference_count FROM topics t\(join("topic", as: "tr", id: "t.id"))
            WHERE t.reference_count > 0 AND (t.search_key LIKE ?1 ESCAPE '\\' OR t.search_key LIKE ?2 ESCAPE '\\'
                OR tr.folded LIKE ?5 ESCAPE '\\' OR tr.folded LIKE ?6 ESCAPE '\\')
            ORDER BY (t.search_key = ?3 OR tr.folded = ?7) DESC,
                (t.search_key LIKE ?1 ESCAPE '\\' OR tr.folded LIKE ?5 ESCAPE '\\') DESC, t.reference_count DESC
            LIMIT ?4
            """,
            [.text(escaped + "%"), .text("% " + escaped + "%"), .text(phrase), .int(limit),
             .text(foldedEscaped + "%"), .text("% " + foldedEscaped + "%"), .text(folded)],
            map: Self.summary
        )
    }

    func topic(id: Int) throws -> Topic? {
        guard let summary = try database.query(
            "SELECT t.id, \(name("tr", "t.name")), t.reference_count, \(isTranslated("tr")) FROM topics t\(join("topic", as: "tr", id: "t.id")) WHERE t.id = ?",
            [.int(id)],
            map: { (Self.summary($0), $0.bool(3)) }
        ).first else {
            return nil
        }
        var passages: [Int: [TopicPassage]] = [:]
        _ = try database.query(
            "SELECT r.entry_id, r.start_verse, r.end_verse, r.whole_chapter FROM refs r JOIN entries e ON e.id = r.entry_id WHERE e.topic_id = ? ORDER BY r.entry_id, r.sort",
            [.int(id)]
        ) { row in
            passages[row.int(0), default: []].append(TopicPassage(start: VerseID(rawValue: row.int(1)), end: VerseID(rawValue: row.int(2)), isWholeChapter: row.bool(3)))
        }
        var translatedHeadings = false
        let entries = try database.query(
            "SELECT e.id, e.parent_id, \(name("tr", "e.label")), \(isTranslated("tr")) FROM entries e\(join("entry", as: "tr", id: "e.id")) WHERE e.topic_id = ? ORDER BY e.sort",
            [.int(id)]
        ) { row in
            translatedHeadings = translatedHeadings || row.bool(3)
            return TopicEntry(id: row.int(0), parentID: row.optionalInt(1), label: row.text(2), passages: passages[row.int(0)] ?? [])
        }
        let seeAlso = try database.query(
            "SELECT t.id, \(name("tr", "t.name")), t.reference_count FROM see_also s JOIN topics t ON t.id = s.target_id\(join("topic", as: "tr", id: "t.id")) WHERE s.topic_id = ? ORDER BY 2",
            [.int(id)],
            map: Self.summary
        )
        return Topic(summary: summary.0, entries: entries, seeAlso: seeAlso, isTranslated: summary.1 || translatedHeadings)
    }

    // MARK: Translations

    /// " LEFT JOIN translations …" for a row of that kind, or "" in English.
    /// The language is one of `translatedLanguages`, never free text.
    private func join(_ kind: String, as alias: String, id: String) -> String {
        guard let language else { return "" }
        return " LEFT JOIN translations \(alias) ON \(alias).lang = '\(language)' AND \(alias).kind = '\(kind)' AND \(alias).key = \(id)"
    }

    /// The translation where there is one, else the English.
    private func name(_ alias: String, _ english: String) -> String {
        language == nil ? english : "COALESCE(NULLIF(\(alias).text, ''), \(english))"
    }

    private func isTranslated(_ alias: String) -> String {
        language == nil ? "0" : "COALESCE(\(alias).text, '') <> ''"
    }

    /// Lower case without accents, as add_topic_translations.py's `fold`.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    private static func searchWords(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "'", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func summary(_ row: SQLiteDatabase.Row) -> TopicSummary {
        TopicSummary(id: row.int(0), name: row.text(1), referenceCount: row.int(2))
    }

    private static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }
}
