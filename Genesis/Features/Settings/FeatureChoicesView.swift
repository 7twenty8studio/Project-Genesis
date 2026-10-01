import SwiftUI

/// The last step of setup: choose which parts of Genesis to show. Optional;
/// Continue keeps the suggested set, Keep It Simple shows just the reader.
struct FeatureChoicesView: View {
    let onFinish: () -> Void

    @Environment(FeaturePreferences.self) private var features
    @Environment(FeatureFlagService.self) private var flags
    @Environment(\.palette) private var palette
    @State private var chosen: Set<OptionalFeature> = OptionalFeature.defaults

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Make Genesis yours")
                        .font(.system(size: 34, weight: .regular, design: .serif))
                        .foregroundStyle(palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("Reading, highlights, notes and search are always here. Choose anything else you'd like; you can change this any time in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(.top, 40)

                VStack(spacing: 12) {
                    ForEach(FeaturePreferences.offered(flags: flags)) { feature in
                        FeatureToggleCard(feature: feature, isOn: Binding(
                            get: { chosen.contains(feature) },
                            set: { on in if on { chosen.insert(feature) } else { chosen.remove(feature) } }
                        ))
                    }
                }

                VStack(spacing: 14) {
                    Button {
                        features.choose(chosen)
                        onFinish()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("features.continue")

                    Button("Keep It Simple") {
                        features.choose([])
                        onFinish()
                    }
                    .font(.subheadline)
                    .foregroundStyle(palette.accent)
                    .accessibilityHint("Shows just the Bible, notes and highlights")
                    .accessibilityIdentifier("features.simple")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .themedScreen()
    }
}

/// One feature with its switch.
struct FeatureToggleCard: View {
    let feature: OptionalFeature
    @Binding var isOn: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: feature.systemImage)
                    .font(.title3)
                    .foregroundStyle(palette.accent)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(feature.title)
                        .font(.headline)
                        .foregroundStyle(palette.text)
                    Text(feature.detail)
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(palette.accent)
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("features.toggle.\(feature.rawValue)")
    }
}

/// Settings › Features: the same choices, any time.
struct FeaturesSettingsView: View {
    @Environment(FeaturePreferences.self) private var features
    @Environment(FeatureFlagService.self) private var flags
    @Environment(AudioPlayerService.self) private var audio
    @Environment(\.palette) private var palette

    var body: some View {
        List {
            Section {
                ForEach(FeaturePreferences.offered(flags: flags)) { feature in
                    FeatureToggleCard(feature: feature, isOn: Binding(
                        get: { features.isOn(feature) },
                        set: { on in
                            features.set(feature, on: on)
                            if feature == .listen, !on { audio.stop() }
                        }
                    ))
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            } footer: {
                Text("Turning something off only hides it. Your plans, prayers, groups and notes stay, and come back when you turn it on.")
            }
            Section {
                DeviceSupportNote()
            }
            .listRowBackground(palette.surface)
        }
        .themedScreen()
        .navigationTitle("Features")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What works on this device, so nobody is surprised on an older iPhone.
struct DeviceSupportNote: View {
    @Environment(\.palette) private var palette
    @State private var naturalVoices = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This device", systemImage: "iphone")
                .font(.headline)
                .foregroundStyle(palette.text)
            Text(naturalVoices > 0
                ? "Listening can use \(naturalVoices) natural-sounding voice\(naturalVoices == 1 ? "" : "s") installed on this device."
                : "Listening uses the standard voice. For a more natural sound, download an Enhanced voice in Settings › Accessibility › Spoken Content › Voices.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
            Text("Everything else in Genesis works on every iPhone and iPad that runs iOS 26. Groups, the community, sync and study notes need an internet connection; reading, listening with the device voice, search and your notes work offline.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.vertical, 4)
        .task {
            naturalVoices = NarrationVoice.available().filter { $0.qualityLabel != nil }.count
        }
    }
}
