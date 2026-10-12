import Foundation

// Group challenges: reading, memorising, a daily reading streak or daily
// prayer, done together for 1 to 90 days. Rows mirror public.group_challenges
// in supabase/migrations/20261011000000_group_moderation_challenges.sql.
// Only ids are stored (chapters, verses); the words always come from the
// Bible databases on the device.

enum GroupChallengeKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case reading, memorise, streak, prayer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reading: String(localized: "Read Together", comment: "Group challenge kind")
        case .memorise: String(localized: "Memorize Together", comment: "Group challenge kind")
        case .streak: String(localized: "Reading Streak", comment: "Group challenge kind")
        case .prayer: String(localized: "Pray Every Day", comment: "Group challenge kind")
        }
    }

    /// One line on what the challenge asks of each member.
    var summary: String {
        switch self {
        case .reading: String(localized: "Read the same chapters together, each at your own pace.")
        case .memorise: String(localized: "Learn the same passage by heart together.")
        case .streak: String(localized: "Read something every day until the challenge ends.")
        case .prayer: String(localized: "Pray for each other's requests every day.")
        }
    }

    var systemImage: String {
        switch self {
        case .reading: "book"
        case .memorise: "brain.head.profile"
        case .streak: "flame"
        case .prayer: "hands.and.sparkles"
        }
    }

    /// A sensible length to start from.
    var defaultDays: Int {
        switch self {
        case .reading: 14
        case .memorise: 7
        case .streak: 21
        case .prayer: 7
        }
    }

    /// Lengths offered as quick choices (any 1 to 90 is allowed).
    var suggestedDays: [Int] {
        switch self {
        case .reading: [7, 14, 30]
        case .memorise: [7, 14]
        case .streak: [7, 21, 30]
        case .prayer: [7, 21, 30]
        }
    }

    /// Ticked one day at a time (streak and prayer).
    var isDaily: Bool { self == .streak || self == .prayer }
}

enum GroupChallengeStatus: String, Sendable, Comparable {
    case running, upcoming, finished

    private var order: Int {
        switch self {
        case .running: 0
        case .upcoming: 1
        case .finished: 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
}

/// The rules every challenge shares (the server checks them too).
enum GroupChallengeRules {
    static let dayRange = 1...90
    static let titleLength = 1...80
    static let detailsLength = 500
    /// Challenges a group can run (or have waiting) at once.
    static let maximumRunning = 5
    /// How far ahead a challenge can be scheduled.
    static let latestStartDays = 60
    /// The most verses in a memorise challenge, as in Memorise itself.
    static var maximumVerses: Int { MemoriseSuggestions.maximumVerses }
}

/// Calendar days for challenges, in the device's calendar: a day's number
/// counts from 1 on the start day, whatever the clock change in between.
enum ChallengeDays {
    /// "2026-10-06" → the start of that day in `calendar`.
    static func date(from day: String, calendar: Calendar) -> Date? {
        Timestamp.day(from: day, calendar: calendar)
    }

    /// The day's number (1 on `start`, 0 the day before, and so on).
    static func index(of date: Date, start: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: date)
        return (calendar.dateComponents([.day], from: from, to: to).day ?? 0) + 1
    }
}

/// A challenge in a group.
struct GroupChallenge: Identifiable, Hashable, Sendable {
    let id: UUID
    let groupID: UUID
    let createdBy: UUID?
    let kind: GroupChallengeKind
    let title: String
    let details: String
    /// The first day, "yyyy-MM-dd" (a calendar day, not an instant).
    let startDay: String
    let days: Int
    /// Reading: the chapters (book * 1000 + chapter), in order.
    let chapters: [Int]
    /// Memorise: the passage, and the translation it's learned in.
    let verseStart: Int?
    let verseEnd: Int?
    let translationID: String?
    let createdAt: Date
    /// Set when a moderator ended it early: it stays, finished, with
    /// everyone's progress.
    var endedAt: Date? = nil

