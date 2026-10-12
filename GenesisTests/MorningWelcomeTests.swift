import Foundation
import Testing
@testable import Genesis

@Suite("Morning welcome")
@MainActor
struct MorningWelcomeTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "Welcome-\(UUID())")!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(_ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func showsOncePerDayForPremium() {
        let welcome = MorningWelcome(defaults: defaults())
        let morning = date(6, hour: 7)
        #expect(welcome.shouldShow(isPremium: true, now: morning, calendar: calendar))
        #expect(!welcome.shouldShow(isPremium: false, now: morning, calendar: calendar), "Premium only")

        welcome.markShown(now: morning, calendar: calendar)
        #expect(!welcome.shouldShow(isPremium: true, now: date(6, hour: 21), calendar: calendar), "Once a day")
        #expect(welcome.shouldShow(isPremium: true, now: date(7, hour: 6), calendar: calendar), "Again the next day")
    }

    @Test func canBeTurnedOffAndIsOffInUITests() {
        let store = defaults()
        let welcome = MorningWelcome(defaults: store)
        welcome.isOn = false
        #expect(!welcome.shouldShow(isPremium: true, now: date(6, hour: 7), calendar: calendar))
        #expect(!MorningWelcome(defaults: store).isOn, "The choice is remembered")

        let testing = MorningWelcome(isEnabled: false, defaults: defaults())
        #expect(!testing.shouldShow(isPremium: true, now: date(6, hour: 7), calendar: calendar))
    }

    @Test func ambientSoundsStartOffForNewPeople() {
        let store = defaults()
        let welcome = MorningWelcome(defaults: store)
        #expect(!welcome.playsSounds, "Off until turned on")
        // Setup marks today as greeted; the next launch still has them off.
        welcome.markShown(now: date(6, hour: 7), calendar: calendar)
        #expect(!MorningWelcome(defaults: store).playsSounds)

        welcome.playsSounds = true
        #expect(MorningWelcome(defaults: store).playsSounds, "The choice is remembered")

        // Someone greeted before the default changed keeps their sounds.
        let earlier = defaults()
        earlier.set("2026-10-05", forKey: "welcome.lastShownDay")
        #expect(MorningWelcome(defaults: earlier).playsSounds)
    }

    @Test func dayKeysFollowTheLocalCalendar() {
        // 11 pm in Chicago is already the next day in UTC; it's still the 6th here.
        #expect(MorningWelcome.dayKey(for: date(6, hour: 23), calendar: calendar) == "2026-10-06")
    }

    @Test func greetsByTimeOfDayAndFirstName() {
        #expect(MorningWelcome.firstName("  Jeovanni Santos ") == "Jeovanni")
        #expect(MorningWelcome.firstName("   ") == nil)
        #expect(MorningWelcome.firstName(nil) == nil)
        #expect(MorningWelcome.greeting(hour: 7, name: "Jeovanni") == "Good morning, Jeovanni.")
        #expect(MorningWelcome.greeting(hour: 14, name: nil) == "Good afternoon.")
        #expect(MorningWelcome.greeting(hour: 2, name: "Ana") == "Good evening, Ana.")
    }
}
