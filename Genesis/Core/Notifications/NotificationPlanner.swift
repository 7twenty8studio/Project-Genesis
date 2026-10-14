import Foundation

/// Everything the planner needs, as plain values (gathered on the main actor
/// by `ReminderScheduler`).
struct NotificationInput: Sendable {
    struct VerseText: Sendable, Equatable {
        let reference: String
        let text: String
        let verse: Int
    }

    var now: Date
    var calendar: Calendar
    var settings: NotificationSettingsSnapshot
    /// Verse of the day for each coming day, by day string ("2026-10-14"),
    /// verbatim from the person's Bible.
    var dailyVerses: [String: VerseText] = [:]
    /// Days with reading (ReadingProgress.readingDays).
    var readingDays: Set<String> = []
    /// Consecutive days read, ending today or yesterday.
    var streak: Int = 0
    /// The active plan's title, and each coming day's unfinished reading.
    var planTitle: String?
    var planReadings: [String: String] = [:]
    /// When each memorized passage is next due.
    var memoryDueDates: [Date] = []
}

/// One notification to schedule.
struct PlannedNotification: Sendable, Equatable {
    let id: String
    let kind: ReminderKind
    let fireDate: Date
    let title: String
    var subtitle: String = ""
    let body: String
    /// Where a tap goes (a versely:// link).
    let link: URL
}

/// Decides which notifications to schedule for the next week. Pure, so it's
/// tested without the notification center.
///
/// Local notifications are scheduled a week ahead (the system keeps at most
/// 64) and the schedule is rebuilt whenever Versely opens, goes to the
/// background or the settings change, so reading today removes today's
/// reading reminder, ticking off a plan day removes its reminder, and so on.
enum NotificationPlanner {
    static let idPrefix = "versely.reminder."
    static let horizonDays = 7

    static func plan(_ input: NotificationInput) -> [PlannedNotification] {
        let calendar = input.calendar
        let today = calendar.startOfDay(for: input.now)
        var planned: [PlannedNotification] = []

        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayKey = Timestamp.dayString(from: day, calendar: calendar)
            let isSunday = calendar.component(.weekday, from: day) == 1

            for kind in ReminderKind.allCases where kind.hasTime && input.settings.enabled.contains(kind) {
                guard let fire = calendar.date(byAdding: .minute, value: input.settings.minutes(for: kind), to: day),
                      fire > input.now else { continue }
                let id = idPrefix + kind.rawValue + "." + dayKey
                switch kind {
                case .verseOfTheDay:
                    guard let verse = input.dailyVerses[dayKey] else { continue }
                    planned.append(PlannedNotification(
                        id: id, kind: kind, fireDate: fire,
                        title: String(localized: "Verse of the Day"),
                        subtitle: verse.reference,
                        body: verse.text,
                        link: GenesisLink.read(verse.verse)
                    ))
                case .dailyReading:
                    // Already read that day: no nudge.
                    guard !input.readingDays.contains(dayKey) else { continue }
                    let message = readingMessage(dayOffset: offset, day: day, input: input)
                    planned.append(PlannedNotification(id: id, kind: kind, fireDate: fire, title: message.title, body: message.body, link: GenesisLink.continueReading))
                case .readingPlan:
                    guard let title = input.planTitle, let reading = input.planReadings[dayKey] else { continue }
                    planned.append(PlannedNotification(
                        id: id, kind: kind, fireDate: fire,
                        title: title,
                        body: String(localized: "Today's reading: \(reading)", comment: "Notification: today's reading in a plan, e.g. Genesis 1-3"),
                        link: GenesisLink.plans
                    ))
                case .memorise:
                    let due = input.memoryDueDates.filter { $0 <= fire }.count
                    guard due > 0 else { continue }
                    planned.append(PlannedNotification(
                        id: id, kind: kind, fireDate: fire,
                        title: String(localized: "Time to review"),
                        body: due == 1
                            ? String(localized: "1 passage is ready to review.")
                            : String(localized: "\(due) passages are ready to review."),
                        link: GenesisLink.memorise
                    ))
                case .sermons:
                    guard isSunday else { continue }
                    planned.append(PlannedNotification(
                        id: id, kind: kind, fireDate: fire,
                        title: String(localized: "Sermon Notes"),
                        body: String(localized: "Heading to church? Your sermon notes are ready."),
                        link: GenesisLink.sermons
                    ))
                case .weeklyRecap:
                    guard isSunday else { continue }
                    planned.append(PlannedNotification(
                        id: id, kind: kind, fireDate: fire,
                        title: String(localized: "Your week in Scripture"),
                        body: String(localized: "See what you read this week, and pick a goal for the next."),
                        link: GenesisLink.insights
                    ))
                case .prayer, .groups:
                    continue
                }
            }
        }
        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    /// Kind, encouraging words: never guilt. Today's can mention the streak
    /// or a return after a break; later days rotate gentle invitations.
    static func readingMessage(dayOffset: Int, day: Date, input: NotificationInput) -> (title: String, body: String) {
        if dayOffset == 0 {
            if input.streak >= 2 {
                return (
                    String(localized: "Keep your streak going"),
                    String(localized: "You've read \(input.streak) days in a row. A few minutes today keeps it going.")
                )
            }
            if input.streak == 1 {
                return (
                    String(localized: "Two days in a row?"),
                    String(localized: "You read yesterday. A few minutes today makes it two days in a row.")
                )
            }
            if !input.readingDays.isEmpty, daysSinceLastReading(input: input) >= 3 {
                return (
                    String(localized: "Welcome back anytime"),
                    String(localized: "Your Bible is right where you left it. Pick up with one chapter today.")
                )
            }
        }
        let invitations: [(String, String)] = [
            (String(localized: "A moment with Scripture"), String(localized: "A few quiet minutes with God's Word can shape your whole day.")),
            (String(localized: "Ready when you are"), String(localized: "Your Bible is right where you left it.")),
            (String(localized: "One chapter today?"), String(localized: "Small steps every day add up to the whole story.")),
            (String(localized: "Time to read"), String(localized: "Take a breath and spend a few minutes in the Word.")),
        ]
        let index = (input.calendar.ordinality(of: .day, in: .era, for: day) ?? dayOffset) % invitations.count
        return invitations[index]
    }

    /// Whole days since the last day with reading (Int.max if none).
    static func daysSinceLastReading(input: NotificationInput) -> Int {
        let today = input.calendar.startOfDay(for: input.now)
        let last = input.readingDays.compactMap { Timestamp.day(from: $0, calendar: input.calendar) }.max()
        guard let last else { return Int.max }
        return input.calendar.dateComponents([.day], from: input.calendar.startOfDay(for: last), to: today).day ?? Int.max
    }
}