    var wasEndedEarly: Bool { endedAt != nil }

    func startDate(calendar: Calendar = .current) -> Date? {
        ChallengeDays.date(from: startDay, calendar: calendar)
    }

    /// The last day of the challenge.
    func endDate(calendar: Calendar = .current) -> Date? {
        startDate(calendar: calendar).flatMap { calendar.date(byAdding: .day, value: days - 1, to: $0) }
    }

    /// The day's number in the challenge: 1 on the first day, `days` on the
    /// last; below 1 before it starts and above `days` once it's over.
    func dayIndex(on date: Date = .now, calendar: Calendar = .current) -> Int {
        guard let start = startDate(calendar: calendar) else { return 0 }
        return ChallengeDays.index(of: date, start: start, calendar: calendar)
    }

    func status(on date: Date = .now, calendar: Calendar = .current) -> GroupChallengeStatus {
        if endedAt != nil { return .finished }
        let index = dayIndex(on: date, calendar: calendar)
        if index < 1 { return .upcoming }
        if index > days { return .finished }
        return .running
    }

    /// Today's day number while it runs, kept within 1...days.
    func currentDay(on date: Date = .now, calendar: Calendar = .current) -> Int {
        min(max(dayIndex(on: date, calendar: calendar), 1), days)
    }

    /// How many things each member can tick: chapters, days, or 1 passage.
    var itemCount: Int {
        switch kind {
        case .reading: chapters.count
        case .memorise: 1
        case .streak, .prayer: days
        }
    }

    var chapterIDs: [ChapterID] { chapters.map(ReadingChallengeChapters.chapterID) }

    var passageStart: VerseID? { verseStart.map(VerseID.init(rawValue:)) }
    var passageEnd: VerseID? { (verseEnd ?? verseStart).map(VerseID.init(rawValue:)) }

    var passage: PassageReference? {
        guard let start = passageStart, let end = passageEnd, (1...66).contains(start.book) else { return nil }
        return PassageReference(verses: [start, end])
    }

    /// The item that "I've learned it" ticks in a memorise challenge.
    static let learnedItem = 1

    /// Whether `item` can be ticked on `date`, as set_challenge_checkin
    /// decides (a day's slack either side for time zones).
    func canTick(_ item: Int, on date: Date = .now, calendar: Calendar = .current) -> Bool {
        let today = dayIndex(on: date, calendar: calendar)
        guard endedAt == nil, today >= 0, today <= days + 1 else { return false }
        switch kind {
        case .reading: return chapters.contains(item)
        case .memorise: return item == Self.learnedItem
        case .streak, .prayer: return (1...days).contains(item) && item <= today + 1
        }
    }
}

/// One member's progress (a row of group_challenge_progress). `items` is
/// nil for other people's chapters in a reading challenge.
struct ChallengeProgress: Codable, Hashable, Sendable {
    let userID: UUID
    let displayName: String
    var done: Int
    var items: [Int]?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case done, items
    }
}

/// Daily streaks from the days someone ticked.
enum ChallengeStreak {
    /// Days in a row up to today, or up to yesterday if today isn't ticked
    /// yet (the day isn't over).
    static func current(_ ticked: Set<Int>, today: Int) -> Int {
        var day = ticked.contains(today) ? today : today - 1
        var count = 0
        while day >= 1, ticked.contains(day) {
            count += 1
            day -= 1
        }
        return count
    }

    /// Still going: today or yesterday is ticked. On the first day nobody
    /// has missed anything yet.
    static func isAlive(_ ticked: Set<Int>, today: Int) -> Bool {
        today <= 1 || ticked.contains(today) || ticked.contains(today - 1)
    }
}

/// Totals for a challenge's page and row. No ranking: just how the group is
/// doing together, and how you are.
struct GroupChallengeSummary: Hashable, Sendable {
    let itemCount: Int
    let memberCount: Int
    let myItems: Set<Int>
    let myDone: Int
    let groupDone: Int
    /// The day used for streaks (today, kept within the challenge).
    let day: Int
    /// Daily challenges: members whose streak is alive.
    let stillGoing: Int

