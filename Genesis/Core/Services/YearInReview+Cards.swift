import Foundation

/// Data for the shareable Year in Review cards: a dot for every day of the
/// year and how much of each book was read.
extension YearInReview {
    /// The year as calendar weeks (columns of seven, starting on the
    /// calendar's first weekday). Each cell is true when that day had
    /// reading, false when not, and nil before 1 January or after 31 December.
    static func readingWeeks(year: Int, readingDays: Set<String>, calendar: Calendar = .current) -> [[Bool?]] {
        guard let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let next = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)),
              let dayCount = calendar.dateComponents([.day], from: first, to: next).day else { return [] }
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var cells: [Bool?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            cells.append(readingDays.contains(Timestamp.dayString(from: day, calendar: calendar)))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    /// For each of the 66 books in order, the share of its chapters read (0...1).
    static func bookShares(chapters: Set<Int>) -> [Double] {
        let byBook = Dictionary(grouping: chapters, by: { $0 / 1_000 }).mapValues(\.count)
        return BibleBook.all.map { book in
            min(Double(byBook[book.id] ?? 0) / Double(max(book.chapterCount, 1)), 1)
        }
    }
}
