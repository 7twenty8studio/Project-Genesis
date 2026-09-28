import Foundation

/// Chooses the verse of the day from a curated list, the same for everyone
/// on a given date and available offline.
enum DailyVerse {
    static func verse(for date: Date = .now, calendar: Calendar = .current) -> VerseID {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return curated[day % curated.count]
    }

    /// Well-loved verses that stand on their own. Book, chapter, verse.
    static let curated: [VerseID] = [
        (43, 3, 16), (19, 23, 1), (20, 3, 5), (23, 40, 31), (45, 8, 28), (50, 4, 13),
        (24, 29, 11), (6, 1, 9), (19, 46, 1), (40, 11, 28), (50, 4, 6), (45, 12, 2),
        (58, 11, 1), (46, 13, 4), (48, 5, 22), (19, 119, 105), (25, 3, 22), (23, 41, 10),
        (40, 6, 33), (43, 14, 27), (45, 15, 13), (49, 2, 8), (60, 5, 7), (19, 34, 18),
        (20, 16, 3), (47, 5, 17), (51, 3, 23), (59, 1, 5), (62, 4, 19), (19, 37, 4),
        (33, 6, 8), (43, 16, 33), (45, 5, 8), (19, 27, 1), (23, 26, 3), (40, 5, 9),
        (50, 4, 7), (58, 12, 1), (19, 90, 12), (21, 3, 1), (34, 1, 7), (36, 3, 17),
        (43, 15, 5), (44, 1, 8), (46, 16, 14), (47, 12, 9), (54, 4, 12), (55, 1, 7),
        (19, 139, 14), (40, 28, 20), (42, 1, 37), (43, 8, 12), (45, 10, 9), (62, 1, 9),
        (19, 16, 11), (20, 18, 10), (23, 43, 2), (5, 31, 6), (19, 121, 1), (66, 21, 4),
    ].map { VerseID(book: $0.0, chapter: $0.1, verse: $0.2) }
}
