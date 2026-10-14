import SwiftUI

/// A one-time invitation on Home: the verse of the day each morning and a
/// gentle evening reminder to read. Turning them on asks the system for
/// permission; either answer hides the card (Settings › Notifications has
/// everything, any time).
struct NotificationInviteCard: View {
    @Environment(NotificationPreferences.self) private var notifications
    @Environment(\.palette) private var palette
    @State private var isAsking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "bell.badge")
                    .font(.title2)
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start each day with a verse")
                        .font(.headline)
                        .foregroundStyle(palette.text)
                    Text("Get the verse of the day each morning, and a gentle reminder in the evening if you haven't read yet. Change times or turn them off anytime in Settings › Notifications.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 12) {
                Button {
                    Task { await turnOn() }
                } label: {
                    Text("Turn On")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .disabled(isAsking)
                .accessibilityIdentifier("home.notifications.turnOn")
                Button {
                    notifications.hasAnsweredInvite = true
                } label: {
                    Text("Not Now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(palette.accent)
                .accessibilityIdentifier("home.notifications.notNow")
            }
        }
        .padding(18)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func turnOn() async {
        isAsking = true
        defer { isAsking = false }
        let allowed = await ReminderScheduler.requestAuthorization()
        if allowed {
            notifications.setAllowsNotifications(true)
            notifications.set(.verseOfTheDay, on: true)
            notifications.set(.dailyReading, on: true)
        }
        notifications.hasAnsweredInvite = true
    }
}