    init(challenge: GroupChallenge, rows: [ChallengeProgress], me: UUID?, on date: Date = .now, calendar: Calendar = .current) {
        itemCount = challenge.itemCount
        memberCount = rows.count
        let mine = rows.first { $0.userID == me }
        myItems = Set(mine?.items ?? [])
        myDone = min(mine?.done ?? 0, challenge.itemCount)
        groupDone = rows.reduce(0) { $0 + min(max($1.done, 0), challenge.itemCount) }
        let day = challenge.currentDay(on: date, calendar: calendar)
        self.day = day
        stillGoing = challenge.kind.isDaily
            ? rows.filter { ChallengeStreak.isAlive(Set($0.items ?? []), today: day) }.count
            : 0
    }

    /// Everyone's ticks over everything there is to tick.
    var groupFraction: Double { Self.fraction(done: groupDone, of: itemCount * memberCount) }
    var myFraction: Double { Self.fraction(done: myDone, of: itemCount) }
    var myStreak: Int { ChallengeStreak.current(myItems, today: day) }

    static func fraction(done: Int, of total: Int) -> Double {
        total > 0 ? min(1, max(0, Double(done) / Double(total))) : 0
    }
}

/// Chapters for a reading challenge, as the server stores them.
enum ReadingChallengeChapters {
    static func raw(_ chapter: ChapterID) -> Int { chapter.book * 1_000 + chapter.chapter }

    static func chapterID(_ raw: Int) -> ChapterID { ChapterID(book: raw / 1_000, chapter: raw % 1_000) }

    /// Every chapter of the given books, in canonical order.
    static func chapters(books: [Int]) -> [Int] {
        Set(books).filter { (1...66).contains($0) }.sorted().flatMap { book in
            (1...BibleBook.withNumber(book).chapterCount).map { book * 1_000 + $0 }
        }
    }

    /// A chapter range in one book (kept within the book).
    static func chapters(book: Int, from first: Int, through last: Int) -> [Int] {
        guard (1...66).contains(book) else { return [] }
        let count = BibleBook.withNumber(book).chapterCount
        let lower = min(max(first, 1), count)
        let upper = min(max(last, lower), count)
        return (lower...upper).map { book * 1_000 + $0 }
    }
}

/// What a leader picks for a reading challenge: one book (optionally a
/// chapter range) or several whole books.
struct ReadingChallengeSelection: Hashable, Sendable {
    var books: [Int] = [41]
    var firstChapter = 1
    var lastChapter = BibleBook.withNumber(41).chapterCount

    var isSingleBook: Bool { books.count == 1 }

    var chapters: [Int] {
        if let book = books.first, isSingleBook {
            return ReadingChallengeChapters.chapters(book: book, from: firstChapter, through: lastChapter)
        }
        return ReadingChallengeChapters.chapters(books: books)
    }

    /// One book, the whole of it.
    mutating func choose(book: Int) {
        books = [book]
        firstChapter = 1
        lastChapter = BibleBook.withNumber(book).chapterCount
    }

    /// Several books (or back to one).
    mutating func choose(books chosen: Set<Int>) {
        let ordered = chosen.filter { (1...66).contains($0) }.sorted()
        if ordered.count == 1, let only = ordered.first {
            choose(book: only)
        } else if !ordered.isEmpty {
            books = ordered
        }
    }

    /// "Mark", "Romans 1–8", "Romans and Galatians" or "5 books".
    var name: String {
        guard let first = books.first else { return "" }
        let book = BibleBook.withNumber(first)
        if isSingleBook {
            let whole = firstChapter <= 1 && lastChapter >= book.chapterCount
            if whole { return book.name }
            if firstChapter == lastChapter { return "\(book.name) \(firstChapter)" }
            return "\(book.name) \(firstChapter)\u{2013}\(lastChapter)"
        }
        if books.count <= 3 {
            return books.map { BibleBook.withNumber($0).name }.formatted(.list(type: .and))
        }
        return String(localized: "\(books.count) books")
    }
}

