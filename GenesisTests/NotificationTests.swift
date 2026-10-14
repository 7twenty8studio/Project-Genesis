import Foundation
import Testing
@testable import Genesis

/// Settings › Notifications: what's scheduled, when, and the switches.
@Suite("Notifications")
struct NotificationTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    /// Wednesday 14 October 2026 at the given time.
    private func wednesday(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: hour, minute: minute))!
    }

    private func dayKey(_ offset: Int, from date: Date) -> String {
        let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))!
        return Timestamp.dayString(from: day, calendar: calendar)
    }

    private func input(_ kinds: Set<ReminderKind>, now: Date) -> NotificationInput {
        let minutes = Dictionary(uniqueKeysWithValues: ReminderKind.allCases.map { ($0, $0.defaultMinutes) })
        return NotificationInput(now: now, calendar: calendar, settings: NotificationSettingsSnapshot(enabled: kinds, minutes: minutes))
    }

    @Test func nothingIsSentUntilTurnedOn() {
        let planned = NotificationPlanner.plan(input([], now: wednesday(hour: 6)))
        #expect(planned.isEmpty)
    }

    @Test func theVerseOfTheDayComesEachMorningVerbatim() {
        let now = wednesday(hour: 6)
        var data = input([.verseOfTheDay], now: now)
        for offset in 0..<7 {
            data.dailyVerses[dayKey(offset, from: now)] = .init(reference: "John 3:16 (KJV)", text: "For God so loved the world…", verse: 43_003_016)
        }
        let planned = NotificationPlanner.plan(data)
        #expect(planned.count == 7)
        let first = planned[0]
        let hour = calendar.component(.hour, from: first.fireDate)
        #expect(hour == 7)
        #expect(first.body == "For God so loved the world…")
        #expect(first.subtitle == "John 3:16 (KJV)")
        #expect(first.link == GenesisLink.read(43_003_016))
    }

    @Test func aTimeAlreadyPastStartsTomorrow() {
        let now = wednesday(hour: 8)
        var data = input([.verseOfTheDay], now: now)
        for offset in 0..<7 {
            data.dailyVerses[dayKey(offset, from: now)] = .init(reference: "Ps 23:1", text: "The LORD is my shepherd", verse: 19_023_001)
        }
        let planned = NotificationPlanner.plan(data)
        #expect(planned.count == 6)
        let firstDay = calendar.component(.day, from: planned[0].fireDate)
        #expect(firstDay == 15)
    }

    @Test func noReadingNudgeOnADayAlreadyRead() {
        let now = wednesday(hour: 6)
        var data = input([.dailyReading], now: now)
        data.readingDays = [dayKey(0, from: now)]
        let planned = NotificationPlanner.plan(data)
        #expect(planned.count == 6)
        let readToday = planned.contains { calendar.isDate($0.fireDate, inSameDayAs: now) }
        #expect(!readToday)
    }

    @Test func todaysNudgeCelebratesTheStreak() {
        let now = wednesday(hour: 6)
        var data = input([.dailyReading], now: now)
        data.streak = 5
        data.readingDays = [dayKey(-1, from: now)]
        let planned = NotificationPlanner.plan(data)
        let today = planned.first { calendar.isDate($0.fireDate, inSameDayAs: now) }
        #expect(today?.body.contains("5") == true)
    }

    @Test func sermonNotesAndTheRecapComeOnSundayOnly() {
        let now = wednesday(hour: 6)
        let planned = NotificationPlanner.plan(input([.sermons, .weeklyRecap], now: now))
        #expect(planned.count == 2)
        let weekdays = Set(planned.map { calendar.component(.weekday, from: $0.fireDate) })
        #expect(weekdays == [1])
    }

    @Test func memorizeRemindsOnlyOnceSomethingIsDue() {
        let now = wednesday(hour: 6)
        var data = input([.memorise], now: now)
        let due = calendar.date(byAdding: .day, value: 2, to: wednesday(hour: 9))!
        data.memoryDueDates = [due, due]
        let planned = NotificationPlanner.plan(data)
        #expect(planned.count == 5)
        #expect(planned.first?.body.contains("2") == true)
    }

    @Test func planRemindersFollowTheUnfinishedDays() {
        let now = wednesday(hour: 6)
        var data = input([.readingPlan], now: now)
        data.planTitle = "Bible in a Year"
        data.planReadings = [dayKey(0, from: now): "Genesis 1–3", dayKey(1, from: now): "Genesis 4–7"]
        let planned = NotificationPlanner.plan(data)
        #expect(planned.count == 2)
        #expect(planned.first?.title == "Bible in a Year")
        #expect(planned.first?.body.contains("Genesis 1–3") == true)
    }

    @Test func everythingOnStaysWithinTheSystemLimit() {
        let now = wednesday(hour: 0, minute: 1)
        var data = input(Set(ReminderKind.allCases), now: now)
        for offset in 0..<7 {
            data.dailyVerses[dayKey(offset, from: now)] = .init(reference: "Ps 23:1", text: "The LORD is my shepherd", verse: 19_023_001)
            data.planReadings[dayKey(offset, from: now)] = "Psalm \(offset + 1)"
        }
        data.planTitle = "Psalms"
        data.memoryDueDates = [wednesday(hour: 0)]
        let planned = NotificationPlanner.plan(data)
        let ids = Set(planned.map(\.id))
        #expect(ids.count == planned.count, "Every notification has its own id")
        #expect(planned.count <= 40, "Leaves room in the system's 64 for prayer reminders")
        let prefixed = planned.allSatisfy { $0.id.hasPrefix(NotificationPlanner.idPrefix) }
        #expect(prefixed)
    }

    @MainActor
    @Test func theSwitchesRememberAndTheMasterSilencesAll() throws {
        let defaults = try #require(UserDefaults(suiteName: "notifications-\(UUID().uuidString)"))
        let preferences = NotificationPreferences(defaults: defaults)
        #expect(!preferences.isOn(.verseOfTheDay), "New kinds start off")
        #expect(preferences.isOn(.prayer), "Prayer reminders were already asked for")
        preferences.set(.verseOfTheDay, on: true)
        preferences.setMinutes(6 * 60 + 30, for: .verseOfTheDay)
        preferences.setMinutes(99_999, for: .dailyReading)

        let reopened = NotificationPreferences(defaults: defaults)
        #expect(reopened.isOn(.verseOfTheDay))
        #expect(reopened.minutes(for: .verseOfTheDay) == 390)
        #expect(reopened.minutes(for: .dailyReading) == 24 * 60 - 1)

        reopened.setAllowsNotifications(false)
        let silenced = reopened.snapshot.enabled
        #expect(silenced.isEmpty)
        #expect(reopened.isOn(.verseOfTheDay), "The master switch keeps each choice")
    }
}
