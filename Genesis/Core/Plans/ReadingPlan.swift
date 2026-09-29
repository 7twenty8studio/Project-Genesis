import Foundation

/// A contiguous run of chapters within one book, e.g. Genesis 1–3.
struct ChapterSpan: Hashable, Sendable {
    let book: Int
    let firstChapter: Int
    let lastChapter: Int

    var first: ChapterID { ChapterID(book: book, chapter: firstChapter) }

    var title: String {
        let book = BibleBook.withNumber(book)
        if book.chapterCount == 1 { return book.name }
        return firstChapter == lastChapter
            ? "\(book.name) \(firstChapter)"
            : "\(book.name) \(firstChapter)\u{2013}\(lastChapter)"
    }

    var chapters: [ChapterID] { (firstChapter...lastChapter).map { ChapterID(book: book, chapter: $0) } }
}

/// One day's reading: one or more spans, e.g. "Genesis 1–3; Matthew 1".
struct PlanDay: Hashable, Sendable {
    let number: Int
    let spans: [ChapterSpan]

    var title: String { spans.map(\.title).joined(separator: "; ") }
    var chapterCount: Int { spans.reduce(0) { $0 + $1.lastChapter - $1.firstChapter + 1 } }
}

/// A reading plan: a fixed schedule of chapters over a number of days.
struct ReadingPlan: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case builtIn
        case custom(books: [Int], days: Int)
    }

    let id: String
    let title: String
    let summary: String
    let kind: Kind
    let days: [PlanDay]

    var dayCount: Int { days.count }

    // MARK: Built-in plans

    static let oneYearID = "one-year"
    static let newTestament90ID = "nt-90"
    static let chronologicalID = "chronological"
    static let gospelsID = "gospels-30"
    static let psalmsID = "psalms-30"

    static let builtIns: [ReadingPlan] = [oneYear, newTestament90, chronological, gospels, psalms]

    static func builtIn(id: String) -> ReadingPlan? {
        builtIns.first { $0.id == id }
    }

    /// The whole Bible in a year: an Old Testament and a New Testament
    /// reading each day.
    static let oneYear: ReadingPlan = {
        let old = split(chapters(of: Array(1...39)), into: 365)
        let new = split(chapters(of: Array(40...66)), into: 365)
        let days = (0..<365).map { PlanDay(number: $0 + 1, spans: spans(for: old[$0]) + spans(for: new[$0])) }
        return ReadingPlan(
            id: oneYearID,
            title: "The Bible in a Year",
            summary: "Old and New Testament readings each day, about 15 minutes.",
            kind: .builtIn,
            days: days
        )
    }()

    static let newTestament90 = make(
        id: newTestament90ID,
        title: "New Testament in 90 Days",
        summary: "Matthew through Revelation, about three chapters a day.",
        books: Array(40...66),
        days: 90
    )

    /// Books arranged in the approximate order the events happened, e.g. Job
    /// after Genesis and the prophets alongside the history of the kings.
    static let chronologicalBookOrder: [Int] = [
        1, 18, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 19, 11, 20, 21, 22, 12, 14,
        31, 29, 32, 30, 28, 23, 33, 34, 36, 35, 24, 25, 26, 27, 15, 37, 38, 17, 16, 39,
        40, 41, 42, 43, 44, 59, 48, 52, 53, 46, 47, 45, 49, 50, 51, 57, 54, 56, 60, 58, 55, 61, 65, 62, 63, 64, 66,
    ]

    static let chronological = make(
        id: chronologicalID,
        title: "Chronological Bible",
        summary: "The whole Bible in a year, with books in the order events happened.",
        books: chronologicalBookOrder,
        days: 365
    )

    static let gospels = make(
        id: gospelsID,
        title: "The Gospels in 30 Days",
        summary: "Matthew, Mark, Luke and John: the life of Jesus in a month.",
        books: [40, 41, 42, 43],
        days: 30
    )

    static let psalms = make(
        id: psalmsID,
        title: "Psalms in 30 Days",
        summary: "Five psalms a day, a month of prayer and praise.",
        books: [19],
        days: 30
    )

    /// A plan through chosen books over a chosen number of days.
    static func custom(id: String = "custom-\(UUID().uuidString.lowercased())", title: String, books: [Int], days: Int) -> ReadingPlan {
        let plan = make(id: id, title: title, summary: "", books: books, days: days)
        return ReadingPlan(id: plan.id, title: plan.title, summary: customSummary(books: books, days: days), kind: .custom(books: books, days: days), days: plan.days)
    }

    static func customSummary(books: [Int], days: Int) -> String {
        let chapterTotal = books.reduce(0) { $0 + BibleBook.withNumber($1).chapterCount }
        let names = books.count <= 3
            ? books.map { BibleBook.withNumber($0).name }.formatted(.list(type: .and))
            : "\(books.count) books"
        return "\(names), \(chapterTotal) chapters over \(days) days."
    }

    // MARK: Schedule building

    private static func make(id: String, title: String, summary: String, books: [Int], days: Int) -> ReadingPlan {
        let parts = split(chapters(of: books), into: max(1, days))
        let planDays = parts.enumerated().map { PlanDay(number: $0.offset + 1, spans: spans(for: $0.element)) }
        return ReadingPlan(id: id, title: title, summary: summary, kind: .builtIn, days: planDays)
    }

    static func chapters(of books: [Int]) -> [ChapterID] {
        books.flatMap { book in (1...BibleBook.withNumber(book).chapterCount).map { ChapterID(book: book, chapter: $0) } }
    }

    /// Splits items into `count` consecutive groups whose sizes differ by at most one.
    static func split<T>(_ items: [T], into count: Int) -> [[T]] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let start = index * items.count / count
            let end = (index + 1) * items.count / count
            return Array(items[start..<end])
        }
    }

    /// Groups consecutive chapters of the same book into spans.
    static func spans(for chapters: [ChapterID]) -> [ChapterSpan] {
        var result: [ChapterSpan] = []
        for chapter in chapters {
            if let last = result.last, last.book == chapter.book, last.lastChapter + 1 == chapter.chapter {
                result[result.count - 1] = ChapterSpan(book: last.book, firstChapter: last.firstChapter, lastChapter: chapter.chapter)
            } else {
                result.append(ChapterSpan(book: chapter.book, firstChapter: chapter.chapter, lastChapter: chapter.chapter))
            }
        }
        return result
    }
}

