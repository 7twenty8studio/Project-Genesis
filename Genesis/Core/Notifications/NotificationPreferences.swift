import Foundation
import Observation

/// The kinds of notification Versely sends, each with its own switch in
/// Settings › Notifications.
enum ReminderKind: String, CaseIterable, Identifiable, Sendable {
    /// Today's verse, at the time the person picks.
    case verseOfTheDay
    /// A nudge to read, only on days without reading yet (keeps a streak).
    case dailyReading
    /// Today's reading from the active plan, until it's ticked off.
    case readingPlan
    /// Memorize: passages ready to review.
    case memorise
    /// Reminders set on prayers in the journal.
    case prayer
    /// Sunday morning: sermon notes are ready for church.
    case sermons
    /// Sunday evening: a look back at the week's reading.
    case weeklyRecap
    /// Group announcements (push from the server).
    case groups

    var id: String { rawValue }

    /// Kinds with a time of day the person chooses.
    var hasTime: Bool {
        switch self {
        case .prayer, .groups: false
        default: true
        }
    }

    /// Off until the person turns them on, except the ones they already
    /// asked for elsewhere (a prayer's reminder, joining a group).
    var isOnByDefault: Bool {
        switch self {
        case .prayer, .groups: true
        default: false
        }
    }

    /// Default time, in minutes after midnight.
    var defaultMinutes: Int {
        switch self {
        case .verseOfTheDay: 7 * 60
        case .dailyReading: 20 * 60
        case .readingPlan: 8 * 60
        case .memorise: 12 * 60
        case .sermons: 8 * 60 + 30
        case .weeklyRecap: 18 * 60
        case .prayer, .groups: 0
        }
    }

    var title: String {
        switch self {
        case .verseOfTheDay: String(localized: "Verse of the Day")
        case .dailyReading: String(localized: "Daily Reading Reminder")
        case .readingPlan: String(localized: "Reading Plan")
        case .memorise: String(localized: "Memorize Review")
        case .prayer: String(localized: "Prayer Reminders")
        case .sermons: String(localized: "Sermon Notes on Sunday")
        case .weeklyRecap: String(localized: "Weekly Recap")
        case .groups: String(localized: "Group Announcements")
        }
    }

    var detail: String {
        switch self {
        case .verseOfTheDay: String(localized: "Today's verse, every day at the time you choose.")
        case .dailyReading: String(localized: "A gentle nudge on days you haven't read yet, to keep your streak going.")
        case .readingPlan: String(localized: "Today's reading from your plan, until you've ticked it off.")
        case .memorise: String(localized: "When verses are ready to review.")
        case .prayer: String(localized: "The reminders you set on prayers in your journal.")
        case .sermons: String(localized: "Sunday morning, so your sermon notes are ready for church.")
        case .weeklyRecap: String(localized: "Sunday evening, a look back at your week of reading.")
        case .groups: String(localized: "Announcements from your groups' leaders.")
        }
    }

    var systemImage: String {
        switch self {
        case .verseOfTheDay: "sun.max"
        case .dailyReading: "flame"
        case .readingPlan: "calendar"
        case .memorise: "brain.head.profile"
        case .prayer: "hands.sparkles"
        case .sermons: "building.columns"
        case .weeklyRecap: "chart.bar"
        case .groups: "person.3"
        }
    }
}

/// What the person wants to be notified about, and when (Settings ›
/// Notifications). Saved on the device. Nothing is sent without the
/// system's permission, and "Allow Notifications" off silences everything.
@MainActor
@Observable
final class NotificationPreferences {
    /// The master switch: off removes every Versely notification.
    var allowsNotifications: Bool {
        didSet { defaults.set(allowsNotifications, forKey: Keys.master) }
    }

    /// Bumped on every change, so the schedule can follow.
    private(set) var version = 0

    /// The Home invitation was answered (or dismissed).
    var hasAnsweredInvite: Bool {
        didSet { defaults.set(hasAnsweredInvite, forKey: Keys.invite) }
    }

    private var on: [ReminderKind: Bool]
    private var minutes: [ReminderKind: Int]
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let master = "notifications.allowed"
        static let invite = "notifications.inviteAnswered"
        static func on(_ kind: ReminderKind) -> String { "notifications.\(kind.rawValue).on" }
        static func minutes(_ kind: ReminderKind) -> String { "notifications.\(kind.rawValue).minutes" }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        allowsNotifications = defaults.object(forKey: Keys.master) as? Bool ?? true
        hasAnsweredInvite = defaults.bool(forKey: Keys.invite)
        var on: [ReminderKind: Bool] = [:]
        var minutes: [ReminderKind: Int] = [:]
        for kind in ReminderKind.allCases {
            on[kind] = defaults.object(forKey: Keys.on(kind)) as? Bool ?? kind.isOnByDefault
            let saved = defaults.object(forKey: Keys.minutes(kind)) as? Int
            minutes[kind] = saved.map { min(max($0, 0), 24 * 60 - 1) } ?? kind.defaultMinutes
        }
        self.on = on
        self.minutes = minutes
    }

    /// The kind's own switch (whatever the master switch says).
    func isOn(_ kind: ReminderKind) -> Bool { on[kind] ?? kind.isOnByDefault }

    /// Whether the kind is sent: its switch and the master switch.
    func allows(_ kind: ReminderKind) -> Bool { allowsNotifications && isOn(kind) }

    func set(_ kind: ReminderKind, on value: Bool) {
        on[kind] = value
        defaults.set(value, forKey: Keys.on(kind))
        version += 1
    }

    /// Minutes after midnight.
    func minutes(for kind: ReminderKind) -> Int { minutes[kind] ?? kind.defaultMinutes }

    func setMinutes(_ value: Int, for kind: ReminderKind) {
        let clamped = min(max(value, 0), 24 * 60 - 1)
        minutes[kind] = clamped
        defaults.set(clamped, forKey: Keys.minutes(kind))
        version += 1
    }

    func setAllowsNotifications(_ value: Bool) {
        allowsNotifications = value
        version += 1
    }

    /// The settings as plain values, for the planner.
    var snapshot: NotificationSettingsSnapshot {
        NotificationSettingsSnapshot(
            enabled: Set(ReminderKind.allCases.filter { allows($0) }),
            minutes: Dictionary(uniqueKeysWithValues: ReminderKind.allCases.map { ($0, minutes(for: $0)) })
        )
    }
}

/// Which kinds are on (master switch included) and their times.
struct NotificationSettingsSnapshot: Sendable, Equatable {
    var enabled: Set<ReminderKind>
    var minutes: [ReminderKind: Int]

    func minutes(for kind: ReminderKind) -> Int { minutes[kind] ?? kind.defaultMinutes }
}
