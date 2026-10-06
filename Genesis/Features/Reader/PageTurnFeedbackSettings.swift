import SwiftUI

/// Aa › Page-turn sound and haptic, each with a slider. Letting go of a
/// slider plays the sound, or gives the tap, at the new level.
struct PageTurnFeedbackSettings: View {
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.palette) private var palette
    @State private var hapticPreview = 0

    var body: some View {
        @Bindable var settings = settings
        Toggle("Page-turn sound", isOn: $settings.preferences.pageTurnSound)
            .accessibilityIdentifier("settings.pageTurnSound")
        if settings.preferences.pageTurnSound {
            Slider(value: $settings.preferences.pageTurnVolume, in: 0...1, step: 0.25) {
                Text("Page-turn volume")
            } minimumValueLabel: {
                Image(systemName: "speaker.fill").accessibilityHidden(true)
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
            } onEditingChanged: { editing in
                if !editing { PageTurnFeedback.shared.playSound(volume: settings.preferences.pageTurnVolume) }
            }
            .tint(palette.accent)
            .foregroundStyle(palette.secondaryText)
            .accessibilityIdentifier("settings.pageTurnVolume")
        }

        Toggle("Page-turn haptic", isOn: $settings.preferences.pageTurnHaptic)
            .accessibilityIdentifier("settings.pageTurnHaptic")
        if settings.preferences.pageTurnHaptic {
            Slider(value: $settings.preferences.pageTurnHapticStrength, in: ReaderPreferences.hapticStrengthRange) {
                Text("Page-turn strength")
            } minimumValueLabel: {
                Image(systemName: "hand.tap").accessibilityHidden(true)
            } maximumValueLabel: {
                Image(systemName: "hand.tap.fill").accessibilityHidden(true)
            } onEditingChanged: { editing in
                if !editing { hapticPreview += 1 }
            }
            .tint(palette.accent)
            .foregroundStyle(palette.secondaryText)
            .accessibilityIdentifier("settings.pageTurnStrength")
            .sensoryFeedback(.impact(weight: .medium, intensity: settings.preferences.pageTurnHapticStrength), trigger: hapticPreview)
        }
    }
}
