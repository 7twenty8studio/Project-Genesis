import Foundation
import Testing
@testable import Genesis

/// Goals & Streaks: shields, milestones, the daily goal, and the reminders
/// that follow them (plus answered-prayer anniversaries).
@Suite("Goals and milestones")
struct GoalsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    /// Wednesday 14 October 2026 at noon.
    private var wednesday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
    }

    private func days(_ offsets: [Int], from date: Date) -> Set<String> {
        Set(offsets.map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))!
            return Timestamp.dayString(from: day, calendar: calendar)
        })
    }

    // MARK: Streak shields

    @Test func withoutShieldsAMissedDayEndsTheStreak() {
        let read = days([0, -1, -3, -4], from: wednesday)
        let walk = ReadingStreak.walk(read, endingOn: wednesday, calendar: calendar, shields: false)
        #expect(walk.length == 2)
        #expect(walk.lastShield == nil)
    }

    @Test func aShieldCoversOneMissedDayWithoutCountingIt() {
        let read = days([0, -1, -3, -4], from: wednesday)
        let walk = ReadingStreak.walk(read, endingOn: wednesday, calendar: calendar, shields: true)
        #expect(walk.length == 4)
        let covered = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: wednesday))!
        #expect(walk.lastShield == covered)
        let ready = ReadingStreak.shieldReady(lastShield: walk.lastShield, on: wednesday, calendar: calendar)
        #expect(!ready, "Used two days ago")
    }

    @Test func twoMissedDaysInARowEndTheStreak() {
        let read = days([0, -3, -4], from: wednesday)
        let walk = ReadingStreak.walk(read, endingOn: wednesday, calendar: calendar, shields: true)
        #expect(walk.length == 1)
    }

    @Test func atMostOneShieldAWeek() {
        // Missed -2 and -5: three days apart, so only the newer is covered.
        let read = days([0, -1, -3, -4, -6, -7], from: wednesday)
        let walk = ReadingStreak.walk(read, endingOn: wednesday, calendar: calendar, shields: true)
        #expect(walk.length == 4)
        // Missed -2 and -10: far enough apart for two shields.
        let spaced = days([0, -1, -3, -4, -5, -6, -7, -8, -9, -11], from: wednesday)
        let long = ReadingStreak.walk(spaced, endingOn: wednesday, calendar: calendar, shields: true)
        #expect(long.length == 10)
    }

    @Test func yesterdayMissedIsCoveredBeforeTodaysReading() {
        // Not read yet today, missed yesterday, read the two days before.
        let read = days([-2, -3], from: wednesday)
        let walk = ReadingStreak.walk(read, endingOn: wednesday, calendar: calendar, shields: true)
        #expect(walk.length == 2)
    }

    @Test func aShieldIsReadyAgainAfterAWeek() {
        let lastShield = calendar.date(byAdding: .day, value: -7, to: wednesday)!
        let ready = ReadingStreak.shieldReady(lastShield: lastShield, on: wednesday, calendar: calendar)
        #expect(ready)
        let none = ReadingStreak.shieldReady(lastShield: nil, on: wednesday, calendar: calendar)
        #expect(none)
    }

    // MARK: Daily goal

    @Test func goalProgressInChaptersAndMinutes() {
        let chapters = ReadingGoal.threeChapters.progress(chaptersToday: 1, secondsToday: 0)
        #expect(chapters?.done == 1)
        #expect(chapters?.remaining == 2)
        #expect(chapters?.isMet == false)
        let minutes = ReadingGoal.tenMinutes.progress(chaptersToday: 0, secondsToday: 11 * 60)
        #expect(minutes?.isMet == true)
        #expect(minutes?.fraction == 1)
        let none = ReadingGoal.none.progress(chaptersToday: 5, secondsToday: 600)
        #expect(none == nil)
    }

    @MainActor
    @Test func goalPreferencesAreRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "goals-\(UUID().uuidString)"))
        let goals = GoalPreferences(defaults: defaults)
        #expect(goals.goal == ReadingGoal.none)
        #expect(goals.usesStreakShields, "Shields start on")
        #expect(!goals.hasCelebratedAny)
        goals.goal = .fiveMinutes
        goals.usesStreakShields = false
        goals.markCelebrated([])
        let reopened = GoalPreferences(defaults: defaults)
        #expect(reopened.goal == .fiveMinutes)
        #expect(!reopened.usesStreakShields)
        #expect(reopened.hasCelebratedAny, "Looked at, even with nothing reached")
    }

    // MARK: Milestones

    @Test func milestonesReachedAndNext() {
        var stats = Milestones.Stats()
        stats.longestStreak = 8
        stats.chapters = 55
        stats.books = 1
        let earned = Set(Milestones.earned(stats).map(\.id))
        #expect(earned == ["streak.3", "streak.7", "chapters.10", "chapters.50", "books.1"])
        let next = Set(Milestones.next(stats).map(\.id))
        #expect(next.contains("streak.30"))
        #expect(next.contains("chapters.100"))
        #expect(next.contains("prayers.1"))
    }

    @Test func anExistingReaderIsntShownAParade() {
        var stats = Milestones.Stats()
        stats.longestStreak = 40
        stats.chapters = 300
        let first = Milestones.toCelebrate(stats, celebrated: [], hasCelebratedAny: false)
        #expect(first.show == nil)
        #expect(first.markQuietly.count == 7)

        // Later, one new milestone: shown, nothing marked quietly.
        stats.chapters = 500
        let later = Milestones.toCelebrate(stats, celebrated: Set(first.markQuietly), hasCelebratedAny: true)
        #expect(later.show?.id == "chapters.500")
        #expect(later.markQuietly.isEmpty)
    }

    // MARK: Reminders

    private func input(_ kinds: Set<ReminderKind>, now: Date) -> NotificationInput {
        let minutes = Dictionary(uniqueKeysWithValues: ReminderKind.allCases.map { ($0, $0.defaultMinutes) })
        return NotificationInput(now: now, calendar: calendar, settings: NotificationSettingsSnapshot(enabled: kinds, minutes: minutes))
    }

    @Test func aPartlyMetGoalGetsAnAlmostThere() {
        var data = input([.dailyReading], now: wednesday)
        data.readingDays = days([0], from: wednesday)
        data.goalToday = ReadingGoal.threeChapters.progress(chaptersToday: 1, secondsToday: 0)
        let planned = NotificationPlanner.plan(data)
        let today = planned.first { calendar.isDate($0.fireDate, inSameDayAs: wednesday) }
        #expect(today != nil)
        #expect(today?.body.contains("2") == true)
    }

    @Test func aMetGoalMeansNoReminderToday() {
        var data = input([.dailyReading], now: wednesday)
        data.readingDays = days([0], from: wednesday)
        data.goalToday = ReadingGoal.oneChapter.progress(chaptersToday: 1, secondsToday: 0)
        let planned = NotificationPlanner.plan(data)
        let today = planned.contains { calendar.isDate($0.fireDate, inSameDayAs: wednesday) }
        #expect(!today)
    }

    @Test func answeredPrayersAreRememberedAYearLater() {
        // Wednesday at 6, before the 9:00 reminder.
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 6))!
        var data = input([.prayerAnniversary], now: morning)
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 10, day: 16, hour: 20))!
        let thisYear = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 20))!
        let twoYears = calendar.date(from: DateComponents(year: 2024, month: 10, day: 16, hour: 8))!
        data.answeredPrayers = [
            .init(title: "A new job", answeredAt: lastYear),
            .init(title: "Not a year yet", answeredAt: thisYear),
            .init(title: "Healing for Mom", answeredAt: twoYears),
        ]
        let planned = NotificationPlanner.plan(data)
        #expect(planned.count == 1, "Only Friday the 16th, once")
        let friday = planned.first
        #expect(calendar.component(.day, from: friday?.fireDate ?? morning) == 16)
        #expect(friday?.title.contains("2") == true, "The oldest answer: two years")
        #expect(friday?.body.contains("Healing for Mom") == true)
        #expect(friday?.link == GenesisLink.prayer)
    }

    @Test func aLeapDayAnswerIsRememberedOnThe28th() {
        let now = calendar.date(from: DateComponents(year: 2027, month: 2, day: 25, hour: 6))!
        var data = input([.prayerAnniversary], now: now)
        let leapDay = calendar.date(from: DateComponents(year: 2024, month: 2, day: 29, hour: 12))!
        data.answeredPrayers = [.init(title: "Leap", answeredAt: leapDay)]
        let planned = NotificationPlanner.plan(data)
        #expect(planned.count == 1)
        #expect(calendar.component(.day, from: planned.first?.fireDate ?? now) == 28)
    }

    // MARK: Nudges

    @Test func nudgesFollowTheServersRules() async throws {
        let backend = InMemoryCommunityBackend()
        let friend = UUID()
        await backend.actAs(InMemoryCommunityBackend.defaultUserID, name: "Me")
        let groupID = try await backend.joinGroup(code: InMemoryCommunityBackend.sampleInviteCode)
        await backend.actAs(friend, name: "Sam")
        _ = try await backend.joinGroup(code: InMemoryCommunityBackend.sampleInviteCode)
        await backend.actAs(InMemoryCommunityBackend.defaultUserID, name: "Me")

        try await backend.nudge(friend, in: groupID)
        await #expect(throws: CommunityError.self) {
            try await backend.nudge(friend, in: groupID)
        }

        // Someone who turned nudges off can't be nudged.
        try await backend.setAcceptsNudges(false)
        await backend.actAs(friend, name: "Sam")
        await #expect(throws: CommunityError.self) {
            try await backend.nudge(InMemoryCommunityBackend.defaultUserID, in: groupID)
        }
        await backend.actAs(InMemoryCommunityBackend.defaultUserID, name: "Me")
        try await backend.setAcceptsNudges(true)
        await backend.actAs(friend, name: "Sam")
        try await backend.nudge(InMemoryCommunityBackend.defaultUserID, in: groupID)
    }
}
