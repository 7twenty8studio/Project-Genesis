import Foundation

/// A link from one verse to a related verse or passage.
struct CrossReference: Hashable, Sendable, Identifiable {
    let target: VerseID
    let targetEnd: VerseID
    /// Community votes from OpenBible.info; higher means more widely agreed.
    let votes: Int

    var id: Int { target.rawValue &* 31 &+ targetEnd.rawValue }

    var reference: PassageReference {
        if targetEnd.chapterID == target.chapterID, targetEnd != target {
            return PassageReference(book: .withNumber(target.book), chapter: target.chapter, verseStart: target.verse, verseEnd: targetEnd.verse)
        }
        return PassageReference(verse: target)
    }
}

/// Cross references from OpenBible.info (CC-BY), based on the Treasury of
/// Scripture Knowledge. Attribution is shown wherever they appear.
final class CrossReferenceRepository: Sendable {
    static let attribution = "Cross references from OpenBible.info, CC-BY."

    private let database: SQLiteDatabase

    init(url: URL) throws {
        database = try SQLiteDatabase(readOnly: url)
    }

    func references(from verse: VerseID, limit: Int = 50) throws -> [CrossReference] {
        try database.query(
            "SELECT to_start, to_end, votes FROM cross_references WHERE from_id = ? ORDER BY votes DESC LIMIT ?",
            [.int(verse.rawValue), .int(limit)]
        ) {
            CrossReference(target: VerseID(rawValue: $0.int(0)), targetEnd: VerseID(rawValue: $0.int(1)), votes: $0.int(2))
        }
    }

    /// Verse ids in a chapter that have at least one cross reference.
    func versesWithReferences(in chapter: ChapterID) throws -> Set<VerseID> {
        let range = chapter.verseRange
        let ids = try database.query(
            "SELECT DISTINCT from_id FROM cross_references WHERE from_id BETWEEN ? AND ?",
            [.int(range.lowerBound), .int(range.upperBound)]
        ) { VerseID(rawValue: $0.int(0)) }
        return Set(ids)
    }
}
