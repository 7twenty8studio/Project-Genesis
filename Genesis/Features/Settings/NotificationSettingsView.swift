import SwiftUI
import UIKit

/// Settings › Notifications: one switch for everything, then each kind of
/// notification with its own switch and time. Kinds belonging to a hidden
/// feature aren't listed (and aren't sent).
struct NotificationSettingsView: View {
    @Environment(NotificationPreferences.self) private var notifications
    @Environment(FeaturePreferences.self) private var features
    @Environment(FeatureFlagService.self) private var flags
    @Environment(EntitlementService.self) private var entitlements
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    /// The system's answer: nil while not asked yet.
    @State private var systemAllows: Bool?
    @State private var premium: PremiumFeature?

    var body: some View {
        Form {
            ThemedRows {
                Section {
                    Toggle("Allow Notifications", isOn: Binding(
                        get: { notifications.allowsNotifications },
                        set: { value in
                            notifications.setAllowsNotifications(value)
                            if value { Task { await askIfNeeded() } }
                        }
                    ))
                    .tint(palette.accent)
                    .accessibilityIdentifier("notifications.master")
                } footer: {
                    if systemAllows == false {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notifications are off for Versely in the Settings app.")
                            Button("Open Settings") { openSystemSettings() }
                                .accessibilityIdentifier("notifications.openSettings")
                        }
                    } else {
                        Text("Turn this off to silence every notification from Versely. Your choices below are kept for when you turn it back on.")
                    }
                }
                .listRowBackground(palette.surface)

                if notifications.allowsNotifications {
                    section(String(localized: "Every Day"), kinds: [.verseOfTheDay, .dailyReading])
                    section(String(localized: "Your Bible Life"), kinds: activityKinds)
                    if features.shows(.together, flags: flags) {
                        section(String(localized: "Groups"), kinds: groupKinds)
                    }
                }
            }
        }
        .themedScreen()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { systemAllows = await ReminderScheduler.systemAllows() }
        .onChange(of: scenePhase) { _, phase in
            // Back from the Settings app: show the new answer.
            if phase == .active { Task { systemAllows = await ReminderScheduler.systemAllows() } }
        }
        .premiumSheet($premium)
    }

    /// Kinds whose feature is shown (Settings › Features).
    private var activityKinds: [ReminderKind] {
        var kinds: [ReminderKind] = []
        if features.isOn(.plans) { kinds.append(.readingPlan) }
        if features.isOn(.memorise) { kinds.append(.memorise) }
        if features.isOn(.prayer) { kinds.append(contentsOf: [.prayer, .prayerAnniversary]) }
        if features.isOn(.sermons) { kinds.append(.sermons) }
        if features.isOn(.insights) { kinds.append(.weeklyRecap) }
        return kinds
    }

    private var groupKinds: [ReminderKind] {
        features.shows(.nudges, flags: flags) ? [.groups, .nudges] : [.groups]
    }

    @ViewBuilder
    private func section(_ title: String, kinds: [ReminderKind]) -> some View {
        if !kinds.isEmpty {
            Section {
                ForEach(kinds) { kind in
                    row(kind)
                }
            } header: {
                Text(title)
            }
            .listRowBackground(palette.surface)
        }
    }

    @ViewBuilder
    private func row(_ kind: ReminderKind) -> some View {
        if kind == .memorise, !entitlements.allows(.memorise) {
            // Memorize is Premium: its reminders come with it.
            Button {
                premium = .memorise
            } label: {
                HStack {
                    Label(kind.title, systemImage: kind.systemImage)
                    Spacer()
                    PremiumBadge()
                }
            }
            .foregroundStyle(palette.text)
            .accessibilityIdentifier("notifications.\(kind.rawValue)")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { notifications.isOn(kind) },
                    set: { value in
                        notifications.set(kind, on: value)
                        if value { Task { await askIfNeeded() } }
                    }
                )) {
                    Label(kind.title, systemImage: kind.systemImage)
                }
                .tint(palette.accent)
                .accessibilityIdentifier("notifications.\(kind.rawValue)")
                Text(kind.detail)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if kind.hasTime, notifications.isOn(kind) {
                DatePicker(
                    kind == .sermons || kind == .weeklyRecap ? String(localized: "Sunday at") : String(localized: "Time"),
                    selection: timeBinding(for: kind),
                    displayedComponents: .hourAndMinute
                )
                .accessibilityIdentifier("notifications.\(kind.rawValue).time")
            }
        }
    }

    private func timeBinding(for kind: ReminderKind) -> Binding<Date> {
        Binding(
            get: {
                let minutes = notifications.minutes(for: kind)
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                notifications.setMinutes((parts.hour ?? 0) * 60 + (parts.minute ?? 0), for: kind)
            }
        )
    }

    /// The first switch turned on asks the system for permission.
    private func askIfNeeded() async {
        // Choosing here answers the Home invitation too.
        notifications.hasAnsweredInvite = true
        // No system alerts in UI tests.
        guard ReminderScheduler.isEnabled else { return }
        if systemAllows == nil {
            systemAllows = await ReminderScheduler.requestAuthorization()
            // Now allowed: put this week's reminders on the schedule.
            notifications.setAllowsNotifications(notifications.allowsNotifications)
        }
        if notifications.allows(.groups) || notifications.allows(.nudges) { await PushNotifications.shared.enable() }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }
}
