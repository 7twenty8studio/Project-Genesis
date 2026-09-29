import Foundation
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

    /// Schedules, reschedules or removes the reminder to match the prayer.
    @MainActor
    static func update(for prayer: Prayer) {
        let id = prayer.id
        cancel(prayerID: id)
        guard !prayer.isAnswered, let date = prayer.reminderAt else { return }
        if !prayer.reminderRepeatsDaily, date < .now { return }

        let content = UNMutableNotificationContent()
        content.title = "A moment to pray"
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
