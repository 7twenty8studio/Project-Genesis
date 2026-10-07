import Foundation

/// A whole verse or a short passage (at most three verses, one chapter) for
/// the verse widget. Ids only: the text always comes from a Bible database.
struct CategoryPassage: Hashable, Sendable {
    let start: VerseID
    let end: VerseID

    init(book: Int, chapter: Int, verse: Int, through last: Int) {
        start = VerseID(book: book, chapter: chapter, verse: verse)
        end = VerseID(book: book, chapter: chapter, verse: last)
    }

    var verseIDs: [VerseID] {
        (start.verse...end.verse).map { VerseID(book: start.book, chapter: start.chapter, verse: $0) }
    }

    var reference: PassageReference {
        PassageReference(book: .withNumber(start.book), chapter: start.chapter, verseStart: start.verse, verseEnd: end.verse == start.verse ? nil : end.verse)
    }
}

/// The verse widget's themes (Premium) and, all together, the pool its free
/// "Random Verse" draws from. Well-known verses that stand on their own:
/// whole sentences (in the KJV) that read rightly out of context, with no
/// psalm titles. Book, chapter, first verse, last verse.
///
/// Every reference is checked against the bundled KJV, WEB and ASV by
/// VerseWidgetTests and Tools/WidgetData/check_verse_categories.py.
enum VerseCategories {
    static func passages(for category: VerseCategory) -> [CategoryPassage] {
        switch category {
        case .hope: hope
        case .peace: peace
        case .faith: faith
        case .strength: strength
        case .comfort: comfort
        case .love: love
        case .gratitude: gratitude
        case .guidance: guidance
        }
    }

    /// Every category's passages, each once, in category order.
    static let encouraging: [CategoryPassage] = {
        var seen = Set<CategoryPassage>()
        return VerseCategory.allCases.flatMap { VerseCategories.passages(for: $0) }.filter { seen.insert($0).inserted }
    }()

    private static func list(_ items: [(Int, Int, Int, Int)]) -> [CategoryPassage] {
        items.map { CategoryPassage(book: $0.0, chapter: $0.1, verse: $0.2, through: $0.3) }
    }

    static let hope = list([
        (45, 15, 13, 13), (24, 29, 11, 11), (25, 3, 22, 23), (25, 3, 24, 24), (25, 3, 25, 25), (19, 42, 11, 11),
        (19, 31, 24, 24), (19, 39, 7, 7), (19, 62, 5, 5), (19, 71, 14, 14), (19, 130, 5, 5), (20, 23, 18, 18),
        (45, 5, 5, 5), (45, 8, 28, 28), (66, 21, 4, 4), (33, 7, 7, 7), (19, 147, 11, 11), (45, 15, 4, 4),
        (19, 33, 22, 22), (23, 43, 19, 19), (19, 16, 9, 9),
    ])

    static let peace = list([
        (43, 14, 27, 27), (50, 4, 6, 7), (23, 26, 3, 3), (4, 6, 24, 26), (19, 4, 8, 8), (43, 16, 33, 33),
        (51, 3, 15, 15), (53, 3, 16, 16), (19, 29, 11, 11), (23, 32, 17, 17), (19, 119, 165, 165), (19, 3, 5, 5),
        (23, 54, 10, 10), (19, 46, 10, 10), (2, 14, 14, 14), (19, 37, 37, 37), (23, 9, 6, 6), (19, 23, 2, 3),
        (42, 2, 14, 14), (23, 26, 12, 12), (19, 116, 7, 7),
    ])

    static let faith = list([
        (58, 11, 1, 1), (58, 11, 6, 6), (45, 10, 17, 17), (49, 2, 8, 9), (41, 9, 23, 23), (48, 2, 20, 20),
        (62, 5, 4, 4), (40, 19, 26, 26), (58, 12, 2, 2), (43, 11, 25, 26), (43, 20, 29, 29), (19, 56, 3, 3),
        (19, 37, 5, 5), (19, 9, 10, 10), (24, 17, 7, 7), (48, 3, 26, 26), (42, 1, 37, 37), (46, 16, 13, 13),
        (49, 6, 16, 16), (41, 11, 24, 24), (19, 20, 7, 7),
    ])

