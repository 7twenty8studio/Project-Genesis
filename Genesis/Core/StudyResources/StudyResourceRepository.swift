import Foundation

/// A passage a note or article covers, which can run across chapters
/// (Tyndale's note on Genesis 1:1–2:3).
struct StudyRange: Hashable, Sendable {
    let start: VerseID
    let end: VerseID

    init(start: VerseID, end: VerseID) {
        self.start = start
        self.end = max(start, end)
    }

    /// Verse 0 starts a chapter introduction.
    var isChapterIntroduction: Bool { start.verse == 0 }

    func covers(_ verse: VerseID) -> Bool {
        (start...end).contains(verse)
    }

    /// "Genesis 1:1–2:3", "John 3:16", "Psalm 23" (an introduction), in a Bible's language.
    func description(in language: String) -> String {
        let book = BibleBook.withNumber(start.book)
        let name = book.name(in: language)
        if isChapterIntroduction {
            return "\(name) \(start.chapter)"
        }
        let first = book.chapterCount == 1 ? "\(name) \(start.verse)" : "\(name) \(start.chapter):\(start.verse)"
        if end == start { return first }
        if end.book != start.book {
            return "\(first)\u{2013}\(PassageReference(verse: end).description(in: language))"
        }
        if end.chapter != start.chapter {
            return "\(first)\u{2013}\(end.chapter):\(end.verse)"
        }
        return "\(first)\u{2013}\(end.verse)"
    }
}

/// A study note or a commentary's comment on a passage.
struct StudyNote: Identifiable, Hashable, Sendable {
    let id: Int
    let range: StudyRange
    let title: String?
    /// Light Markdown (`StudyMarkup`).
    let text: String
}

/// A dictionary entry, a person's profile or a theme article, listed by title.
struct StudyArticleSummary: Identifiable, Hashable, Sendable {
    /// The pack's id for it ("Aaron", "kt/god").
    let id: String
    let title: String
    let kind: String
}

struct StudyArticle: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let kind: String
    let text: String
}

/// A book introduction.
struct StudyIntroduction: Hashable, Sendable {
    let book: Int
    let title: String?
    let text: String
}

/// A Brown-Driver-Briggs or Liddell-Scott-Jones entry.
struct StudyLexiconEntry: Identifiable, Hashable, Sendable {
    enum Source: String, Sendable {
        case bdb, lsj

        var title: String {
            switch self {
            case .bdb: String(localized: "Brown-Driver-Briggs", comment: "Hebrew lexicon name")
            case .lsj: String(localized: "Liddell-Scott-Jones", comment: "Greek lexicon name")
            }
        }
    }

    let id: Int
    let strongs: String
    let source: Source
    let lemma: String
    let transliteration: String
    let gloss: String
    let definition: String
}

/// Reads one downloaded study pack (Tools/StudyResources/build_resources.py
/// describes the format). Packs hold verse ids in the KJV's numbering and
/// never verse text.
final class StudyResourceRepository: Sendable {
    private let database: SQLiteDatabase

    init(url: URL) throws {
        database = try SQLiteDatabase(readOnly: url)
    }

    /// The pack's id, from its info table.
    func packID() throws -> String? {
        try database.query("SELECT value FROM info WHERE key = 'id'") { $0.text(0) }.first
    }

    // MARK: Notes

    /// Notes and comments that take in the verse, chapter introductions
    /// first, then the widest passage first.
    func notes(for verse: VerseID) throws -> [StudyNote] {
        // Notes never start before their book.
        let bookStart = VerseID(book: verse.book, chapter: 0, verse: 0).rawValue
        return try database.query(
            "SELECT id, start_verse, end_verse, title, text FROM notes WHERE start_verse BETWEEN ? AND ? AND end_verse >= ? ORDER BY start_verse % 1000 != 0, start_verse, end_verse DESC, id",
            [.int(bookStart), .int(verse.rawValue), .int(verse.rawValue)], map: Self.note
        )
    }