/// Titles to start from, which the leader can change.
enum ChallengeTitleSuggestion {
    static func reading(_ selection: ReadingChallengeSelection, days: Int) -> String {
        let name = selection.name
        return days == 1 ? String(localized: "Read \(name) in 1 day") : String(localized: "Read \(name) in \(days) days")
    }

    static func memorise(_ reference: PassageReference?) -> String {
        guard let reference else { return String(localized: "Learn a passage together") }
        let name = reference.description
        return String(localized: "Learn \(name) together")
    }

    static func streak(days: Int) -> String {
        days == 1 ? String(localized: "Read today") : String(localized: "Read every day for \(days) days")
    }

    static func prayer(days: Int) -> String {
        days == 1 ? String(localized: "Pray for each other today") : String(localized: "Pray for each other for \(days) days")
    }
}

/// A passage typed for a memorise challenge ("Psalm 23:1–3"): one chapter,
/// at most `GroupChallengeRules.maximumVerses` verses.
enum ChallengePassage {
    static func parse(_ text: String) -> (start: VerseID, end: VerseID)? {
        guard let reference = ReferenceParser.parse(text), let chapter = reference.chapter, let first = reference.verseStart else { return nil }
        let start = VerseID(book: reference.book.id, chapter: chapter, verse: first)
        let end = VerseID(book: reference.book.id, chapter: chapter, verse: max(first, reference.verseEnd ?? first))
        guard end.verse - start.verse < GroupChallengeRules.maximumVerses else { return nil }
        return (start, end)
    }
}

/// What a leader fills in to start a challenge.
struct GroupChallengeDraft: Hashable, Sendable {
    var kind: GroupChallengeKind = .reading
    var title = ""
    var details = ""
    var startsOn: Date = .now
    var days = GroupChallengeKind.reading.defaultDays
    /// Reading.
    var chapters: [Int] = []
    /// Memorise.
    var verseStart: VerseID?
    var verseEnd: VerseID?
    var translationID: String?

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedDetails: String { details.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Whether the server would accept it (it checks again).
    func isValid(today: Date = .now, calendar: Calendar = .current) -> Bool {
        guard GroupChallengeRules.titleLength.contains(trimmedTitle.count),
              trimmedDetails.count <= GroupChallengeRules.detailsLength,
              GroupChallengeRules.dayRange.contains(days) else { return false }
        let offset = ChallengeDays.index(of: startsOn, start: today, calendar: calendar) - 1
        guard (-1...GroupChallengeRules.latestStartDays).contains(offset) else { return false }
        switch kind {
        case .reading:
            return !chapters.isEmpty && chapters.count <= 1_189
        case .memorise:
            guard let verseStart, let verseEnd, let translationID, !translationID.isEmpty else { return false }
            return verseStart.book == verseEnd.book && verseEnd >= verseStart && (1...66).contains(verseStart.book)
        case .streak, .prayer:
            return true
        }
    }
}

/// Database error codes from the challenge functions, in words.
enum GroupChallengeError {
    static let messages: [String: String] = [
        "moderators_only": String(localized: "Only the group's owner and moderators can do that."),
        "invalid_challenge": String(localized: "Check the challenge's title, start date and length."),
        "too_many_challenges": String(localized: "A group can run up to five challenges at once."),
        "challenge_ended": String(localized: "This challenge has ended."),
        "not_started": String(localized: "This challenge hasn't started yet."),
        "invalid_item": String(localized: "That can't be ticked yet."),
    ]

    /// A friendly error for anything a challenge call throws.
    static func from(_ error: Error) -> CommunityError {
        if case let .http(_, message)? = error as? SupabaseError, let text = messages[message] {
            return .message(text)
        }
        return CommunityError.from(error)
    }
}
