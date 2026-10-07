import Foundation
import SwiftData
import UserNotifications

/// Local notifications for prayer reminders. Scheduled on the device, so they
/// work offline and without a server.
enum PrayerReminders {
    private static func identifier(for id: UUID) -> String { "prayer-\(id.uuidString)" }

    /// Asks for permission the first time someone sets a reminder.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    /// True while the Prayer Journal is switched off (Settings › Features):
    /// reminders wait, and come back when it's switched on again. Set by
    /// RootView from `FeaturePreferences`.
    @MainActor static var isPaused = false

    /// Whether a prayer's reminder should be on the schedule.
    static func shouldSchedule(isAnswered: Bool, reminderAt: Date?, repeatsDaily: Bool, paused: Bool, now: Date = .now) -> Bool {
        guard !paused, !isAnswered, let reminderAt else { return false }
        return repeatsDaily || reminderAt >= now
    }

    /// What to do when the Prayer Journal switch is read: `wasOn` is nil the
    /// first time (at launch), when only switched-off reminders need clearing.
    enum SwitchChange: Equatable, Sendable {
        case none, pauseAll, resumeAll
    }

    static func change(wasOn: Bool?, isOn: Bool) -> SwitchChange {
        switch (wasOn, isOn) {
        case (nil, false), (true?, false): .pauseAll
        case (false?, true): .resumeAll
        default: .none
        }
    }

    /// Follows the Prayer Journal switch: off removes every pending prayer
    /// reminder; on puts back the ones the prayers still ask for.
    @MainActor
    static func follow(_ change: SwitchChange, context: ModelContext) {
        switch change {
        case .none:
            return
        case .pauseAll:
            isPaused = true
            let prayers = (try? context.fetch(FetchDescriptor<Prayer>())) ?? []
            let ids = prayers.map { identifier(for: $0.id) }
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        case .resumeAll:
            isPaused = false
            let prayers = (try? context.fetch(FetchDescriptor<Prayer>(predicate: #Predicate { $0.reminderAt != nil }))) ?? []
            for prayer in prayers { update(for: prayer) }
        }
    }

    /// Schedules, reschedules or removes the reminder to match the prayer.
    @MainActor
    static func update(for prayer: Prayer) {
        let id = prayer.id
        cancel(prayerID: id)
        guard shouldSchedule(isAnswered: prayer.isAnswered, reminderAt: prayer.reminderAt, repeatsDaily: prayer.reminderRepeatsDaily, paused: isPaused),
              let date = prayer.reminderAt else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "A moment to pray")
        // Prayer text is private: the notification shows only the title the
        // person chose, never the body.
        content.body = prayer.displayTitle
        content.sound = .default
        content.userInfo = ["prayerID": id.uuidString]

        let calendar = Calendar.current
        let components = prayer.reminderRepeatsDaily
            ? calendar.dateComponents([.hour, .minute], from: date)
            : calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: prayer.reminderRepeatsDaily)
        let request = UNNotificationRequest(identifier: identifier(for: id), content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(prayerID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: prayerID)])
    }
}
