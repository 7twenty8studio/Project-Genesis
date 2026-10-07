import Foundation

// The prayer journal's pure logic: attached passages, the timeline, the
// streak and the statistics. Free for everyone, with no limits.

/// A passage held by a prayer: verse ids only, never the text. The words are
/// shown verbatim from the Bible being read.
struct PrayerPassage: Hashable, Sendable, Identifiable {
    let start: VerseID
    let end: VerseID

    init(start: VerseID, end: VerseID) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    var id: String { "\(start.rawValue)-\(end.rawValue)" }

    var reference: PassageReference {
        PassageReference(
            book: .withNumber(start.book),
            chapter: start.chapter,
            verseStart: start.verse,
            verseEnd: end.chapterID == start.chapterID && end.verse != start.verse ? end.verse : nil
        )
    }

    /// The most passages one prayer keeps.
    static let maximumPerPrayer = 20

    /// "John 3:16" or "Psalm 23:1–3", within one chapter. A whole chapter
    /// ("Psalm 23") runs to its last verse, when `lastVerse` knows it.
    static func parse(_ text: String, lastVerse: (ChapterID) -> Int? = { _ in nil }) -> PrayerPassage? {
        guard let reference = ReferenceParser.parse(text), let chapter = reference.chapter else { return nil }
        let chapterID = ChapterID(book: reference.book.id, chapter: chapter)
        if let first = reference.verseStart {
            let start = VerseID(book: chapterID.book, chapter: chapter, verse: first)
            let end = VerseID(book: chapterID.book, chapter: chapter, verse: max(first, reference.verseEnd ?? first))
            return PrayerPassage(start: start, end: end)
        }
        guard let last = lastVerse(chapterID), last >= 1 else { return nil }
        return PrayerPassage(start: chapterID.firstVerse, end: VerseID(book: chapterID.book, chapter: chapter, verse: last))
    }

    /// The selected verses in the reader, kept within the first one's chapter.
    init?(selection: some Collection<VerseID>) {
        guard let first = selection.min(), let last = selection.max() else { return nil }
        self.init(start: first, end: last.chapterID == first.chapterID ? last : first)
    }

    // MARK: Storage ("start-end,start-end")

    static func encode(_ passages: [PrayerPassage]) -> String {
        passages.map { "\($0.start.rawValue)-\($0.end.rawValue)" }.joined(separator: ",")
    }

    /// Lenient: anything unreadable is skipped, and duplicates are dropped.
    static func decode(_ raw: String) -> [PrayerPassage] {
        var seen = Set<String>()
        return raw.split(separator: ",").compactMap { part -> PrayerPassage? in
            let bounds = part.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard let first = bounds.first, first > 1_000_000 else { return nil }
            let last = bounds.count > 1 && bounds[1] > 1_000_000 ? bounds[1] : first
            let passage = PrayerPassage(start: VerseID(rawValue: first), end: VerseID(rawValue: last))
            return seen.insert(passage.id).inserted ? passage : nil
        }
    }
}

/// What the journal's logic needs from a prayer, without SwiftData.
struct PrayerFacts: Hashable, Sendable, Identifiable {
    var id: UUID
    var category: PrayerCategory
    var isAnswered: Bool
    var createdAt: Date
    var answeredAt: Date?
    var lastPrayedAt: Date?
    /// False for a prayer opened and left empty (it's discarded on close).
    var hasContent: Bool = true
}

/// "Your prayer life": counts, answered share, categories and how long
/// answers took.
struct PrayerStatistics: Equatable, Sendable {
    struct CategoryCount: Equatable, Sendable, Identifiable {
        let category: PrayerCategory
        let count: Int
        var id: String { category.rawValue }
    }

    let total: Int
    let answered: Int
    let active: Int
    /// Most prayed-for first; categories with none are left out.
    let byCategory: [CategoryCount]
    /// Mean days from asking to the answer, over answered prayers with both dates.
    let averageDaysToAnswer: Double?

    init(_ prayers: [PrayerFacts]) {
        let counted = prayers.filter(\.hasContent)
        total = counted.count
        answered = counted.filter(\.isAnswered).count
        active = total - answered
        let counts = Dictionary(grouping: counted, by: \.category).mapValues(\.count)
        byCategory = PrayerCategory.allCases
            .compactMap { category in counts[category].map { CategoryCount(category: category, count: $0) } }
            .enumerated()
            .sorted { $0.element.count == $1.element.count ? $0.offset < $1.offset : $0.element.count > $1.element.count }
            .map { $0.element }
        let waits = counted.compactMap { prayer -> Double? in
            guard prayer.isAnswered, let answeredAt = prayer.answeredAt else { return nil }
            return max(0, answeredAt.timeIntervalSince(prayer.createdAt)) / 86_400
        }
        averageDaysToAnswer = waits.isEmpty ? nil : waits.reduce(0, +) / Double(waits.count)
    }

