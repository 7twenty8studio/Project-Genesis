import Foundation
import Observation

/// The Premium morning welcome: the first time Genesis opens each day, a
/// quiet screen greets the person by name, shows today's verse and reading,
/// and eases in their ambient sounds. Settings › Morning Welcome turns it off,
/// sets the name and whether sounds play.
@MainActor
@Observable
final class MorningWelcome {
    /// Show it each day (Premium only).
    var isOn: Bool {
        didSet { defaults.set(isOn, forKey: Keys.isOn) }
    }

    /// The name to greet; empty means the person's group name, or none.
    var name: String {
        didSet { defaults.set(name, forKey: Keys.name) }
    }

    /// Ease in the person's ambient sounds (when they've chosen some).
    var playsSounds: Bool {
        didSet { defaults.set(playsSounds, forKey: Keys.playsSounds) }
    }

    /// False in UI tests unless they ask for it, so it never covers other tests.
    @ObservationIgnored let isEnabled: Bool
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let isOn = "welcome.isOn"
        static let name = "welcome.name"
        static let playsSounds = "welcome.playsSounds"
        static let lastShown = "welcome.lastShownDay"
    }

    init(isEnabled: Bool = true, defaults: UserDefaults = .standard) {
        self.isEnabled = isEnabled
        self.defaults = defaults
        isOn = defaults.object(forKey: Keys.isOn) as? Bool ?? true
        name = defaults.string(forKey: Keys.name) ?? ""
        // Off until the person turns it on. Someone already greeted before
        // this default changed keeps the sounds they've been hearing. Saved
        // straight away, as setup marks today as greeted.
        if let saved = defaults.object(forKey: Keys.playsSounds) as? Bool {
            playsSounds = saved
        } else {
            playsSounds = defaults.string(forKey: Keys.lastShown) != nil
            defaults.set(playsSounds, forKey: Keys.playsSounds)
        }
    }

    /// True the first time today the app opens for a Premium member who has it on.
    func shouldShow(isPremium: Bool, now: Date = .now, calendar: Calendar = .current) -> Bool {
        Self.shouldShow(
            isEnabled: isEnabled,
            isOn: isOn,
            isPremium: isPremium,
            lastShownDay: defaults.string(forKey: Keys.lastShown),
            today: Self.dayKey(for: now, calendar: calendar)
        )
    }

    /// Counts today as greeted (also when the app was opened from a link or
    /// widget, so it doesn't cover where the person meant to go).
    func markShown(now: Date = .now, calendar: Calendar = .current) {
        defaults.set(Self.dayKey(for: now, calendar: calendar), forKey: Keys.lastShown)
    }

    // MARK: Pure logic

    nonisolated static func shouldShow(isEnabled: Bool, isOn: Bool, isPremium: Bool, lastShownDay: String?, today: String) -> Bool {
        isEnabled && isOn && isPremium && lastShownDay != today
    }

    /// "2026-10-06" in the person's calendar and time zone.
    nonisolated static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The first word of a name, trimmed ("Jeovanni Santos" → "Jeovanni"); nil when empty.
    nonisolated static func firstName(_ name: String?) -> String? {
        let first = name?.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init)
        return first?.isEmpty == false ? first : nil
    }

    /// "Good morning, Jeovanni." by the hour; without a name, "Good morning."
    nonisolated static func greeting(hour: Int, name: String?) -> String {
        switch (hour, name) {
        case (4..<12, let name?): String(localized: "Good morning, \(name).")
        case (12..<17, let name?): String(localized: "Good afternoon, \(name).")
        case (_, let name?): String(localized: "Good evening, \(name).")
        case (4..<12, nil): String(localized: "Good morning.")
        case (12..<17, nil): String(localized: "Good afternoon.")
        case (_, nil): String(localized: "Good evening.")
        }
    }
}
