import SwiftUI

/// App settings from Home: features, Bibles and account. Reading settings
/// live in the reader ("Aa").
struct SettingsView: View {
    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
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
                        NavigationLink {
                            NotificationSettingsView()
                        } label: {
                            Label("Notifications", systemImage: "bell.badge")
                        }
                        .accessibilityIdentifier("settings.notifications")
                        if features.isOn(.goals) {
                            NavigationLink {
                                GoalSettingsView()
                            } label: {
                                Label("Goals & Streaks", systemImage: "target")
                            }
                            .accessibilityIdentifier("settings.goals")
                        }
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
                        NavigationLink {
                            WidgetStylesView()
                        } label: {
                            Label("Widget Styles", systemImage: "rectangle.3.group")
                        }
                        .accessibilityIdentifier("settings.widgetStyles")
                        if entitlements.allows(.widgets) {
                            NavigationLink {
                                WidgetPhotoSettingsView()
                            } label: {
                                Label("Widget Photo", systemImage: "photo.on.rectangle")
                            }
                            .accessibilityIdentifier("settings.widgetPhoto")
                        } else {
                            Button {
                                premium = .widgets
                            } label: {
                                HStack {
                                    Label("Widget Photo", systemImage: "photo.on.rectangle")
                                    Spacer()
                                    PremiumBadge()
                                }
                            }
                            .accessibilityIdentifier("settings.widgetPhoto")
                        }
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

                    Section {
                        if let support = AppConfiguration.current.supportURL {
                            Link(destination: support) {
                                Label("Help & Support", systemImage: "questionmark.circle")
                            }
                            .accessibilityIdentifier("settings.support")
                        }
                        if let privacy = AppConfiguration.current.privacyURL {
                            Link(destination: privacy) {
                                Label("Privacy Policy", systemImage: "hand.raised")
                            }
                            .accessibilityIdentifier("settings.privacy")
                        }
                        Link(destination: AppConfiguration.current.termsURL) {
                            Label("Terms of Use", systemImage: "doc.text")
                        }
                        .accessibilityIdentifier("settings.terms")
                    } header: {
                        Text("About Versely")
                    } footer: {
                        Text("Version \(Self.version)")
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
                        NavigationLink {
                            LanguageSettingsView()
                        } label: {
                            LabeledContent {
                                Text(AppLanguage.displayName(AppLanguage.code))
                            } label: {
                                Label("Language", systemImage: "globe")
                            }
                        }
                        .accessibilityIdentifier("settings.language")
                    } footer: {
                        Text("Versely is available in English and Spanish.")
                    }
                    .listRowBackground(palette.surface)
                    .foregroundStyle(palette.text)

                    Section {
                    } footer: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Theme, font and page turns are also in the reader under Aa.")
                            // Asked by the YouVersion Platform's Terms, since
                            // Versely offers a subscription.
                            if library.offersYouVersionBibles {
                                Text("Bibles from the YouVersion Platform are always free in Versely. The YouVersion Bible App is free to download and use.")
                            }
                        }
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

    /// "1.0 (202611131200)": the version people see, then the build number.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(short) (\(build))"
    }
}
