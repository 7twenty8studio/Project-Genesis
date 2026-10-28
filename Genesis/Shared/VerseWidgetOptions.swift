import Foundation

// The verse widget's options, shared by the app (which writes the verses)
// and the widget extension (which shows them). Plain Foundation so the rules
// are easy to test; the widget's AppEnum mirrors `VerseWidgetSource`.

/// The themes a Premium verse widget can follow. The raw values are stored
/// in snapshots and widget configurations: never change them.
enum VerseCategory: String, CaseIterable, Codable, Sendable {
    case hope, peace, faith, strength, comfort, love, gratitude, guidance
}

/// What the verse widget shows. The raw values are saved in installed
/// widgets' configurations: never change them.
enum VerseWidgetSource: String, CaseIterable, Sendable {
    /// The default, and what widgets installed before the options show.
    case verseOfTheDay
    /// A different encouraging verse every few hours (free).
    case random
    /// A verse from a chapter read in the last week (Premium).
    case fromYourReading
    case hope, peace, faith, strength, comfort, love, gratitude, guidance

    var category: VerseCategory? { VerseCategory(rawValue: rawValue) }

    /// Verse of the Day and Random Verse are free; the rest need Premium.
    var needsPremium: Bool {
        switch self {
        case .verseOfTheDay, .random: false
        default: true
        }
    }

    /// Random verses and categories change every few hours; the others daily.
    var rotates: Bool { self == .random || category != nil }
}

/// When the verse widget changes. Rotating options move on every three
/// hours (eight verses a day); the others at local midnight.
enum VerseWidgetSchedule {
    static let hoursPerVerse = 3
    static let versesPerDay = 24 / hoursPerVerse

    /// Whole days from a fixed local midnight, so a day's choice is the same
    /// all day wherever the person is.
    static func dayNumber(for date: Date, calendar: Calendar = .current) -> Int {
        let reference = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        return calendar.dateComponents([.day], from: reference, to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// The three-hour block a date falls in, counted from the same midnight.
    static func slot(for date: Date, calendar: Calendar = .current) -> Int {
        dayNumber(for: date, calendar: calendar) * versesPerDay + calendar.component(.hour, from: date) / hoursPerVerse
    }

    /// The pool item for a date: the next one every three hours.
    static func index(for date: Date, count: Int, calendar: Calendar = .current) -> Int? {
        guard count > 0 else { return nil }
        let slot = slot(for: date, calendar: calendar)
        return ((slot % count) + count) % count
    }

    /// Timeline entry dates: now, then each later change for a day
    /// (rotating) or a week (daily).
    static func entryDates(rotates: Bool, from now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        var dates = [now]
        if rotates {
            let block = calendar.component(.hour, from: now) / hoursPerVerse
            for step in 1...versesPerDay {
                if let date = calendar.date(byAdding: .hour, value: (block + step) * hoursPerVerse, to: today) {
                    dates.append(date)
                }
            }
        } else {
            for offset in 1..<7 {
                if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                    dates.append(day)
                }
            }
        }
        return dates
    }
}

extension WidgetSnapshot {
    /// The verse of the day as a passage, in the snapshot's Bible.
    func dailyPassage(on date: Date, calendar: Calendar = .current) -> Passage? {
        dailyVerse(on: date, calendar: calendar).map {
            Passage(reference: $0.reference, text: $0.text, verse: $0.verse, translation: translation)
        }
    }

    /// What the verse widget shows for an option at a date. Anything not
    /// written yet (an older snapshot, no recent reading) falls back to the
    /// verse of the day.
    func passage(for source: VerseWidgetSource, on date: Date, calendar: Calendar = .current) -> Passage? {
        let chosen: Passage?
        switch source {
        case .verseOfTheDay:
            chosen = nil
        case .random:
            chosen = Self.rotating(randomVerses ?? [], on: date, calendar: calendar)
        case .fromYourReading:
            chosen = readingVerses?[Self.dayKey(for: date, calendar: calendar)]
        default:
            let pool = source.category.flatMap { categoryVerses?[$0.rawValue] } ?? []
            chosen = Self.rotating(pool, on: date, calendar: calendar)
        }
        return chosen ?? dailyPassage(on: date, calendar: calendar)
    }

    private static func rotating(_ pool: [Passage], on date: Date, calendar: Calendar) -> Passage? {
        VerseWidgetSchedule.index(for: date, count: pool.count, calendar: calendar).map { pool[$0] }
    }
}
