import SwiftUI

/// Settings › Morning Welcome (Premium): on or off, the name to greet, and
/// whether ambient sounds ease in.
struct MorningWelcomeSettingsView: View {
    @Environment(MorningWelcome.self) private var welcome
    @Environment(AmbientSoundService.self) private var ambient
    @Environment(FeaturePreferences.self) private var features
    @Environment(\.palette) private var palette
    @State private var showsPreview = false

    var body: some View {
        @Bindable var welcome = welcome
        Form {
            ThemedRows {
                Section {
                    Toggle("Show Each Day", isOn: $welcome.isOn)
                        .tint(palette.accent)
                        .accessibilityIdentifier("welcome.settings.isOn")
                } footer: {
                    Text("The first time you open Genesis each day, a quiet welcome shows today's verse and reading.")
                }
                .listRowBackground(palette.surface)

                Section {
                    TextField("Your first name", text: $welcome.name)
                        .textContentType(.givenName)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("welcome.settings.name")
                } header: {
                    Text("Greeting")
                } footer: {
                    Text("Leave it empty to use your name in groups, or no name at all.")
                }
                .listRowBackground(palette.surface)

                // Only while Ambient Sounds is switched on (Settings › Features).
                if features.isOn(.ambientSounds) {
                    Section {
                        Toggle("Ease In My Ambient Sounds", isOn: $welcome.playsSounds)
                            .tint(palette.accent)
                            .accessibilityIdentifier("welcome.settings.sounds")
                    } footer: {
                        if ambient.mix.isEmpty {
                            Text("Choose your sounds first in Settings › Ambient Sounds.")
                        } else {
                            Text("Plays \(ambient.summary), fading in gently.")
                        }
                    }
                    .listRowBackground(palette.surface)
                }

                Section {
                    Button("Preview", systemImage: "sun.horizon") { showsPreview = true }
                        .foregroundStyle(palette.accent)
                        .accessibilityIdentifier("welcome.settings.preview")
                }
                .listRowBackground(palette.surface)
            }
        }
        .themedScreen()
        .navigationTitle("Morning Welcome")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showsPreview) {
            MorningWelcomeView(isPreview: true) { showsPreview = false }
        }
    }
}
