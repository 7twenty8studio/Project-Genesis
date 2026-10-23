import Foundation

/// Where a search looks.
enum SearchScope: Hashable, Sendable {
    case wholeBible
    case testament(Testament)
    case book(Int)

    /// Inclusive verse-id bounds for the scope.
    var idRange: ClosedRange<Int> {
        switch self {
        case .wholeBible:
            return VerseID(book: 1, chapter: 0, verse: 0).rawValue...VerseID(book: 66, chapter: 999, verse: 999).rawValue
        case let .testament(testament):
            let books = testament == .old ? 1...39 : 40...66
            return VerseID(book: books.lowerBound, chapter: 0, verse: 0).rawValue...VerseID(book: books.upperBound, chapter: 999, verse: 999).rawValue
        case let .book(book):
            return VerseID(book: book, chapter: 0, verse: 0).rawValue...VerseID(book: book, chapter: 999, verse: 999).rawValue
        }
    }
}

enum SearchOrder: String, Hashable, Sendable, CaseIterable {
    case relevance
    case canonical

    var title: String {
        switch self {
        case .relevance: String(localized: "Best Match", comment: "Search result order")
        case .canonical: String(localized: "Bible Order", comment: "Search result order")
        }
    }
}

/// Read access to one translation's offline database.
final class BibleRepository: Sendable {
    let translation: Translation
    private let database: SQLiteDatabase

    /// True when the translation joins some verses into one ("16–17"):
    /// a `verse_spans` table, written by Tools/BibleData/import_dbl.py.
    private let hasSpans: Bool
    /// True when the translation has footnotes (a `footnotes` table, which
    /// YouVersion Platform Bibles built on the device have).
    private let hasFootnotes: Bool

