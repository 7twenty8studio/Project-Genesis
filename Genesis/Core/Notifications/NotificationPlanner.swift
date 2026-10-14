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
    /// Today's progress toward the daily reading goal, if one is set.
    var goalToday: GoalProgress?
    /// Answered prayers in the journal, for their anniversaries.
    var answeredPrayers: [AnsweredPrayer] = []

    struct AnsweredPrayer: Sendable, Equatable {
        let title: String
        let answeredAt: Date
    }
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
                    if input.readingDays.contains(dayKey) {
                        // Already read that day: no nudge, unless today's goal
                        // is partly done (then a gentle "almost there").
                        guard offset == 0, let goal = input.goalToday, !goal.isMet, goal.done > 0 else { continue }
                        planned.append(PlannedNotification(
                            id: id, kind: kind, fireDate: fire,
                            title: String(localized: "Almost there"),
                            body: goal.nudge,
                            link: GenesisLink.continueReading
                        ))
                        continue
                    }
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
                case .prayerAnniversary:
                    guard let anniversary = anniversaries(on: day, input: input) else { continue }
                    planned.append(PlannedNotification(
                        id: id, kind: kind, fireDate: fire,
                        title: anniversary.title,
                        body: anniversary.body,
                        link: GenesisLink.prayer
                    ))
                case .prayer, .groups, .nudges:
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

    /// Prayers answered on this day of the year, a year or more ago. One
    /// notification a day: the oldest answer, with how many more. A prayer
    /// answered on 29 February is remembered on the 28th in other years.
    static func anniversaries(on day: Date, input: NotificationInput) -> (title: String, body: String)? {
        let calendar = input.calendar
        let target = calendar.dateComponents([.year, .month, .day], from: day)
        let isLeapYear = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: target.year, month: 2, day: 1)) ?? day)?.count == 29
        let matches = input.answeredPrayers
            .compactMap { prayer -> (prayer: NotificationInput.AnsweredPrayer, years: Int)? in
                let answered = calendar.dateComponents([.year, .month, .day], from: prayer.answeredAt)
                guard let year = answered.year, let targetYear = target.year, targetYear > year else { return nil }
                let sameDay = answered.month == target.month && answered.day == target.day
                let leapDay = !isLeapYear && answered.month == 2 && answered.day == 29 && target.month == 2 && target.day == 28
                guard sameDay || leapDay else { return nil }
                return (prayer, targetYear - year)
            }
            .sorted { $0.prayer.answeredAt < $1.prayer.answeredAt }
        guard let first = matches.first else { return nil }
        let title = first.years == 1
            ? String(localized: "A year ago today")
            : String(localized: "\(first.years) years ago today", comment: "Notification: an answered prayer's anniversary")
        let name = String(first.prayer.title.prefix(80))
        let body = matches.count == 1
            ? String(localized: "On this day you marked \"\(name)\" as answered. Take a moment to remember and give thanks.", comment: "Notification: the prayer's title")
            : String(localized: "On this day you marked \"\(name)\" and \(matches.count - 1) more as answered. Take a moment to remember and give thanks.", comment: "Notification: the prayer's title, then how many more")
        return (title, body)
    }

    /// Whole days since the last day with reading (Int.max if none).
    static func daysSinceLastReading(input: NotificationInput) -> Int {
        let today = input.calendar.startOfDay(for: input.now)
        let last = input.readingDays.compactMap { Timestamp.day(from: $0, calendar: input.calendar) }.max()
        guard let last else { return Int.max }
        return input.calendar.dateComponents([.day], from: input.calendar.startOfDay(for: last), to: today).day ?? Int.max
    }
}
