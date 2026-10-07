import Foundation
import Testing
@testable import Genesis

@Suite("Evening Sanctuary, chapter moments and year cards")
@MainActor
struct PremiumFeelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ day: Int, hour: Int, minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "Moments-\(UUID())")!
    }

    // MARK: Evening rule

    @Test func eveningRunsFromSixPMUntilFourAM() {
        #expect(!EveningSanctuary.isEvening(date(6, hour: 17, minute: 59), calendar: calendar))
        #expect(EveningSanctuary.isEvening(date(6, hour: 18), calendar: calendar))
        #expect(EveningSanctuary.isEvening(date(6, hour: 23, minute: 30), calendar: calendar))
        #expect(EveningSanctuary.isEvening(date(7, hour: 3, minute: 59), calendar: calendar))
        #expect(!EveningSanctuary.isEvening(date(7, hour: 4), calendar: calendar))
        #expect(!EveningSanctuary.isEvening(date(7, hour: 12), calendar: calendar))
    }

    @Test func homeCardIsHiddenInUITestsUnlessAsked() {
        let evening = date(6, hour: 21)
        let noon = date(6, hour: 12)
        #expect(EveningSanctuary.showsHomeCard(now: evening, calendar: calendar, arguments: []))
        #expect(!EveningSanctuary.showsHomeCard(now: noon, calendar: calendar, arguments: []))
        #expect(!EveningSanctuary.showsHomeCard(now: evening, calendar: calendar, arguments: ["-uiTesting"]))
        #expect(EveningSanctuary.showsHomeCard(now: noon, calendar: calendar, arguments: ["-uiTesting", "-uiTestingEvening"]))
    }

    // MARK: Sleep timer

    @Test func sleepTimerOffersQuarterHours() {
        #expect(EveningSanctuary.sleepTimerChoices == [15, 30, 45, 60])
        let start = date(6, hour: 22)
        #expect(EveningSanctuary.sleepTimerEnd(minutes: 30, from: start) == start.addingTimeInterval(30 * 60))
        #expect(EveningSanctuary.sleepTimerEnd(minutes: 60, from: start) == start.addingTimeInterval(60 * 60))
        #expect(EveningSanctuary.sleepTimerEnd(minutes: nil, from: start) == nil, "Off")
        #expect(EveningSanctuary.sleepTimerEnd(minutes: 20, from: start) == nil, "Only the offered lengths")
    }

    // MARK: Chapter moments

    @Test func chapterMomentShowsOncePerChapterPerDay() {
        let moments = ChapterMoments(isEnabled: true, defaults: defaults(), calendar: calendar)
        let john3 = ChapterID(book: 43, chapter: 3)
        let morning = date(6, hour: 8)

        #expect(moments.chapterFinished(john3, now: morning))
        #expect(moments.current?.kind == .chapter(john3))
        #expect(moments.current?.place == .reader)
        #expect(!moments.chapterFinished(john3, now: date(6, hour: 22)), "Once a day")
        #expect(moments.chapterFinished(ChapterID(book: 43, chapter: 4), now: date(6, hour: 22)), "Each chapter has its own")
        #expect(moments.chapterFinished(john3, now: date(7, hour: 7)), "Again the next day")
    }

    @Test func chapterMomentIsRememberedAcrossLaunches() {
        let store = defaults()
        let john3 = ChapterID(book: 43, chapter: 3)
        #expect(ChapterMoments(isEnabled: true, defaults: store, calendar: calendar).chapterFinished(john3, now: date(6, hour: 8)))
        #expect(!ChapterMoments(isEnabled: true, defaults: store, calendar: calendar).chapterFinished(john3, now: date(6, hour: 9)))
    }

    @Test func planDayMomentShowsOncePerPlanDay() {
        let moments = ChapterMoments(isEnabled: true, defaults: defaults(), calendar: calendar)
        let now = date(6, hour: 8)
        #expect(moments.planDayCompleted(12, planID: "plan-a", in: .plans, now: now))
        #expect(moments.current?.kind == .planDay(12))
        #expect(!moments.planDayCompleted(12, planID: "plan-a", in: .home, now: now))
        #expect(moments.planDayCompleted(12, planID: "plan-b", in: .plans, now: now), "Another plan's day 12")
        #expect(moments.planDayCompleted(13, planID: "plan-a", in: .plans, now: now))
    }

    @Test func momentsAreOffInUITestsAndCanBeDismissed() throws {
        #expect(ChapterMoments.enabledByLaunchArguments([]))
        #expect(!ChapterMoments.enabledByLaunchArguments(["-uiTesting"]))
        #expect(ChapterMoments.enabledByLaunchArguments(["-uiTesting", "-uiTestingMoments"]))

        let off = ChapterMoments(isEnabled: false, defaults: defaults(), calendar: calendar)
        #expect(!off.chapterFinished(ChapterID(book: 1, chapter: 1)))
        #expect(off.current == nil)

        let moments = ChapterMoments(isEnabled: true, defaults: defaults(), calendar: calendar)
        let now = Date.now
        moments.chapterFinished(ChapterID(book: 1, chapter: 1), now: now)
        let shown = try #require(moments.current)
        #expect(shown.isFresh(at: now.addingTimeInterval(1)))
        #expect(!shown.isFresh(at: now.addingTimeInterval(10)), "An unseen moment isn't shown later")
        moments.dismiss(shown)
        #expect(moments.current == nil)
    }

    @Test func onlyTodaysMomentsAreKept() {
        let keys: Set<String> = ["2026-10-05|chapter:43003", "2026-10-06|chapter:43003", "2026-10-06|plan:a:1"]
        let kept = ChapterMomentRule.pruned(keys, on: date(6, hour: 12), calendar: calendar)
        #expect(kept == ["2026-10-06|chapter:43003", "2026-10-06|plan:a:1"])
        #expect(ChapterMomentRule.key(for: ChapterMomentRule.chapterSubject(ChapterID(book: 43, chapter: 3)), on: date(6, hour: 12), calendar: calendar) == "2026-10-06|chapter:43003")
    }

    // MARK: Year in Review cards

    @Test func readingWeeksCoverEveryDayOfTheYear() {
        let weeks = YearInReview.readingWeeks(year: 2026, readingDays: ["2026-01-01", "2026-12-31", "2025-12-31"], calendar: calendar)
        let fullWeeks = weeks.allSatisfy { $0.count == 7 }
        #expect(fullWeeks)
        let days = weeks.flatMap { $0 }.compactMap { $0 }
        #expect(days.count == 365)
        let filled = days.filter { $0 }.count
        #expect(filled == 2, "Only this year's days are filled")
        #expect(days.first == true)
        #expect(days.last == true)
        // 1 January 2026 is a Thursday: four empty cells before it (weeks start on Sunday).
        let leadingBlanks = weeks[0].prefix(4).allSatisfy { $0 == nil }
        #expect(leadingBlanks)

        let leap = YearInReview.readingWeeks(year: 2028, readingDays: [], calendar: calendar)
        let leapDays = leap.flatMap { $0 }.compactMap { $0 }.count
        #expect(leapDays == 366)
    }

    @Test func bookSharesFollowTheCanon() {
        // Genesis 1–25 of 50, and all of Jude (1 chapter).
        var chapters = Set((1...25).map { 1_000 + $0 })
        chapters.insert(65_001)
        let shares = YearInReview.bookShares(chapters: chapters)
        #expect(shares.count == 66)
        #expect(shares[0] == 0.5)
        #expect(shares[64] == 1)
        #expect(shares[1] == 0)
    }
}
