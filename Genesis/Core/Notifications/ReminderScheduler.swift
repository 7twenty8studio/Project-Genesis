import Foundation
import SwiftData
import UserNotifications

/// Puts the planned notifications on the device's schedule (local
/// notifications: they work offline, with no server). RootView calls
/// `refresh` when Versely opens or goes to the background, when data
/// changes and when the settings change; each call replaces Versely's
/// pending reminders with a fresh week (prayer reminders are scheduled by
/// `PrayerReminders`, group announcements come by push).
@MainActor
enum ReminderScheduler {
    /// False in UI tests (no permission alerts, nothing scheduled).
    static var isEnabled = true

    struct Context {
        let preferences: NotificationPreferences
        let library: BibleLibrary
        let progress: ReadingProgress
        let modelContext: ModelContext
        let features: FeaturePreferences
        let entitlements: EntitlementService
        let goals: GoalPreferences
    }

    /// Asks for the system's permission (once); true when allowed.
    static func requestAuthorization() async -> Bool {
        await PrayerReminders.requestAuthorization()
    }

    /// Whether the system lets Versely notify (nil while undecided).
    static func systemAllows() async -> Bool? {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return nil
        default: return false
        }
    }

    /// Each refresh's number: a newer one makes an older one stop, so two
    /// refreshes close together never mix their schedules.
    private static var generation = 0

    static func refresh(_ context: Context, now: Date = .now) async {
        guard isEnabled else { return }
        generation += 1
        let mine = generation
        let center = UNUserNotificationCenter.current()
        let allowed = await systemAllows() == true
        let pending = await center.pendingNotificationRequests()
        guard mine == generation else { return }
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(NotificationPlanner.idPrefix) }
        let planned = allowed ? NotificationPlanner.plan(input(for: context, now: now)) : []
        // The whole week is a few dozen requests, so it's simply replaced.
        center.removePendingNotificationRequests(withIdentifiers: ours)
        for item in planned {
            guard mine == generation else { return }
            let content = UNMutableNotificationContent()
            content.title = item.title
            if !item.subtitle.isEmpty { content.subtitle = item.subtitle }
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = item.kind.rawValue
            content.userInfo = ["link": item.link.absoluteString]
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    /// Gathers what the planner needs. Kinds whose feature is hidden (or,
    /// for Memorize, not unlocked) are left out here.
    static func input(for context: Context, now: Date, calendar: Calendar = .current) -> NotificationInput {
        var settings = context.preferences.snapshot
        let features = context.features
        if !features.isOn(.plans) { settings.enabled.remove(.readingPlan) }
        if !features.isOn(.memorise) || !context.entitlements.allows(.memorise) { settings.enabled.remove(.memorise) }
        if !features.isOn(.sermons) { settings.enabled.remove(.sermons) }
        if !features.isOn(.insights) { settings.enabled.remove(.weeklyRecap) }
        if !features.isOn(.prayer) { settings.enabled.remove(.prayerAnniversary) }

        var input = NotificationInput(now: now, calendar: calendar, settings: settings)
        let today = calendar.startOfDay(for: now)
        let days = (0..<NotificationPlanner.horizonDays).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }

        if settings.enabled.contains(.verseOfTheDay) {
            let translation = context.library.currentTranslation
            let repository = context.library.current
            for day in days {
                let id = DailyVerse.verse(for: day, calendar: calendar)
                guard let verse = try? repository.verse(id) else { continue }
                input.dailyVerses[Timestamp.dayString(from: day, calendar: calendar)] = NotificationInput.VerseText(
                    reference: "\(PassageReference(verse: id).description(in: translation.language)) (\(translation.abbreviation))",
                    text: verse.plainText,
                    verse: id.rawValue
                )
            }
        }

        if settings.enabled.contains(.dailyReading) {
            input.readingDays = context.progress.readingDays
            input.streak = context.progress.streak(on: now)
            if features.isOn(.goals) {
                input.goalToday = context.goals.goal.progress(
                    chaptersToday: context.progress.chaptersRead(on: now),
                    secondsToday: context.progress.secondsRead(on: now)
                )
            }
        }

        if settings.enabled.contains(.prayerAnniversary) {
            let answered = (try? context.modelContext.fetch(FetchDescriptor<Prayer>(predicate: #Predicate<Prayer> { $0.isAnswered }))) ?? []
            input.answeredPrayers = answered.compactMap { prayer in
                prayer.answeredAt.map { NotificationInput.AnsweredPrayer(title: prayer.displayTitle, answeredAt: $0) }
            }
        }

        if settings.enabled.contains(.readingPlan) {
            let enrollments = (try? context.modelContext.fetch(FetchDescriptor<PlanEnrollment>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
            if let enrollment = enrollments.first(where: \.isActive), let plan = enrollment.plan {
                let progress = PlanProgress(plan: plan, startDate: enrollment.startDate, completedDays: enrollment.completedDays)
                input.planTitle = plan.title
                for day in days {
                    // A day already ticked off has nothing left to remind about.
                    let scheduled = progress.scheduledDay(on: day, calendar: calendar)
                    guard !progress.completedDays.contains(scheduled), !progress.isComplete,
                          let reading = progress.todaysDay(on: day, calendar: calendar) else { continue }
                    input.planReadings[Timestamp.dayString(from: day, calendar: calendar)] = reading.title
                }
            }
        }

        if settings.enabled.contains(.memorise) {
            let memory = (try? context.modelContext.fetch(FetchDescriptor<MemoryVerse>())) ?? []
            input.memoryDueDates = memory.map(\.dueAt)
        }
        return input
    }
}