    /// The book's introduction, if the pack has one.
    func introduction(toBook book: Int) throws -> StudyIntroduction? {
        try database.query("SELECT book, title, text FROM introductions WHERE book = ? LIMIT 1", [.int(book)]) { row in
            StudyIntroduction(book: row.int(0), title: row.isNull(1) ? nil : row.text(1), text: row.text(2))
        }.first
    }

    // MARK: Articles

    /// Articles linked to the verse (people, themes, key terms), by title.
    func articles(for verse: VerseID, limit: Int = 30) throws -> [StudyArticleSummary] {
        let bookStart = VerseID(book: verse.book, chapter: 0, verse: 0).rawValue
        return try database.query(
            """
            SELECT DISTINCT a.id, a.title, a.kind, a.sort_key FROM article_verses v JOIN articles a ON a.id = v.article
            WHERE v.start_verse BETWEEN ? AND ? AND v.end_verse >= ? ORDER BY a.sort_key LIMIT ?
            """,
            [.int(bookStart), .int(verse.rawValue), .int(verse.rawValue), .int(limit)], map: Self.summary
        )
    }

    func article(id: String) throws -> StudyArticle? {
        try database.query("SELECT id, title, kind, text FROM articles WHERE id = ? LIMIT 1", [.text(id)]) { row in
            StudyArticle(id: row.text(0), title: row.text(1), kind: row.text(2), text: row.text(3))
        }.first
    }

    func articleCount() throws -> Int {
        try database.query("SELECT COUNT(*) FROM articles") { $0.int(0) }.first ?? 0
    }

    /// Articles whose titles match, those starting with the words first;
    /// accents and case don't matter. An empty query lists from the start.
    func searchArticles(_ query: String, limit: Int = 100) throws -> [StudyArticleSummary] {
        let folded = StudyMarkup.folded(query)
        let columns = "SELECT id, title, kind, sort_key FROM articles"
        guard !folded.isEmpty else {
            return try database.query("\(columns) ORDER BY sort_key LIMIT ?", [.int(limit)], map: Self.summary)
        }
        let pattern = StudyMarkup.likeEscaped(folded)
        let starting = try database.query(
            "\(columns) WHERE sort_key LIKE ? ESCAPE '\\' ORDER BY sort_key LIMIT ?",
            [.text(pattern + "%"), .int(limit)], map: Self.summary
        )
        guard starting.count < limit else { return starting }
        let containing = try database.query(
            "\(columns) WHERE sort_key LIKE ? ESCAPE '\\' AND sort_key NOT LIKE ? ESCAPE '\\' ORDER BY sort_key LIMIT ?",
            [.text("%" + pattern + "%"), .text(pattern + "%"), .int(limit - starting.count)], map: Self.summary
        )
        return starting + containing
    }

    // MARK: Lexicon

    /// Brown-Driver-Briggs or Liddell-Scott-Jones entries for a Strong's
    /// number ("H430", "H0430G"), by its plain number.
    func lexicon(strongs: String) throws -> [StudyLexiconEntry] {
        guard let tag = StrongsNumber.normalized(strongs) else { return [] }
        return try database.query(
            "SELECT rowid, strongs, source, lemma, translit, gloss, definition FROM lexicon WHERE strongs = ? ORDER BY rowid",
            [.text(StrongsNumber.base(of: tag))]
        ) { row in
            StudyLexiconEntry(
                id: row.int(0),
                strongs: row.text(1),
                source: StudyLexiconEntry.Source(rawValue: row.text(2)) ?? .bdb,
                lemma: row.text(3),
                transliteration: row.text(4),
                gloss: row.text(5),
                definition: row.text(6)
            )
        }
    }

    // MARK: Rows

    private static func note(_ row: SQLiteDatabase.Row) -> StudyNote {
        StudyNote(
            id: row.int(0),
            range: StudyRange(start: VerseID(rawValue: row.int(1)), end: VerseID(rawValue: row.int(2))),
            title: row.isNull(3) ? nil : row.text(3),
            text: row.text(4)
        )
    }

    private static func summary(_ row: SQLiteDatabase.Row) -> StudyArticleSummary {
        StudyArticleSummary(id: row.text(0), title: row.text(1), kind: row.text(2))
    }
}
