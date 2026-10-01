import UIKit
import UserNotifications

/// Remote notifications for group announcements, and what happens when any
/// Genesis notification is tapped.
///
/// The system calls in through the app delegate, so this is a single shared
/// object; GenesisApp connects it to the community backend and router.
@MainActor
final class PushNotifications: NSObject {
    static let shared = PushNotifications()

    /// Where to upload the device token (set when the app starts).
    var backend: CommunityBackend?
    /// Opens a group's page when its announcement is tapped.
    var onOpenGroup: ((UUID) -> Void)?
    /// Opens the prayer journal when a prayer reminder is tapped.
    var onOpenPrayerJournal: (() -> Void)?

    /// False in UI tests, so no permission alert covers the screen.
    var isEnabled = true

    private var token: String?
    /// The token and account last sent to the server.
    private var uploaded: (token: String, user: UUID)?

    #if DEBUG
    /// Builds run from Xcode use Apple's sandbox push service.
    private let isSandbox = true
    #else
    private let isSandbox = false
    #endif

    /// Asks permission (once) and registers with Apple for push. Called when
    /// someone creates or joins a group, or turns notifications on.
    func enable() async {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        if allowed { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Re-registers on launch if permission was given before, so a changed
    /// token reaches the server.
    func refreshRegistration() async {
        guard isEnabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func didRegister(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await upload() }
    }

    /// Sends the token to the server when signed in (again after signing in).
    func upload() async {
        guard let token, let backend, let user = await backend.currentUserID() else { return }
        if let uploaded, uploaded.token == token, uploaded.user == user { return }
        do {
            try await backend.registerPushToken(token, sandbox: isSandbox)
            uploaded = (token, user)
        } catch {
            CrashReporter.record(error, context: "Push.upload")
        }
    }

    /// Called just before signing out: this device stops getting the
    /// account's notifications.
    func signingOut() async {
        defer { uploaded = nil }
        guard let token, let backend else { return }
        try? await backend.unregisterPushToken(token)
    }

    fileprivate func handleTap(groupID: String?, isPrayerReminder: Bool) {
        if let groupID, let id = UUID(uuidString: groupID) {
            onOpenGroup?(id)
        } else if isPrayerReminder {
            onOpenPrayerJournal?()
        }
    }
}

extension PushNotifications: UNUserNotificationCenterDelegate {
    /// Show notifications even while Genesis is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let groupID = (info["genesis"] as? [String: Any])?["groupID"] as? String
        let isPrayerReminder = info["prayerID"] != nil
        await MainActor.run {
            PushNotifications.shared.handleTap(groupID: groupID, isPrayerReminder: isPrayerReminder)
        }
    }
}

/// Receives the push token and sets up notification handling at launch.
final class GenesisAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = PushNotifications.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotifications.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected without a push entitlement (no developer team yet).
    }
}
