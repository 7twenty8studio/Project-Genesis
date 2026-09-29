import Foundation
import Testing
@testable import Genesis

@Suite("Reading plans")
struct ReadingPlanTests {
    struct Coverage: Sendable, CustomTestStringConvertible {
        let id: String
        let chapters: Int
        let days: Int
        var testDescription: String { id }
    }

    @Test("Built-in plans cover their books exactly once", arguments: [
        Coverage(id: ReadingPlan.oneYearID, chapters: 1189, days: 365),
        Coverage(id: ReadingPlan.chronologicalID, chapters: 1189, days: 365),
        Coverage(id: ReadingPlan.newTestament90ID, chapters: 260, days: 90),
        Coverage(id: ReadingPlan.gospelsID, chapters: 89, days: 30),
        Coverage(id: ReadingPlan.psalmsID, chapters: 150, days: 30),
    ])
    func coverage(_ expected: Coverage) throws {
        let plan = try #require(ReadingPlan.builtIn(id: expected.id))
        #expect(plan.dayCount == expected.days)
        let all = plan.days.flatMap { $0.spans.flatMap(\.chapters) }
        #expect(all.count == expected.chapters)
        let unique = Set(all).count
        #expect(unique == expected.chapters, "No chapter should repeat")
        let numbers = plan.days.map(\.number)
        #expect(numbers == Array(1...expected.days))
    }

    @Test func chronologicalOrderHasEveryBookOnce() {
        #expect(ReadingPlan.chronologicalBookOrder.sorted() == Array(1...66))
    }

    @Test func dayTitlesReadNaturally() throws {
        let psalms = try #require(ReadingPlan.builtIn(id: ReadingPlan.psalmsID))
        #expect(psalms.days[0].title == "Psalms 1\u{2013}5")
        let spans = ReadingPlan.spans(for: [ChapterID(book: 1, chapter: 50), ChapterID(book: 2, chapter: 1), ChapterID(book: 2, chapter: 2)])
        #expect(PlanDay(number: 1, spans: spans).title == "Genesis 50; Exodus 1\u{2013}2")
        #expect(ChapterSpan(book: 65, firstChapter: 1, lastChapter: 1).title == "Jude")
    }

    @Test func splitIsEven() {
        let groups = ReadingPlan.split(Array(1...10), into: 3)
        let sizes = groups.map(\.count).sorted()
        let joined = groups.flatMap { $0 }
        #expect(sizes == [3, 3, 4])
        #expect(joined == Array(1...10))
    }

    @Test func customPlan() {
        let plan = ReadingPlan.custom(title: "Paul", books: [45, 46], days: 10)
        #expect(plan.dayCount == 10)
        let chapters = plan.days.flatMap { $0.spans.flatMap(\.chapters) }
        #expect(chapters.count == 32)
        #expect(plan.summary.contains("32 chapters"))
    }

    @Test func progressThroughAPlan() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 20))!
        let progress = PlanProgress(plan: .gospels, startDate: start, completedDays: [1, 2, 5])

        #expect(progress.scheduledDay(on: today, calendar: calendar) == 5)
        #expect(progress.daysBehind(on: today, calendar: calendar) == 2)
        // Today's reading is done, so the next unfinished day is offered.
        #expect(progress.todaysDay(on: today, calendar: calendar)?.number == 3)
        #expect(abs(progress.fractionComplete - 0.1) < 0.0001)
        #expect(!progress.isComplete)

        let early = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        #expect(progress.scheduledDay(on: early, calendar: calendar) == 1)
    }
}

