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

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    private static let positionKey = "progress.position"
    private static let dateKey = "progress.lastReadAt"
    private static let daysKey = "progress.readingDays"
    private static let chaptersKey = "progress.chaptersRead"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        let raw = defaults.integer(forKey: Self.positionKey)
        position = raw > 0 ? VerseID(rawValue: raw) : ChapterID.genesis1.firstVerse
        lastReadAt = defaults.object(forKey: Self.dateKey) as? Date
        readingDays = Set(defaults.stringArray(forKey: Self.daysKey) ?? [])
        chaptersRead = Set((defaults.array(forKey: Self.chaptersKey) as? [Int]) ?? [])
    }

    var hasStartedReading: Bool { lastReadAt != nil }

    func update(_ verse: VerseID, at date: Date = .now) {
        let isNewDay = readingDays.insert(Timestamp.dayString(from: date, calendar: calendar)).inserted
        let chapterKey = verse.book * 1_000 + verse.chapter
        let isNewChapter = chaptersRead.insert(chapterKey).inserted
        if isNewDay { defaults.set(Array(readingDays), forKey: Self.daysKey) }
        if isNewChapter { defaults.set(Array(chaptersRead), forKey: Self.chaptersKey) }

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
