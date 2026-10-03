import Foundation

/// A year of reading, worked out from what's on the device: days read,
/// streaks, time, chapters and books, highlights, notes and prayers.
struct YearInReview: Equatable, Sendable {
    struct HighlightRecord: Sendable {
        let date: Date
        let verse: VerseID
        let color: HighlightColor
    }

    struct PrayerRecord: Sendable {
        let created: Date
        let answered: Date?
    }

    let year: Int
    let daysRead: Int
    let longestStreak: Int
    let minutesRead: Int
    /// The day with the most reading, and how many minutes.
    let longestDay: Date?
    let longestDayMinutes: Int
    let chaptersRead: Int
    let booksOpened: Int
    /// Books read from beginning to end this year.
    let booksFinished: Int
    /// The book with the most chapters read this year.
    let topBook: BibleBook?
    let highlights: Int
    let mostHighlightedBook: BibleBook?
    let favoriteColor: HighlightColor?
    let notes: Int
    let prayersAdded: Int
    let prayersAnswered: Int

    /// True when there's something to show.
    var hasActivity: Bool { daysRead > 0 || highlights > 0 || notes > 0 || prayersAdded > 0 }

    static func make(
        year: Int,
        readingDays: Set<String>,
        readingSeconds: [String: Int],
        chapters: Set<Int>,
        highlights: [HighlightRecord],
        notes: [Date],
        prayers: [PrayerRecord],
        calendar: Calendar = .current
    ) -> YearInReview {
        let prefix = String(format: "%04d-", year)
        let days = readingDays.filter { $0.hasPrefix(prefix) }
        let dates = days.compactMap { Timestamp.day(from: $0, calendar: calendar) }.sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for day in dates {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }

        let seconds = readingSeconds.filter { $0.key.hasPrefix(prefix) }
        let busiest = seconds.max { $0.value < $1.value }

        let byBook = Dictionary(grouping: chapters, by: { $0 / 1_000 }).mapValues(\.count)
        let finished = byBook.filter { book, count in count >= BibleBook.withNumber(book).chapterCount }.count
        let topBook = byBook.max { lhs, rhs in lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value }?.key

        let inYear: (Date) -> Bool = { calendar.component(.year, from: $0) == year }
        let yearHighlights = highlights.filter { inYear($0.date) }
        let highlightBooks = Dictionary(grouping: yearHighlights, by: { $0.verse.book }).mapValues(\.count)
        let topHighlighted = highlightBooks.max { lhs, rhs in lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value }?.key
        let colors = Dictionary(grouping: yearHighlights, by: \.color).mapValues(\.count)
        let favorite = colors.max { lhs, rhs in lhs.value == rhs.value ? lhs.key.rawValue > rhs.key.rawValue : lhs.value < rhs.value }?.key

        return YearInReview(
            year: year,
            daysRead: days.count,
            longestStreak: longest,
            minutesRead: seconds.values.reduce(0, +) / 60,
            longestDay: busiest.flatMap { Timestamp.day(from: $0.key, calendar: calendar) },
            longestDayMinutes: (busiest?.value ?? 0) / 60,
            chaptersRead: chapters.count,
            booksOpened: byBook.count,
            booksFinished: finished,
            topBook: topBook.map(BibleBook.withNumber),
            highlights: yearHighlights.count,
            mostHighlightedBook: topHighlighted.map(BibleBook.withNumber),
            favoriteColor: favorite,
            notes: notes.filter(inYear).count,
            prayersAdded: prayers.filter { inYear($0.created) }.count,
            prayersAnswered: prayers.filter { $0.answered.map(inYear) ?? false }.count
        )
    }

    /// Year in Review is offered through December and January.
    static func isSeason(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        let month = calendar.component(.month, from: date)
        return month == 12 || month == 1
    }

    /// The year to review: in January, the one just ended.
    static func reviewedYear(on date: Date = .now, calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: date)
        return calendar.component(.month, from: date) == 1 ? year - 1 : year
    }
}
