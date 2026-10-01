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
}

/// Topics.sqlite: topic names, headings and verse ids only (never verse
/// text). CC BY 4.0, see Resources/Study/LICENSE.txt.
final class TopicRepository: Sendable {
    private let database: SQLiteDatabase

    init(url: URL) throws {
        database = try SQLiteDatabase(readOnly: url)
    }

    static func bundled(in bundle: Bundle = .main) -> TopicRepository? {
        bundle.url(forResource: "Topics", withExtension: "sqlite").flatMap { try? TopicRepository(url: $0) }
    }

    static let attribution = "Topics from Nave's Topical Bible (public domain), via BibleData by Brady Stephenson, CC BY 4.0."

    /// Topics whose name starts with the query first, then those containing it.
    func search(_ query: String, limit: Int = 12) throws -> [TopicSummary] {
        // "Lord's" and "Lords" both match "lord's" in the index (apostrophes ignored).
        let words = query.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "'", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        guard let first = words.first, first.count >= 3 || words.count > 1 else { return [] }
        let phrase = words.joined(separator: " ")
        let escaped = Self.escapeLike(phrase)
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

    func topic(id: Int) throws -> Topic? {
        guard let summary = try database.query("SELECT id, name, reference_count FROM topics WHERE id = ?", [.int(id)], map: Self.summary).first else {
            return nil
        }
        var passages: [Int: [TopicPassage]] = [:]
        _ = try database.query(
            "SELECT r.entry_id, r.start_verse, r.end_verse, r.whole_chapter FROM refs r JOIN entries e ON e.id = r.entry_id WHERE e.topic_id = ? ORDER BY r.entry_id, r.sort",
            [.int(id)]
        ) { row in
            passages[row.int(0), default: []].append(TopicPassage(start: VerseID(rawValue: row.int(1)), end: VerseID(rawValue: row.int(2)), isWholeChapter: row.bool(3)))
        }
        let entries = try database.query("SELECT id, parent_id, label FROM entries WHERE topic_id = ? ORDER BY sort", [.int(id)]) { row in
            TopicEntry(id: row.int(0), parentID: row.optionalInt(1), label: row.text(2), passages: passages[row.int(0)] ?? [])
        }
        let seeAlso = try database.query(
            "SELECT t.id, t.name, t.reference_count FROM see_also s JOIN topics t ON t.id = s.target_id WHERE s.topic_id = ? ORDER BY t.name",
            [.int(id)],
            map: Self.summary
        )
        return Topic(summary: summary, entries: entries, seeAlso: seeAlso)
    }

    private static func summary(_ row: SQLiteDatabase.Row) -> TopicSummary {
        TopicSummary(id: row.int(0), name: row.text(1), referenceCount: row.int(2))
    }

    private static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }
}
