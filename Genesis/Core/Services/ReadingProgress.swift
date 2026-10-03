import Foundation
import Observation

/// Remembers where the person is reading so the app reopens in place, plus
/// simple statistics: which days they read (for streaks) and which chapters
/// they have opened. Stored in UserDefaults for an instant read at launch.
@MainActor
@Observable
final class ReadingProgress {
    /// The first verse visible when the reader was last used.
    private(set) var position: VerseID
    private(set) var lastReadAt: Date?
    /// Days with reading, as "yyyy-MM-dd" in the local calendar.
    private(set) var readingDays: Set<String>
    /// Raw `ChapterID` keys (book * 1000 + chapter) of chapters opened.
    private(set) var chaptersRead: Set<Int>
    /// Seconds spent in the reader per day ("yyyy-MM-dd").
    private(set) var readingSeconds: [String: Int]
    /// Chapters opened in each year ("2026" → chapter keys), for Year in
    /// Review. Recorded from the release that added it.
    private(set) var chaptersByYear: [String: Set<Int>]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    private static let positionKey = "progress.position"
    private static let dateKey = "progress.lastReadAt"
    private static let daysKey = "progress.readingDays"
    private static let chaptersKey = "progress.chaptersRead"
    private static let secondsKey = "progress.readingSeconds"
    private static let yearChaptersKey = "progress.chaptersByYear"
    /// A session longer than this is counted as this long, so a reader left
    /// open on the table doesn't inflate the total.
    static let longestSession: TimeInterval = 45 * 60

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        let raw = defaults.integer(forKey: Self.positionKey)
        position = raw > 0 ? VerseID(rawValue: raw) : ChapterID.genesis1.firstVerse
        lastReadAt = defaults.object(forKey: Self.dateKey) as? Date
        readingDays = Set(defaults.stringArray(forKey: Self.daysKey) ?? [])
        chaptersRead = Set((defaults.array(forKey: Self.chaptersKey) as? [Int]) ?? [])
        readingSeconds = (defaults.dictionary(forKey: Self.secondsKey) as? [String: Int]) ?? [:]
        let byYear = (defaults.dictionary(forKey: Self.yearChaptersKey) as? [String: [Int]]) ?? [:]
        chaptersByYear = byYear.mapValues { Set($0) }
    }

    /// Adds time spent reading, ending at `date`.
    func addReadingTime(_ duration: TimeInterval, endingAt date: Date = .now) {
        let seconds = Int(min(max(duration, 0), Self.longestSession))
        guard seconds >= 5 else { return }
        let day = Timestamp.dayString(from: date, calendar: calendar)
        readingSeconds[day, default: 0] += seconds
        defaults.set(readingSeconds, forKey: Self.secondsKey)
    }

    var totalReadingTime: TimeInterval {
        TimeInterval(readingSeconds.values.reduce(0, +))
    }

    /// Reading time on each of the last `days` days, oldest first.
    func dailyReadingTime(days: Int, endingOn date: Date = .now) -> [(day: Date, seconds: Int)] {
        let today = calendar.startOfDay(for: date)
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, readingSeconds[Timestamp.dayString(from: day, calendar: calendar)] ?? 0)
        }
    }

    /// Books by chapters opened, the most read first.
    func favoriteBooks(limit: Int = 5) -> [(book: BibleBook, chapters: Int)] {
        let counts = Dictionary(grouping: chaptersRead, by: { $0 / 1_000 }).mapValues(\.count)
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map { (BibleBook.withNumber($0.key), $0.value) }
    }

    /// The longest run of consecutive reading days.
    var longestStreak: Int {
        let dates = readingDays.compactMap { Timestamp.day(from: $0, calendar: calendar) }.sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in dates {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    var hasStartedReading: Bool { lastReadAt != nil }

    func update(_ verse: VerseID, at date: Date = .now) {
        let isNewDay = readingDays.insert(Timestamp.dayString(from: date, calendar: calendar)).inserted
        let chapterKey = verse.book * 1_000 + verse.chapter
        let isNewChapter = chaptersRead.insert(chapterKey).inserted
        if isNewDay { defaults.set(Array(readingDays), forKey: Self.daysKey) }
        if isNewChapter { defaults.set(Array(chaptersRead), forKey: Self.chaptersKey) }
        let year = String(calendar.component(.year, from: date))
        if chaptersByYear[year, default: []].insert(chapterKey).inserted {
            defaults.set(chaptersByYear.mapValues { Array($0) }, forKey: Self.yearChaptersKey)
        }

        guard verse != position || lastReadAt == nil || isNewDay else { return }
        position = verse
        lastReadAt = date
        defaults.set(verse.rawValue, forKey: Self.positionKey)
        defaults.set(date, forKey: Self.dateKey)
    }

    /// Fraction of the current book's chapters before this one, 0...1.
    var progressThroughBook: Double {
        let book = position.chapterID.bibleBook
        return Double(position.chapter - 1) / Double(max(book.chapterCount, 1))
    }

    /// Consecutive days of reading ending today (or yesterday, so a streak
    /// isn't shown as broken before today's reading).
    func streak(on date: Date = .now) -> Int {
        ReadingStreak.length(of: readingDays, endingOn: date, calendar: calendar)
    }

    /// Books with every chapter opened.
    var booksCompleted: Int {
        BibleBook.all.filter { book in
            (1...book.chapterCount).allSatisfy { chaptersRead.contains(book.id * 1_000 + $0) }
        }.count
    }
}

enum ReadingStreak {
    static func length(of days: Set<String>, endingOn date: Date, calendar: Calendar) -> Int {
        var day = calendar.startOfDay(for: date)
        if !days.contains(Timestamp.dayString(from: day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(Timestamp.dayString(from: day, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
