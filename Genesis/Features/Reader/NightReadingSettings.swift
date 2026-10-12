import SwiftUI

/// Aa › Night Reading: read in Night or Starlight (Premium) whenever Dark
/// Mode is on, or from one hour until another, then back to the person's
/// own theme.
struct NightReadingSettings: View {
    /// Set to open the Premium screen when Starlight is locked.
    @Binding var premium: PremiumFeature?
    @Environment(ReaderSettings.self) private var settings
    @Environment(EntitlementService.self) private var entitlements

    var body: some View {
        @Bindable var settings = settings
        let schedule = settings.preferences.nightReading
        Section {
            Picker("At night, switch to", selection: themeSelection) {
                ForEach(NightTheme.allCases) { theme in
                    themeLabel(theme).tag(theme)
                }
            }
            .accessibilityIdentifier("settings.nightReading")

            if schedule.theme != .off {
                Picker("When", selection: $settings.preferences.nightReading.timing.animation()) {
                    ForEach(NightReadingTiming.allCases) { timing in
                        Text(timing.title).tag(timing)
                    }
                }
                .accessibilityIdentifier("settings.nightTiming")
            }

            if schedule.theme != .off, schedule.timing == .hours {
                hourPicker(String(localized: "From", comment: "Night reading starts at this hour"), selection: $settings.preferences.nightReading.startHour)
                    .accessibilityIdentifier("settings.nightStart")
                hourPicker(String(localized: "Until", comment: "Night reading ends at this hour"), selection: $settings.preferences.nightReading.endHour)
                    .accessibilityIdentifier("settings.nightEnd")
            }
        } header: {
            Text("Night Reading")
        } footer: {
            footer(schedule)
        }
    }

    /// Starlight without Premium opens the Premium screen instead.
    private var themeSelection: Binding<NightTheme> {
        Binding(
            get: { settings.preferences.nightReading.theme },
            set: { theme in
                if theme.isPremium && !entitlements.allows(.premiumThemes) {
                    premium = .premiumThemes
                } else {
                    settings.preferences.nightReading.theme = theme
                }
            }
        )
    }

    @ViewBuilder
    private func themeLabel(_ theme: NightTheme) -> some View {
        if theme.isPremium && !entitlements.allows(.premiumThemes) {
            Label(theme.title, systemImage: "lock.fill")
        } else {
            Text(theme.title)
        }
    }

    private func hourPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(NightReadingSchedule.hours, id: \.self) { hour in
                Text(NightReading.hourLabel(hour)).tag(hour)
            }
        }
    }

    @ViewBuilder
    private func footer(_ schedule: NightReadingSchedule) -> some View {
        if schedule.theme == .off {
            Text("Read on a soft, dark page at night, then return to your theme in the morning.")
        } else if schedule.theme.isPremium && !entitlements.allows(.premiumThemes) {
            Text("Starlight comes with Premium. Until then, the reader uses Night.")
        } else if schedule.timing == .darkMode {
            Text("The reader switches when Dark Mode turns on and returns to your theme when it turns off.")
        } else if schedule.startHour == schedule.endHour {
            Text("Choose different hours to switch at night.")
        } else {
            Text("The reader switches at the start time and returns to your theme at the end.")
        }
    }
}
