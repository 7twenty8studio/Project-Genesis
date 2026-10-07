import SwiftUI

/// App settings from Home: features, Bibles and account. Reading settings
/// live in the reader ("Aa").
struct SettingsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showsBibles = false
    @State private var showsAccount = false
    @State private var showsReading = false
    @State private var showsListening = false
    @State private var showsAmbient = false
    @State private var premium: PremiumFeature?
    @Environment(EntitlementService.self) private var entitlements
    @Environment(FeaturePreferences.self) private var features

    var body: some View {
        NavigationStack {
            List {
                ThemedRows {
                    Section {
                        NavigationLink {
                            FeaturesSettingsView()
                        } label: {
                            Label("Features", systemImage: "square.grid.2x2")
                        }
                        .accessibilityIdentifier("settings.features")
                        Button {
                            showsBibles = true
                        } label: {
                            Label("Bibles", systemImage: "books.vertical")
                        }
                        Button {
                            showsAccount = true
                        } label: {
                            Label("Account", systemImage: "person.crop.circle")
                        }
                        NavigationLink {
                            AppIconPickerView()
                        } label: {
                            Label("App Icon", systemImage: "app.badge")
                        }
                        .accessibilityIdentifier("settings.appIcon")
                    }
                    .listRowBackground(palette.surface)
                    .foregroundStyle(palette.text)

                    // Reading and listening, also reachable from the reader.
                    Section {
                        Button {
                            showsReading = true
                        } label: {
                            Label("Theme & Reading", systemImage: "textformat.size")
                        }
                        .accessibilityIdentifier("settings.reading")
                        if features.isOn(.listen) {
                            Button {
                                showsListening = true
                            } label: {
                                Label("Listening", systemImage: "headphones")
                            }
                            .accessibilityIdentifier("settings.listening")
                        }
                        if features.isOn(.ambientSounds) {
                            Button {
                                if entitlements.allows(.ambientSounds) { showsAmbient = true } else { premium = .ambientSounds }
                            } label: {
                                HStack {
                                    Label("Ambient Sounds", systemImage: "speaker.wave.2")
                                    Spacer()
                                    if !entitlements.allows(.ambientSounds) { PremiumBadge() }
                                }
                            }
                            .accessibilityIdentifier("settings.ambientSounds")
                        }
                        if entitlements.allows(.morningWelcome) {
                            NavigationLink {
                                MorningWelcomeSettingsView()
                            } label: {
                                Label("Morning Welcome", systemImage: "sun.horizon")
                            }
                            .accessibilityIdentifier("settings.welcome")
                        } else {
                            Button {
                                premium = .morningWelcome
                            } label: {
                                HStack {
                                    Label("Morning Welcome", systemImage: "sun.horizon")
                                    Spacer()
                                    PremiumBadge()
                                }
                            }
                            .accessibilityIdentifier("settings.welcome")
                        }
                    } header: {
                        Text("Reading")
                    }
                    .listRowBackground(palette.surface)
                    .foregroundStyle(palette.text)

                    Section {
                        NavigationLink {
                            FeedbackView()
                        } label: {
                            Label("Send Feedback", systemImage: "envelope")
                        }
                        .accessibilityIdentifier("settings.feedback")
                    } footer: {
                        Text("Report a problem, a mistake in a Bible text, or share an idea.")
                    }
                    .listRowBackground(palette.surface)
                    .foregroundStyle(palette.text)

                    #if DEBUG
                    Section {
                        Toggle("Test as Premium", isOn: Binding(get: { entitlements.isTestingPremium }, set: { entitlements.isTestingPremium = $0 }))
                            .tint(palette.accent)
                            .accessibilityIdentifier("settings.testPremium")
                    } header: {
                        Text(verbatim: "Developer")
                    } footer: {
                        Text(verbatim: "Development builds only: turns on every Premium feature without a purchase. Release builds don't include this switch.")
                    }
                    .listRowBackground(palette.surface)
                    .foregroundStyle(palette.text)
                    #endif

                    Section {
                        // iOS keeps each app's language in the Settings app (and
                        // restarts the app when it changes), so this opens it there.
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            LabeledContent {
                                Text(AppLanguage.displayName(AppLanguage.code))
                            } label: {
                                Label("Language", systemImage: "globe")
                            }
                        }
                        .accessibilityIdentifier("settings.language")
                    } footer: {
                        Text("Genesis is available in English and Spanish. Tap to choose in the Settings app; Genesis restarts in the new language.")
                    }
                    .listRowBackground(palette.surface)
                    .foregroundStyle(palette.text)

                    Section {
                    } footer: {
                        Text("Theme, font and page turns are also in the reader under Aa.")
                    }
                }
            }
            .themedScreen()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("appSettings.done")
                }
            }
            .sheet(isPresented: $showsBibles) { BibleDownloadsView() }
            .sheet(isPresented: $showsAccount) { AccountView() }
            .sheet(isPresented: $showsReading) { ReaderSettingsSheet() }
            .sheet(isPresented: $showsListening) { AudioSettingsView() }
            .sheet(isPresented: $showsAmbient) { AmbientSoundsSheet() }
            .premiumSheet($premium)
        }
    }
}