    /// Opens a Bible file; a sealed one (`BibleProtection`, licensed text)
    /// is opened into memory with this device's key.
    init(translation: Translation, url: URL) throws {
        self.translation = translation
        let database = BibleProtection.isSealed(fileAt: url)
            ? try SQLiteDatabase(contents: try BibleProtection.read(url))
            : try SQLiteDatabase(readOnly: url)
        let tables = Set(try database.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('verse_spans', 'footnotes')"
        ) { $0.text(0) })
        self.database = database
        hasSpans = tables.contains("verse_spans")
        hasFootnotes = tables.contains("footnotes")
    }

    /// Joined verses that start between the two ids: first id → last verse number.
    private func spans(from start: Int, through end: Int) -> [Int: Int] {
        guard hasSpans else { return [:] }
        let rows = (try? database.query(
            "SELECT id, last FROM verse_spans WHERE id BETWEEN ? AND ?",
            [.int(start), .int(end)]
        ) { ($0.int(0), $0.int(1) % 1_000) }) ?? []
        return Dictionary(rows, uniquingKeysWith: { first, _ in first })
    }

    private func applyingSpans(_ verses: [Verse]) -> [Verse] {
        let ids = verses.map(\.id.rawValue)
        guard hasSpans, let lowest = ids.min(), let highest = ids.max() else { return verses }
        let spans = spans(from: lowest, through: highest)
        guard !spans.isEmpty else { return verses }
        return verses.map { verse in
            var verse = verse
            verse.lastVerse = spans[verse.id.rawValue]
            return verse
        }
    }

    private static let verseColumns = "id, text, paragraph, poetry"

    private static func verse(from row: SQLiteDatabase.Row) -> Verse {
        Verse(
            id: VerseID(rawValue: row.int(0)),
            text: row.text(1),
            startsParagraph: row.bool(2),
            isPoetry: row.bool(3)
        )
    }

    func chapter(_ id: ChapterID) throws -> Chapter {
        let range = id.verseRange
        let verses = applyingSpans(try database.query(
            "SELECT \(Self.verseColumns) FROM verses WHERE id BETWEEN ? AND ? ORDER BY id",
            [.int(range.lowerBound), .int(range.upperBound)],
            map: Self.verse(from:)
        ))
        let headings = try database.query(
            "SELECT before_verse, text FROM headings WHERE book = ? AND chapter = ? ORDER BY before_verse",
            [.int(id.book), .int(id.chapter)]
        ) { ChapterHeading(beforeVerse: $0.int(0), text: $0.text(1)) }
        return Chapter(
            id: id,
            verses: verses,
            headings: headings,
            copyrightNotice: translation.isLicensed ? translation.license : nil,
            publisherURL: translation.isLicensed ? translation.publisherURL : nil,
            footnotes: try footnotes(in: id)
        )
    }

    /// A chapter's footnotes, by verse then position.
    func footnotes(in id: ChapterID) throws -> [Footnote] {
        guard hasFootnotes else { return [] }
        let range = id.verseRange
        return try database.query(
            "SELECT verse_id, position, text FROM footnotes WHERE verse_id BETWEEN ? AND ? ORDER BY verse_id, position, rowid",
            [.int(range.lowerBound), .int(range.upperBound)]
        ) { Footnote(verse: VerseID(rawValue: $0.int(0)), offset: $0.int(1), text: $0.text(2)) }
    }

    /// A verse, or for a verse the translation joins with the ones before
    /// it ("16–17" asked for 17) the joined verse that holds its words.
    func verse(_ id: VerseID) throws -> Verse? {
        if let verse = applyingSpans(try database.query(
            "SELECT \(Self.verseColumns) FROM verses WHERE id = ?",
            [.int(id.rawValue)],
            map: Self.verse(from:)
        )).first {
            return verse
        }
        guard hasSpans, let holder = spanHolding(id) else { return nil }
        return try verse(holder)
    }

    /// The first verse of a joined group that covers `id`, if any.
    private func spanHolding(_ id: VerseID) -> VerseID? {
        let chapterStart = id.rawValue - id.rawValue % 1_000
        let first = try? database.query(
            "SELECT id FROM verse_spans WHERE id BETWEEN ? AND ? AND last >= ? ORDER BY id DESC LIMIT 1",
            [.int(chapterStart), .int(id.rawValue - 1), .int(id.rawValue)]
        ) { $0.int(0) }.first
        return first.map { VerseID(rawValue: $0) }
    }

    /// Verses from `start` through `end` inclusive, in canonical order. A
    /// range starting inside joined verses ("17" of "16–17") includes them.
    func verses(from start: VerseID, through end: VerseID) throws -> [Verse] {
        let from = hasSpans ? (spanHolding(start) ?? start) : start
        return applyingSpans(try database.query(
            "SELECT \(Self.verseColumns) FROM verses WHERE id BETWEEN ? AND ? ORDER BY id",
            [.int(from.rawValue), .int(end.rawValue)],
            map: Self.verse(from:)
        ))
    }

    /// Looks up many individual verses at once, keyed by id.
    func verses(withIDs ids: some Collection<VerseID>) throws -> [VerseID: Verse] {
        guard !ids.isEmpty else { return [:] }
        let list = ids.map { String($0.rawValue) }.joined(separator: ",")
        let verses = applyingSpans(try database.query(
            "SELECT \(Self.verseColumns) FROM verses WHERE id IN (\(list))",
            map: Self.verse(from:)
        ))
        var found = Dictionary(uniqueKeysWithValues: verses.map { ($0.id, $0) })
        // A verse inside joined verses ("17" of "16–17") is found as the
        // joined verse, under the id that was asked for.
        if hasSpans {
            for id in ids where found[id] == nil {
                if let holder = spanHolding(id), let joined = try verse(holder) { found[id] = joined }
            }
        }
        return found
    }

    /// Full-text search. `matchExpression` is an FTS5 query built by `FullTextQuery`.
    func search(
        matchExpression: String,
        scope: SearchScope,
        order: SearchOrder,
        limit: Int
    ) throws -> [Verse] {
        let range = scope.idRange
        let orderClause = order == .relevance ? "f.rank" : "f.rowid"
        return try database.query(
            """
            SELECT v.id, v.text, v.paragraph, v.poetry
            FROM verses_fts f JOIN verses v ON v.id = f.rowid
            WHERE verses_fts MATCH ? AND f.rowid BETWEEN ? AND ?
            ORDER BY \(orderClause)
            LIMIT ?
            """,
            [.text(matchExpression), .int(range.lowerBound), .int(range.upperBound), .int(limit)],
            map: Self.verse(from:)
        )
    }

    func countMatches(matchExpression: String, scope: SearchScope) throws -> Int {
        let range = scope.idRange
        return try database.query(
            "SELECT count(*) FROM verses_fts WHERE verses_fts MATCH ? AND rowid BETWEEN ? AND ?",
            [.text(matchExpression), .int(range.lowerBound), .int(range.upperBound)]
        ) { $0.int(0) }.first ?? 0
    }

    /// Verses in the whole translation (to check a download is complete).
    func verseCount() throws -> Int {
        try database.query("SELECT COUNT(*) FROM verses") { $0.int(0) }.first ?? 0
    }

    /// Number of verses in a chapter, used for navigation and progress.
    func verseCount(in chapter: ChapterID) throws -> Int {
        let range = chapter.verseRange
        let rows = try database.query(
            "SELECT count(*) FROM verses WHERE id BETWEEN ? AND ?",
            [.int(range.lowerBound), .int(range.upperBound)]
        ) { $0.int(0) }.first ?? 0
        guard hasSpans else { return rows }
        // Joined verses count as all the verses they hold.
        let joined = try database.query(
            "SELECT coalesce(sum(last - id), 0) FROM verse_spans WHERE id BETWEEN ? AND ?",
            [.int(range.lowerBound), .int(range.upperBound)]
        ) { $0.int(0) }.first ?? 0
        return rows + joined
    }
}
