import Foundation

/// The theme the reader switches to at night ("At night, switch to").
enum NightTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case night
    /// Premium; without it the reader uses Night, keeping this choice.
    case starlight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: String(localized: "Off", comment: "Night reading: don't switch themes at night")
        case .night: ReaderTheme.night.title
        case .starlight: ReaderTheme.starlight.title
        }
    }

    var isPremium: Bool { self == .starlight }

    /// The reader theme to use, nil for Off. Starlight falls back to Night
    /// without Premium.
    func theme(premium: Bool) -> ReaderTheme? {
        switch self {
        case .off: nil
        case .night: .night
        case .starlight: premium ? .starlight : .night
        }
    }
}

/// When night reading switches: with the system's Dark Mode, or between two
/// hours the person sets.
enum NightReadingTiming: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Whenever Dark Mode is on (by the person or the system's own schedule).
    case darkMode
    case hours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .darkMode: String(localized: "With Dark Mode", comment: "Night reading: switch whenever the device is in Dark Mode")
        case .hours: String(localized: "At Set Hours", comment: "Night reading: switch between two chosen hours")
        }
    }
}

/// Night reading: which theme, and when (with Dark Mode by default, or from
/// one whole local hour to another, 8 pm to 6 am by default). Part of
/// `ReaderPreferences`.
struct NightReadingSchedule: Codable, Equatable, Sendable {
    var theme: NightTheme = .off
    var timing: NightReadingTiming = .darkMode
    /// The hour (0–23) night reading starts.
    var startHour = 20
    /// The hour (0–23) it ends. The same as `startHour` means never.
    var endHour = 6

    static let hours = 0...23

    init() {}

    // Decode leniently, like ReaderPreferences.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NightReadingSchedule()
        theme = (try? c.decode(NightTheme.self, forKey: .theme)) ?? d.theme
        // Saved before Dark Mode was a choice: someone who'd turned night
        // reading on chose hours, so keep them.
        timing = (try? c.decode(NightReadingTiming.self, forKey: .timing)) ?? (theme == .off ? d.timing : .hours)
        startHour = (try? c.decode(Int.self, forKey: .startHour)).map(Self.clamped) ?? d.startHour
        endHour = (try? c.decode(Int.self, forKey: .endHour)).map(Self.clamped) ?? d.endHour
    }

    private static func clamped(_ hour: Int) -> Int {
        min(max(hour, hours.lowerBound), hours.upperBound)
    }
}

/// Decides the reader's theme for night reading. Pure, so it can be tested
/// with any time, calendar and time zone.
enum NightReading {
    /// Whether `date` falls inside the night window, in local hours. The
    /// window may cross midnight (20 → 6); start == end is never night.
    static func isNight(_ date: Date, startHour: Int, endHour: Int, calendar: Calendar) -> Bool {
        guard startHour != endHour else { return false }
        let hour = calendar.component(.hour, from: date)
        if startHour < endHour {
            return hour >= startHour && hour < endHour
        }
        return hour >= startHour || hour < endHour
    }

    /// The theme to read in now: the night theme while Dark Mode is on (or
    /// inside the night window), the person's day theme otherwise
    /// (unresolved, so Auto and Seasons keep their behaviour).
    /// `systemIsDark` is the system's appearance, not the app's.
    static func theme(
        for schedule: NightReadingSchedule,
        dayTheme: ReaderTheme,
        now: Date,
        calendar: Calendar,
        systemIsDark: Bool,
        premium: Bool
    ) -> ReaderTheme {
        guard let night = schedule.theme.theme(premium: premium) else { return dayTheme }
        let nightNow = switch schedule.timing {
        case .darkMode: systemIsDark
        case .hours: isNight(now, startHour: schedule.startHour, endHour: schedule.endHour, calendar: calendar)
        }
        return nightNow ? night : dayTheme
    }

    /// When the window next opens or closes after `date`, so the reader can
    /// switch on time; nil when night reading is off or follows Dark Mode.
    static func nextChange(after date: Date, schedule: NightReadingSchedule, calendar: Calendar) -> Date? {
        guard schedule.theme != .off, schedule.timing == .hours, schedule.startHour != schedule.endHour else { return nil }
        let edges = [schedule.startHour, schedule.endHour].compactMap { hour in
            calendar.nextDate(
                after: date,
                matching: DateComponents(hour: hour, minute: 0, second: 0),
                matchingPolicy: .nextTime
            )
        }
        return edges.min()
    }

    /// A time the hour picker shows as "8 PM" or "20:00", as the person's
    /// locale prefers.
    static func hourLabel(_ hour: Int, calendar: Calendar = .current) -> String {
        // Mid-June, when no clock changes, so every hour exists.
        let date = calendar.date(from: DateComponents(year: 2001, month: 6, day: 15, hour: hour)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
