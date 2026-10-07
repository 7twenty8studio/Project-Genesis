import Foundation
import SwiftUI
import Testing
@testable import Genesis

@Suite("Night reading")
@MainActor
struct NightReadingTests {
    private var chicago: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(_ day: Int, hour: Int, minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        chicago.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func schedule(_ theme: NightTheme = .night, from start: Int = 20, until end: Int = 6) -> NightReadingSchedule {
        var schedule = NightReadingSchedule()
        schedule.theme = theme
        schedule.timing = .hours
        schedule.startHour = start
        schedule.endHour = end
        return schedule
    }

    private func theme(_ schedule: NightReadingSchedule, at now: Date, day: ReaderTheme = .paper, dark: Bool = false, premium: Bool = false) -> ReaderTheme {
        NightReading.theme(for: schedule, dayTheme: day, now: now, calendar: chicago, systemIsDark: dark, premium: premium)
    }

    // MARK: Dark Mode

    @Test func followsDarkModeByDefault() {
        var withDarkMode = NightReadingSchedule()
        withDarkMode.theme = .night
        let noon = date(6, hour: 12)
        let late = date(6, hour: 23)
        let light = theme(withDarkMode, at: late, day: .sepia, dark: false)
        let dark = theme(withDarkMode, at: noon, day: .sepia, dark: true)
        let next = NightReading.nextChange(after: noon, schedule: withDarkMode, calendar: chicago)
        #expect(NightReadingSchedule().timing == .darkMode)
        #expect(light == .sepia, "The hour doesn't matter")
        #expect(dark == .night)
        #expect(next == nil, "No clock to follow")
    }

    @Test func darkModeKeepsStarlightPremium() {
        var starlight = NightReadingSchedule()
        starlight.theme = .starlight
        let now = date(6, hour: 12)
        let free = theme(starlight, at: now, dark: true, premium: false)
        let premium = theme(starlight, at: now, dark: true, premium: true)
        var off = NightReadingSchedule()
        off.theme = .off
        let offInDark = theme(off, at: now, day: .sepia, dark: true)
        #expect(free == .night)
        #expect(premium == .starlight)
        #expect(offInDark == .sepia)
    }

    @Test func hoursIgnoreDarkMode() {
        let night = schedule()
        let noonInDark = theme(night, at: date(6, hour: 12), dark: true)
        #expect(noonInDark == .paper)
    }

    // MARK: The window

    @Test func windowCrossesMidnight() {
        let night = schedule()
        let evening = theme(night, at: date(6, hour: 19, minute: 59))
        let start = theme(night, at: date(6, hour: 20))
        let midnight = theme(night, at: date(7, hour: 0, minute: 30))
        let lastMinute = theme(night, at: date(7, hour: 5, minute: 59))
        let morning = theme(night, at: date(7, hour: 6))
        #expect(evening == .paper)
        #expect(start == .night)
        #expect(midnight == .night)
        #expect(lastMinute == .night)
        #expect(morning == .paper)
    }

    @Test func windowWithinOneDay() {
        let afternoon = schedule(from: 13, until: 15)
        let inside = NightReading.isNight(date(6, hour: 14), startHour: 13, endHour: 15, calendar: chicago)
        let after = NightReading.isNight(date(6, hour: 15), startHour: 13, endHour: 15, calendar: chicago)
        let resolved = theme(afternoon, at: date(6, hour: 13, minute: 30))
        #expect(inside)
        #expect(!after)
        #expect(resolved == .night)
    }

    @Test func sameStartAndEndIsOff() {
        let never = schedule(from: 21, until: 21)
        let atStart = theme(never, at: date(6, hour: 21))
        let lateNight = theme(never, at: date(7, hour: 2))
        let next = NightReading.nextChange(after: date(6, hour: 12), schedule: never, calendar: chicago)
        #expect(atStart == .paper)
        #expect(lateNight == .paper)
        #expect(next == nil)
    }

    @Test func offNeverSwitches() {
        let off = schedule(.off)
        let late = theme(off, at: date(6, hour: 23), day: .sepia)
        let next = NightReading.nextChange(after: date(6, hour: 12), schedule: off, calendar: chicago)
        #expect(late == .sepia)
        #expect(next == nil)
    }

    /// Clocks go back in Chicago at 2 am on 1 November 2026: 1 am happens
    /// twice and the night is an hour longer.
    @Test func daylightSavingNightInChicago() {
        let night = schedule()
        let firstOneThirty = date(1, hour: 1, minute: 30, month: 11)
        let secondOneThirty = firstOneThirty.addingTimeInterval(3600)
        let first = theme(night, at: firstOneThirty)
        let second = theme(night, at: secondOneThirty)
        let beforeSix = theme(night, at: date(1, hour: 5, minute: 59, month: 11))
        let six = theme(night, at: date(1, hour: 6, month: 11))
        #expect(first == .night)
        #expect(second == .night)
        #expect(beforeSix == .night)
        #expect(six == .paper)

        // From 10 pm on 31 October, the morning edge is nine hours away.
        let evening = date(31, hour: 22)
        let next = NightReading.nextChange(after: evening, schedule: night, calendar: chicago)
        let expected = date(1, hour: 6, month: 11)
        let hours = next.map { $0.timeIntervalSince(evening) / 3600 }
        #expect(next == expected)
        #expect(hours == 9)
    }

    @Test func nextChangeIsTheNearerEdge() {
        let night = schedule()
        let afternoon = NightReading.nextChange(after: date(6, hour: 15), schedule: night, calendar: chicago)
        let lateNight = NightReading.nextChange(after: date(6, hour: 23), schedule: night, calendar: chicago)
        #expect(afternoon == date(6, hour: 20))
        #expect(lateNight == date(7, hour: 6))
    }

    // MARK: Premium

    @Test func starlightNeedsPremium() {
        let starlight = schedule(.starlight)
        let late = date(6, hour: 22)
        let free = theme(starlight, at: late, premium: false)
        let premium = theme(starlight, at: late, premium: true)
        let byDay = theme(starlight, at: date(6, hour: 12), premium: true)
        #expect(free == .night, "Without Premium, Starlight falls back to Night")
        #expect(premium == .starlight)
        #expect(byDay == .paper)
        #expect(starlight.theme == .starlight, "The choice is kept")
    }

    @Test func themesAreGatedLikeOtherThemes() {
        #expect(!ReaderTheme.night.isPremium)
        #expect(ReaderTheme.starlight.isPremium)
        #expect(ReaderTheme.night.isDark)
        #expect(ReaderTheme.starlight.isDark)
        #expect(ReaderTheme.starlight.hasStars)
        #expect(!ReaderTheme.night.hasStars)
        #expect(ReaderTheme.night.hasPaperTexture, "Night keeps the book's paper")
        #expect(ReaderTheme.starlight.hasPaperTexture)
    }

    @Test func automaticKeepsItsBehaviourByDay() {
        let night = schedule()
        let noon = theme(night, at: date(6, hour: 12), day: .automatic)
        let lightResolved = noon.resolved(for: .light)
        let darkResolved = noon.resolved(for: .dark)
        let late = theme(night, at: date(6, hour: 22), day: .automatic)
        #expect(noon == .automatic)
        #expect(lightResolved == .paper)
        #expect(darkResolved == .slate)
        #expect(late == .night)
    }

    // MARK: Settings

    @Test func uiTestsNeverSwitchUnlessAsked() {
        let settings = ReaderSettings(defaults: UserDefaults(suiteName: "Night-\(UUID())")!)
        settings.preferences.theme = .sepia
        settings.preferences.nightReading = schedule(.starlight)
        settings.nightClock = date(6, hour: 22)

        settings.nightReadingOverride = false
        let blocked = settings.currentTheme(premium: true, calendar: chicago)
        settings.nightReadingOverride = true
        let alwaysNight = settings.currentTheme(premium: false, calendar: chicago)
        settings.nightReadingOverride = nil
        let clock = settings.currentTheme(premium: true, calendar: chicago)
        #expect(blocked == .sepia)
        #expect(alwaysNight == .night)
        #expect(clock == .starlight)
    }

    // MARK: Saved preferences

    @Test func oldPreferencesDecodeWithNightReadingOff() throws {
        let old = Data(#"{"theme": "sepia", "fontSize": 21, "pageTurnSound": true}"#.utf8)
        let preferences = try JSONDecoder().decode(ReaderPreferences.self, from: old)
        #expect(preferences.theme == .sepia)
        #expect(preferences.fontSize == 21)
        #expect(preferences.nightReading == NightReadingSchedule())
        #expect(preferences.nightReading.theme == .off)
        #expect(preferences.nightReading.startHour == 20)
        #expect(preferences.nightReading.endHour == 6)
        #expect(preferences.nightReading.timing == .darkMode)
    }

    @Test func nightReadingDecodesLeniently() throws {
        let partial = Data(#"{"nightReading": {"theme": "starlight", "startHour": 31}}"#.utf8)
        let preferences = try JSONDecoder().decode(ReaderPreferences.self, from: partial)
        #expect(preferences.nightReading.theme == .starlight)
        #expect(preferences.nightReading.startHour == 23, "Out of range hours are clamped")
        #expect(preferences.nightReading.endHour == 6)
        #expect(preferences.nightReading.timing == .hours, "Saved before Dark Mode: keeps the hours")

        let offBefore = Data(#"{"nightReading": {"theme": "off"}}"#.utf8)
        let off = try JSONDecoder().decode(ReaderPreferences.self, from: offBefore)
        #expect(off.nightReading.timing == .darkMode)

        let unknown = Data(#"{"nightReading": {"theme": "aurora"}}"#.utf8)
        let fallback = try JSONDecoder().decode(ReaderPreferences.self, from: unknown)
        #expect(fallback.nightReading.theme == .off)
    }

    @Test func nightReadingRoundTrips() throws {
        var preferences = ReaderPreferences()
        preferences.nightReading = schedule(.starlight, from: 21, until: 7)
        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(ReaderPreferences.self, from: data)
        #expect(decoded.nightReading == preferences.nightReading)
    }

    // MARK: Palettes

    @Test func nightTextMeetsWCAGAA() {
        for theme in [ReaderTheme.night, .starlight] {
            let palette = theme.palette
            let body = Self.contrast(palette.textHex, palette.backgroundHex)
            let onSurface = Self.contrast(palette.textHex, palette.surfaceHex)
            let secondary = Self.contrast(palette.secondaryTextHex, palette.backgroundHex)
            #expect(body >= 4.5, "\(theme.rawValue) body text")
            #expect(onSurface >= 4.5, "\(theme.rawValue) text on surfaces")
            #expect(secondary >= 4.5, "\(theme.rawValue) secondary text")
        }
    }

    @Test func nightIsSoftNotHarsh() {
        let palette = ReaderTheme.night.palette
        let body = Self.contrast(palette.textHex, palette.backgroundHex)
        let harsh = Self.contrast(0xFFFFFF, 0x000000)
        #expect(body < harsh * 0.6, "Gentler than white on black")
        #expect(palette.backgroundHex != 0x000000, "Not pure black")
    }

    @Test func widgetsCarryTheNightColours() {
        let night = WidgetSnapshotWriter.widgetTheme(for: .night)
        let starlight = WidgetSnapshotWriter.widgetTheme(for: .starlight)
        #expect(night.light.background == ReaderTheme.night.palette.backgroundHex)
        #expect(night.dark.text == ReaderTheme.night.palette.textHex)
        #expect(night.light.isDark)
        #expect(starlight.name == "starlight")
        #expect(starlight.dark.background == ReaderTheme.starlight.palette.backgroundHex)
    }

    /// WCAG relative luminance contrast ratio.
    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let first = luminance(a)
        let second = luminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}
