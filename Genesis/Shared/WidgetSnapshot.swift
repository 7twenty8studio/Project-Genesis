import Foundation

/// Everything the widgets show, written by the app into the shared App Group
/// container. Widgets never open the Bible databases themselves, which keeps
/// the extension small and fast. This file belongs to both targets.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct DailyVerse: Codable, Equatable, Sendable {
        /// "yyyy-MM-dd" in the person's calendar.
        let day: String
        let reference: String
        let text: String
        let verse: Int
    }

    /// A verse (or a short passage of up to three verses) for the verse
    /// widget's other options, verbatim from a Bible database. `translation`
    /// is the Bible it came from: usually the person's, the KJV where their
    /// Bible numbers the passage differently.
    struct Passage: Codable, Equatable, Sendable {
        let reference: String
        let text: String
        /// The first verse, for opening the reader.
        let verse: Int
        let translation: String
    }

    struct ContinueReading: Codable, Equatable, Sendable {
        let reference: String
        let snippet: String
        let verse: Int
        let bookProgress: Double
    }

    struct Plan: Codable, Equatable, Sendable {
        let title: String
        let todayTitle: String
        let dayNumber: Int
        let dayCount: Int
        var isTodayComplete: Bool
        let fractionComplete: Double
        /// For ticking off today's reading from a widget.
        var enrollmentID: UUID?
        /// The day scheduled for today (what the tick marks).
        var scheduledDay: Int?
    }

    /// Memorise Scripture (Premium): the next passage to review.
    struct Memorise: Codable, Equatable, Sendable {
        let isUnlocked: Bool
        /// When each passage is next due, so the count stays right as days pass.
        let dueDates: [Date]
        let total: Int
        let reference: String?
        /// The passage's opening words, as a prompt.
        let hint: String?
        let translation: String?
        /// True while Memorise is switched off in the app (Settings ›
        /// Features): the widget shows that instead of a passage. Missing in
        /// older snapshots (decodes as nil).
        var isHidden: Bool? = nil

        func dueCount(on date: Date) -> Int { dueDates.filter { $0 <= date }.count }
    }

    /// The person's reader theme, for Premium's theme-matched widgets. The
    /// colours travel as hex values because the widget extension doesn't
    /// compile ReaderTheme. Light and dark are the same for a fixed theme;
    /// Auto differs (Paper by day, Slate by night).
    struct Theme: Codable, Equatable, Sendable {
        struct Colors: Codable, Equatable, Sendable {
            let background: UInt32
            let text: UInt32
            let secondary: UInt32
            let accent: UInt32
            /// Premium themes are printed on textured paper.
            let hasPaperTexture: Bool
            let isDark: Bool
        }

        /// `ReaderTheme.rawValue` as chosen (e.g. "automatic", "sepia").
        let name: String
        let light: Colors
        let dark: Colors
    }

    var generatedAt: Date
    var translation: String
    var dailyVerses: [DailyVerse]
    var continueReading: ContinueReading?
    var streakDays: Int
    var chaptersRead: Int
    var plan: Plan?
    var activePrayerCount: Int
    var nextPrayerReminder: Date?
    var memorise: Memorise?
    /// Premium widgets (ticking off reading, Memorise) are unlocked.
    var isPremium: Bool?
    /// Written for Premium only; missing in older snapshots (decodes as nil).
    var theme: Theme? = nil
    /// The verse widget's "Random Verse" pool for the day (free), shown in
    /// turn every few hours. Missing in older snapshots (decodes as nil).
    var randomVerses: [Passage]? = nil
    /// Premium: each `VerseCategory`'s passages, by its raw value.
    var categoryVerses: [String: [Passage]]? = nil
    /// Premium: "From Your Reading", one passage per day ("yyyy-MM-dd").
    var readingVerses: [String: Passage]? = nil

    static let appGroup = "group.com.7twenty8studio.genesis"
    static let fileName = "widget-snapshot.json"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() throws {
        guard let url = Self.fileURL else { return }
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// The verse for a calendar day, falling back to the first available.
    func dailyVerse(on date: Date, calendar: Calendar = .current) -> DailyVerse? {
        let day = Self.dayKey(for: date, calendar: calendar)
        return dailyVerses.first { $0.day == day } ?? dailyVerses.first
    }

    /// "yyyy-MM-dd" for a date in the person's calendar.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Shown in widget galleries before the app has run.
    static let placeholder = WidgetSnapshot(
        generatedAt: .now,
        translation: "KJV",
        dailyVerses: [DailyVerse(day: "", reference: String(localized: "Psalms 119:105", comment: "Bible reference"), text: "Thy word is a lamp unto my feet, and a light unto my path.", verse: 19_119_105)],
        continueReading: ContinueReading(reference: String(localized: "John 3", comment: "Bible reference: the Gospel of John, chapter 3"), snippet: "There was a man of the Pharisees, named Nicodemus, a ruler of the Jews:", verse: 43_003_001, bookProgress: 0.1),
        streakDays: 7,
        chaptersRead: 42,
        plan: Plan(title: String(localized: "The Gospels in 30 Days"), todayTitle: String(localized: "John 3\u{2013}5", comment: "Bible reference: the Gospel of John, chapters 3 to 5"), dayNumber: 26, dayCount: 30, isTodayComplete: false, fractionComplete: 0.83),
        activePrayerCount: 3,
        nextPrayerReminder: nil,
        memorise: Memorise(isUnlocked: true, dueDates: [.distantPast, .distantPast], total: 6, reference: String(localized: "Psalms 119:105", comment: "Bible reference"), hint: "Thy word is a lamp\u{2026}", translation: "KJV"),
        isPremium: true
    )
}

/// Deep links from widgets into the app.
enum GenesisLink {
    static let scheme = "genesis"

    static func read(_ verse: Int) -> URL { URL(string: "\(scheme)://read/\(verse)")! }
    static let plans = URL(string: "\(scheme)://plans")!
    static let prayer = URL(string: "\(scheme)://prayer")!
    static let memorise = URL(string: "\(scheme)://memorise")!
    /// The app's Home tab (locked Premium widgets open here; the router has
    /// no Premium route).
    static let home = URL(string: "\(scheme)://home")!
}
