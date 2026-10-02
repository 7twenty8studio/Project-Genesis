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

    init(translation: Translation, url: URL) throws {
        self.translation = translation
        database = try SQLiteDatabase(readOnly: url)
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
        let verses = try database.query(
            "SELECT \(Self.verseColumns) FROM verses WHERE id BETWEEN ? AND ? ORDER BY id",
            [.int(range.lowerBound), .int(range.upperBound)],
            map: Self.verse(from:)
        )
        let headings = try database.query(
            "SELECT before_verse, text FROM headings WHERE book = ? AND chapter = ? ORDER BY before_verse",
            [.int(id.book), .int(id.chapter)]
        ) { ChapterHeading(beforeVerse: $0.int(0), text: $0.text(1)) }
        return Chapter(id: id, verses: verses, headings: headings)
    }

    func verse(_ id: VerseID) throws -> Verse? {
        try database.query(
            "SELECT \(Self.verseColumns) FROM verses WHERE id = ?",
            [.int(id.rawValue)],
            map: Self.verse(from:)
        ).first
    }

    /// Verses from `start` through `end` inclusive, in canonical order.
    func verses(from start: VerseID, through end: VerseID) throws -> [Verse] {
        try database.query(
            "SELECT \(Self.verseColumns) FROM verses WHERE id BETWEEN ? AND ? ORDER BY id",
            [.int(start.rawValue), .int(end.rawValue)],
            map: Self.verse(from:)
        )
    }

    /// Looks up many individual verses at once, keyed by id.
    func verses(withIDs ids: some Collection<VerseID>) throws -> [VerseID: Verse] {
        guard !ids.isEmpty else { return [:] }
        let list = ids.map { String($0.rawValue) }.joined(separator: ",")
        let verses = try database.query(
            "SELECT \(Self.verseColumns) FROM verses WHERE id IN (\(list))",
            map: Self.verse(from:)
        )
        return Dictionary(uniqueKeysWithValues: verses.map { ($0.id, $0) })
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
        return try database.query(
            "SELECT count(*) FROM verses WHERE id BETWEEN ? AND ?",
            [.int(range.lowerBound), .int(range.upperBound)]
        ) { $0.int(0) }.first ?? 0
    }
}