@Suite("Reading streaks")
struct StreakTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ value: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: value, hour: 9))!
    }

    @Test func countsConsecutiveDays() {
        let days: Set<String> = ["2026-09-26", "2026-09-27", "2026-09-28", "2026-09-29"]
        #expect(ReadingStreak.length(of: days, endingOn: day(29), calendar: calendar) == 4)
    }

    @Test func yesterdayKeepsTheStreakAlive() {
        let days: Set<String> = ["2026-09-27", "2026-09-28"]
        #expect(ReadingStreak.length(of: days, endingOn: day(29), calendar: calendar) == 2)
    }

    @Test func gapBreaksTheStreak() {
        let days: Set<String> = ["2026-09-25", "2026-09-26"]
        #expect(ReadingStreak.length(of: days, endingOn: day(29), calendar: calendar) == 0)
    }
}

@Suite("Timestamps")
struct TimestampTests {
    @Test("Parses Postgres and GoTrue formats", arguments: [
        "2026-09-29T17:46:00.123456+00:00",
        "2026-09-29T17:46:00.123Z",
        "2026-09-29T17:46:00+00:00",
        "2026-09-29T12:46:00.123-05:00",
    ])
    func parses(text: String) throws {
        let date = try #require(Timestamp.date(from: text))
        let expected = try #require(Timestamp.date(from: "2026-09-29T17:46:00Z"))
        #expect(abs(date.timeIntervalSince(expected)) < 1)
    }

    @Test func roundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000.25)
        let parsed = try #require(Timestamp.date(from: Timestamp.string(from: date)))
        #expect(abs(parsed.timeIntervalSince(date)) < 0.001)
    }

    @Test func dayStrings() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23))!
        #expect(Timestamp.dayString(from: date, calendar: calendar) == "2026-03-07")
        #expect(Timestamp.day(from: "2026-03-07", calendar: calendar) == calendar.startOfDay(for: date))
    }
}

@Suite("Sync conflict rules")
struct SyncMergeTests {
    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    @Test func newRemoteRecordIsAdded() {
        #expect(SyncMerge.decide(remoteUpdatedAt: later, remoteDeleted: false, localUpdatedAt: nil) == .applyRemote)
    }

    @Test func remoteDeletionOfUnknownRecordIsIgnored() {
        #expect(SyncMerge.decide(remoteUpdatedAt: later, remoteDeleted: true, localUpdatedAt: nil) == .keepLocal)
    }

    @Test func newerRemoteWins() {
        #expect(SyncMerge.decide(remoteUpdatedAt: later, remoteDeleted: false, localUpdatedAt: earlier) == .applyRemote)
        #expect(SyncMerge.decide(remoteUpdatedAt: later, remoteDeleted: true, localUpdatedAt: earlier) == .deleteLocal)
    }

    @Test func newerLocalWins() {
        #expect(SyncMerge.decide(remoteUpdatedAt: earlier, remoteDeleted: false, localUpdatedAt: later) == .keepLocal)
        #expect(SyncMerge.decide(remoteUpdatedAt: earlier, remoteDeleted: true, localUpdatedAt: later) == .keepLocal)
    }

    @Test func sameEditIsHarmless() {
        #expect(SyncMerge.decide(remoteUpdatedAt: later, remoteDeleted: false, localUpdatedAt: later) == .applyRemote)
    }
}

@Suite("Widget snapshot")
struct WidgetSnapshotTests {
    @Test func picksTodaysVerse() {
        var snapshot = WidgetSnapshot.placeholder
        snapshot.dailyVerses = [
            .init(day: "2026-09-29", reference: "John 3:16", text: "For God so loved", verse: 43_003_016),
            .init(day: "2026-09-30", reference: "Psalms 23:1", text: "The Lord is my shepherd", verse: 19_023_001),
        ]
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 8))!
        #expect(snapshot.dailyVerse(on: date, calendar: calendar)?.reference == "Psalms 23:1")
    }

    @Test func encodesAndDecodes() throws {
        let data = try JSONEncoder().encode(WidgetSnapshot.placeholder)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(decoded == WidgetSnapshot.placeholder)
    }

    @Test func deepLinks() {
        #expect(GenesisLink.read(43_003_016).absoluteString == "genesis://read/43003016")
    }
}
