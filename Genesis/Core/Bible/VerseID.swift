import Foundation

/// A translation-independent verse address.
///
/// Encoded as `book * 1_000_000 + chapter * 1_000 + verse`, matching the `id`
/// column of every bundled Bible database, so ids sort in canonical order and a
/// chapter is a contiguous id range.
struct VerseID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(book: Int, chapter: Int, verse: Int) {
        rawValue = book * 1_000_000 + chapter * 1_000 + verse
    }

    var book: Int { rawValue / 1_000_000 }
    var chapter: Int { (rawValue / 1_000) % 1_000 }
    var verse: Int { rawValue % 1_000 }

    var chapterID: ChapterID { ChapterID(book: book, chapter: chapter) }

    static func < (lhs: VerseID, rhs: VerseID) -> Bool { lhs.rawValue < rhs.rawValue }

    var description: String { "\(book).\(chapter).\(verse)" }

    // Encode as a plain integer so stored data stays compact and stable.
    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A book and chapter, independent of translation.
struct ChapterID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let book: Int
    let chapter: Int

    var firstVerse: VerseID { VerseID(book: book, chapter: chapter, verse: 1) }

    /// Inclusive id range covering every possible verse in the chapter.
    var verseRange: ClosedRange<Int> {
        VerseID(book: book, chapter: chapter, verse: 0).rawValue...VerseID(book: book, chapter: chapter, verse: 999).rawValue
    }

    var bibleBook: BibleBook { BibleBook.withNumber(book) }

    /// The following chapter in canonical order, crossing book boundaries.
    var next: ChapterID? {
        if chapter < bibleBook.chapterCount { return ChapterID(book: book, chapter: chapter + 1) }
        guard book < BibleBook.all.count else { return nil }
        return ChapterID(book: book + 1, chapter: 1)
    }

    /// The preceding chapter in canonical order, crossing book boundaries.
    var previous: ChapterID? {
        if chapter > 1 { return ChapterID(book: book, chapter: chapter - 1) }
        guard book > 1 else { return nil }
        let previousBook = BibleBook.withNumber(book - 1)
        return ChapterID(book: previousBook.id, chapter: previousBook.chapterCount)
    }

    static func < (lhs: ChapterID, rhs: ChapterID) -> Bool {
        (lhs.book, lhs.chapter) < (rhs.book, rhs.chapter)
    }

    var description: String { "\(bibleBook.name) \(chapter)" }

    static let genesis1 = ChapterID(book: 1, chapter: 1)
    static let john1 = ChapterID(book: 43, chapter: 1)
}

extension ChapterID {
    /// "John 3" or "Juan 3", in a Bible's language.
    func description(in language: String) -> String {
        "\(bibleBook.name(in: language)) \(chapter)"
    }
}