    static let strength = list([
        (23, 40, 29, 29), (50, 4, 13, 13), (23, 41, 10, 10), (6, 1, 9, 9), (47, 12, 9, 9), (19, 28, 7, 7),
        (19, 73, 26, 26), (5, 31, 6, 6), (19, 18, 32, 32), (23, 12, 2, 2), (49, 6, 10, 10), (55, 1, 7, 7),
        (19, 27, 14, 14), (13, 16, 11, 11), (19, 118, 14, 14), (19, 138, 3, 3), (10, 22, 33, 33), (19, 62, 7, 7),
        (19, 121, 2, 2), (23, 40, 31, 31),
    ])

    static let comfort = list([
        (40, 11, 28, 28), (60, 5, 7, 7), (19, 34, 18, 18), (40, 5, 4, 4), (47, 1, 3, 4), (19, 147, 3, 3),
        (19, 23, 4, 4), (43, 14, 1, 1), (23, 41, 13, 13), (19, 55, 22, 22), (23, 43, 2, 2), (19, 94, 19, 19),
        (40, 6, 34, 34), (23, 66, 13, 13), (19, 30, 5, 5), (19, 34, 4, 4), (5, 31, 8, 8), (19, 121, 7, 8),
        (45, 8, 38, 39), (19, 9, 9, 9), (34, 1, 7, 7), (23, 40, 11, 11), (40, 6, 26, 26), (19, 56, 8, 8),
        (43, 14, 18, 18),
    ])

    static let love = list([
        (43, 3, 16, 16), (62, 4, 19, 19), (62, 4, 7, 8), (62, 4, 16, 16), (45, 5, 8, 8), (46, 13, 13, 13),
        (24, 31, 3, 3), (36, 3, 17, 17), (43, 15, 13, 13), (43, 13, 34, 35), (62, 3, 1, 1), (60, 4, 8, 8),
        (51, 3, 14, 14), (45, 13, 10, 10), (19, 103, 11, 11), (62, 4, 18, 18), (48, 5, 22, 23), (41, 12, 30, 31),
        (43, 15, 9, 9), (46, 16, 14, 14), (19, 63, 3, 3), (19, 86, 15, 15),
    ])

    static let gratitude = list([
        (52, 5, 16, 18), (19, 107, 1, 1), (19, 118, 24, 24), (19, 100, 4, 5), (51, 3, 17, 17), (19, 136, 1, 1),
        (51, 2, 6, 7), (19, 95, 2, 2), (19, 106, 1, 1), (13, 16, 34, 34), (59, 1, 17, 17), (47, 9, 15, 15),
        (19, 150, 6, 6), (46, 15, 57, 57), (19, 139, 14, 14), (19, 126, 3, 3), (19, 30, 12, 12), (19, 105, 1, 1),
        (19, 147, 1, 1), (19, 68, 19, 19), (19, 145, 9, 9), (19, 23, 6, 6),
    ])

    static let guidance = list([
        (19, 32, 8, 8), (23, 30, 21, 21), (59, 1, 5, 5), (20, 16, 9, 9), (19, 25, 4, 5), (19, 37, 23, 23),
        (24, 33, 3, 3), (23, 58, 11, 11), (19, 143, 8, 8), (20, 16, 3, 3), (19, 16, 11, 11), (43, 16, 13, 13),
        (19, 48, 14, 14), (19, 73, 24, 24), (23, 42, 16, 16), (20, 2, 6, 6), (23, 48, 17, 17), (19, 25, 9, 9),
        (45, 12, 2, 2), (43, 8, 12, 12), (19, 31, 3, 3), (33, 6, 8, 8), (19, 86, 11, 11), (20, 3, 5, 6),
    ])
}