/// Where someone is in a plan on a given date.
struct PlanProgress: Sendable {
    let plan: ReadingPlan
    let startDate: Date
    let completedDays: Set<Int>

    /// The scheduled day for `date`, 1-based and clamped to the plan.
    func scheduledDay(on date: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: date)
        let elapsed = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return min(max(elapsed + 1, 1), plan.dayCount)
    }

    /// The first unfinished day, or nil when the plan is complete.
    var nextDay: Int? {
        (1...max(plan.dayCount, 1)).first { !completedDays.contains($0) }
    }

    var fractionComplete: Double {
        guard plan.dayCount > 0 else { return 0 }
        return Double(completedDays.filter { (1...plan.dayCount).contains($0) }.count) / Double(plan.dayCount)
    }

    var isComplete: Bool { nextDay == nil }

    /// Unfinished days scheduled before today (today's reading isn't late yet).
    func daysBehind(on date: Date = .now, calendar: Calendar = .current) -> Int {
        let scheduled = scheduledDay(on: date, calendar: calendar)
        guard scheduled > 1 else { return 0 }
        return (1..<scheduled).filter { !completedDays.contains($0) }.count
    }

    /// Today's reading: the scheduled day if unfinished, otherwise the next unfinished day.
    func todaysDay(on date: Date = .now, calendar: Calendar = .current) -> PlanDay? {
        let scheduled = scheduledDay(on: date, calendar: calendar)
        let number = completedDays.contains(scheduled) ? (nextDay ?? scheduled) : scheduled
        return plan.days.first { $0.number == number }
    }
}