    /// Answered, as a whole percentage of all requests (0 with none).
    var answeredPercent: Int {
        total == 0 ? 0 : Int((Double(answered) / Double(total) * 100).rounded())
    }

    /// The average wait in whole days (0 means within a day).
    var averageAnswerDays: Int? {
        averageDaysToAnswer.map { Int($0.rounded(.down)) }
    }
}

/// The journal as a story: each prayer where it was asked and, once
/// answered, where the answer came. Months newest first.
enum PrayerTimeline {
    struct Entry: Hashable, Sendable, Identifiable {
        enum Kind: String, Sendable { case asked, answered }
        let prayerID: UUID
        let kind: Kind
        let date: Date
        var id: String { "\(prayerID.uuidString)-\(kind.rawValue)" }
    }

    struct Month: Hashable, Sendable, Identifiable {
        /// The first moment of the month.
        let start: Date
        let entries: [Entry]
        var id: Date { start }
    }

    static func months(_ prayers: [PrayerFacts], calendar: Calendar = .current) -> [Month] {
        let entries = prayers.filter(\.hasContent).flatMap { prayer -> [Entry] in
            var result = [Entry(prayerID: prayer.id, kind: .asked, date: prayer.createdAt)]
            if prayer.isAnswered, let answeredAt = prayer.answeredAt {
                result.append(Entry(prayerID: prayer.id, kind: .answered, date: answeredAt))
            }
            return result
        }
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.dateInterval(of: .month, for: entry.date)?.start ?? calendar.startOfDay(for: entry.date)
        }
        return grouped
            .map { start, entries in
                Month(start: start, entries: entries.sorted { lhs, rhs in
                    // Newest first; an answer before its asking on the same instant.
                    lhs.date == rhs.date ? lhs.kind == .answered && rhs.kind == .asked : lhs.date > rhs.date
                })
            }
            .sorted { $0.start > $1.start }
    }
}

/// Days in a row with prayer: adding a request, marking one prayed or
/// answered, or "I prayed today". Shown gently; a missed day just starts
/// again. Uses the reading streak's rule (today, or through yesterday).
enum PrayerStreak {
    /// "I prayed today" and prayed/answered taps, kept on this device as
    /// "yyyy-MM-dd" days separated by commas (`@AppStorage`).
    static let storageKey = "prayer.prayedDays"
    /// Days kept in the log; older ones aren't needed for a streak.
    static let keptDays = 400

    static func days(log: Set<String>, prayers: [PrayerFacts], calendar: Calendar = .current) -> Set<String> {
        var days = log
        for prayer in prayers where prayer.hasContent {
            days.insert(Timestamp.dayString(from: prayer.createdAt, calendar: calendar))
            if let answeredAt = prayer.answeredAt {
                days.insert(Timestamp.dayString(from: answeredAt, calendar: calendar))
            }
            if let lastPrayedAt = prayer.lastPrayedAt {
                days.insert(Timestamp.dayString(from: lastPrayedAt, calendar: calendar))
            }
        }
        return days
    }

    static func length(of days: Set<String>, on date: Date = .now, calendar: Calendar = .current) -> Int {
        ReadingStreak.length(of: days, endingOn: date, calendar: calendar)
    }

    static func hasPrayed(on date: Date = .now, in days: Set<String>, calendar: Calendar = .current) -> Bool {
        days.contains(Timestamp.dayString(from: date, calendar: calendar))
    }

    static func decodeLog(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init).filter { Timestamp.day(from: $0) != nil })
    }

    /// The log with `date`'s day added, keeping only recent days.
    static func recording(_ date: Date, in raw: String, calendar: Calendar = .current) -> String {
        var days = decodeLog(raw)
        days.insert(Timestamp.dayString(from: date, calendar: calendar))
        if let cutoff = calendar.date(byAdding: .day, value: -keptDays, to: calendar.startOfDay(for: date)) {
            let oldest = Timestamp.dayString(from: cutoff, calendar: calendar)
            days = days.filter { $0 >= oldest }
        }
        return days.sorted().joined(separator: ",")
    }

    /// Records a day of prayer in the standard defaults (what `@AppStorage` reads).
    static func record(on date: Date = .now, defaults: UserDefaults = .standard) {
        let raw = defaults.string(forKey: storageKey) ?? ""
        defaults.set(recording(date, in: raw), forKey: storageKey)
    }
}

/// The journal's search: title, prayer and how it was answered.
enum PrayerSearch {
    static func matches(title: String, body: String, answerNote: String?, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return [title, body, answerNote ?? ""].contains { $0.localizedStandardContains(trimmed) }
    }
}
