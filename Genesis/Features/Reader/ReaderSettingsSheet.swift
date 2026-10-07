import SwiftUI

/// "Aa" reading settings: theme, font, size, spacing, margins, brightness and layout.
struct ReaderSettingsSheet: View {
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var brightness: CGFloat = 0.5
    @State private var premium: PremiumFeature?
    @Environment(EntitlementService.self) private var entitlements
    @Environment(AmbientSoundService.self) private var ambient
    @Environment(FeaturePreferences.self) private var features
    @State private var showsAmbient = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                ThemedRows {
                    Section {
                        themePicker(selection: $settings.preferences.theme)
                            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))

                        HStack(spacing: 12) {
                            Image(systemName: "sun.min")
                            Slider(value: $brightness, in: 0...1)
                                .onChange(of: brightness) { DeviceScreen.brightness = brightness }
                                .accessibilityLabel("Brightness")
                            Image(systemName: "sun.max")
                        }
                        .foregroundStyle(palette.secondaryText)

                        if settings.preferences.theme.season != nil {
                            Toggle("Seasonal Touches", isOn: $settings.preferences.seasonalEffects)
                                .tint(palette.accent)
                                .accessibilityIdentifier("settings.seasonalEffects")
                        }
                    } footer: {
                        if settings.preferences.theme.season != nil {
                            Text("Leaves, snow, blossom or summer sunlight drift gently across the page while you read. Paused in Low Power Mode and not shown when Reduce Motion is on.")
                        }
                    }

                    if features.isOn(.ambientSounds) {
                        ambientSection
                    }

                    NightReadingSettings(premium: $premium)

                    Section("Text") {
                        NavigationLink {
                            FontList(selection: $settings.preferences.font, premium: $premium)
                        } label: {
                            // Without Premium the reader falls back from a Premium typeface.
                            let font = ReaderStyle.resolvedFont(settings.preferences.font, premium: entitlements.allows(.premiumThemes))
                            LabeledContent("Font") {
                                Text(font.title)
                                    .font(font.font(size: 17))
                            }
                        }

                        HStack {
                            Button {
                                settings.preferences.fontSize = max(ReaderPreferences.fontSizeRange.lowerBound, settings.preferences.fontSize - 1)
                            } label: {
                                Image(systemName: "textformat.size.smaller").frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .accessibilityLabel("Smaller text")
                            Divider()
                            Text("\(Int(settings.preferences.fontSize)) pt")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(palette.secondaryText)
                                .frame(minWidth: 56)
                            Divider()
                            Button {
                                settings.preferences.fontSize = min(ReaderPreferences.fontSizeRange.upperBound, settings.preferences.fontSize + 1)
                            } label: {
                                Image(systemName: "textformat.size.larger").frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .accessibilityLabel("Larger text")
                        }
                        .buttonStyle(.borderless)

                        labeledSlider(String(localized: "Line spacing"), value: $settings.preferences.lineSpacing, in: ReaderPreferences.lineSpacingRange)
                        labeledSlider(String(localized: "Paragraph spacing"), value: $settings.preferences.paragraphSpacing, in: ReaderPreferences.paragraphSpacingRange)

                        Picker("Margins", selection: $settings.preferences.margins) {
                            ForEach(ReaderMargins.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("Follow Dynamic Type", isOn: $settings.preferences.followsDynamicType)
                    }

                    Section("Layout") {
                        Picker("Reading mode", selection: $settings.preferences.readingMode) {
                            ForEach(ReadingMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        if settings.preferences.readingMode == .page {
                            Picker("Page turn", selection: Binding(
                                get: { settings.preferences.pageTurn },
                                set: {
                                    settings.preferences.pageTurn = $0
                                    settings.preferences.pageTurnChosen = true
                                }
                            )) {
                                ForEach(PageTurnStyle.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        Picker("Text", selection: $settings.preferences.layout) {
                            ForEach(TextLayout.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("Verse numbers", isOn: $settings.preferences.showsVerseNumbers)
                        Toggle("Large first letter", isOn: $settings.preferences.largeInitial)
                            .accessibilityIdentifier("settings.largeInitial")
                        if settings.preferences.largeInitial {
                            initialStylePicker(selection: $settings.preferences.initialStyle)
                        }
                        if settings.preferences.readingMode == .page {
                            PageTurnFeedbackSettings()
                        }
                        Toggle(isOn: $settings.preferences.leftHanded) {
                            Text("Left-handed mode")
                            Text("Tap the left edge to turn forward; study panel on the left.")
                        }
                    }

                    Section {
                        Button("Reset to Defaults", role: .destructive) { settings.reset() }
                    }
                }
            }
            .accessibilityIdentifier("settings.list")
            .themedScreen()
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { brightness = DeviceScreen.brightness }
            .premiumSheet($premium)
            .navigationDestination(isPresented: $showsAmbient) { AmbientSoundsView() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
    }

    /// A small mark on seasonal (and Starlight's) swatches.
    private static func seasonSymbol(_ theme: ReaderTheme) -> String? {
        switch theme {
        case .seasons: "calendar"
        case .autumn: "leaf.fill"
        case .winter: "snowflake"
        case .spring: "camera.macro"
        case .summer: "sun.max.fill"
        case .starlight: "sparkles"
        default: nil
        }
    }

    /// Ambient sounds (Premium), when the feature is switched on.
    private var ambientSection: some View {
        Section {
            Button {
                if entitlements.allows(.ambientSounds) {
                    showsAmbient = true
                } else {
                    premium = .ambientSounds
                }
            } label: {
                HStack {
                    Label("Ambient Sounds", systemImage: "speaker.wave.2")
                        .foregroundStyle(palette.text)
                    Spacer()
                    if !entitlements.allows(.ambientSounds) {
                        PremiumBadge()
                    } else if ambient.isPlaying {
                        Text(ambient.summary)
                            .lineLimit(1)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("settings.ambient")
        } footer: {
            Text("Rain, waves, a fire or birdsong while you read and pray.")
        }
    }

    private func themePicker(selection: Binding<ReaderTheme>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(ReaderTheme.allCases) { theme in
                    let isSelected = selection.wrappedValue == theme
                    let isLocked = !entitlements.allows(theme)
                    Button {
                        if isLocked {
                            premium = .premiumThemes
                        } else {
                            selection.wrappedValue = theme
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(theme == .automatic
                                        ? AnyShapeStyle(LinearGradient(colors: [ReaderTheme.paper.palette.background, ReaderTheme.slate.palette.background], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(theme.palette.background))
                                Text("Aa")
                                    .font(.system(size: 15, weight: .medium, design: .serif))
                                    .foregroundStyle(theme == .automatic ? ReaderTheme.paper.palette.text : theme.palette.text)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if let symbol = Self.seasonSymbol(theme) {
                                    Image(systemName: symbol)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(theme.palette.accent)
                                        .padding(3)
                                        .background(theme.palette.surface, in: Circle())
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(width: 48, height: 48)
                            .overlay(Circle().strokeBorder(isSelected ? palette.accent : palette.separator, lineWidth: isSelected ? 2.5 : 1))
                            .overlay(alignment: .topTrailing) {
                                if isLocked { PremiumBadge().padding(2).background(palette.background, in: Circle()) }
                            }
                            Text(theme.title)
                                .font(.caption2)
                                .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isLocked ? "\(theme.title) theme, Premium" : "\(theme.title) theme")
                    .accessibilityIdentifier("settings.theme.\(theme.rawValue)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
        }
    }

    /// Classic or Illuminated, beside "Large first letter". Illuminated is
    /// Premium: locked, it shows the badge and opens the Premium screen.
    private func initialStylePicker(selection: Binding<InitialStyle>) -> some View {
        let allowed = entitlements.allows(.premiumThemes)
        return HStack {
            Text("First letter style")
            Spacer()
            Menu {
                ForEach(InitialStyle.allCases) { style in
                    let isLocked = style.isPremium && !allowed
                    Button {
                        if isLocked {
                            premium = .premiumThemes
                        } else {
                            selection.wrappedValue = style
                        }
                    } label: {
                        if isLocked {
                            Label(style.title, systemImage: "lock.fill")
                        } else if selection.wrappedValue == style {
                            Label(style.title, systemImage: "checkmark")
                        } else {
                            Text(style.title)
                        }
                    }
                    .accessibilityIdentifier("settings.initialStyle.\(style.rawValue)")
                }
            } label: {
                HStack(spacing: 6) {
                    // Without Premium the reader shows the classic letter, so say so.
                    let shown = allowed ? selection.wrappedValue : .plain
                    Text(shown.title)
                        .foregroundStyle(palette.accent)
                    if !allowed { PremiumBadge() }
                }
            }
            .accessibilityIdentifier("settings.initialStyle")
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Slider(value: value, in: range)
                .accessibilityLabel(title)
        }
    }
}

private struct FontList: View {
    @Binding var selection: ReaderFont
    /// Set to open the Premium screen for a locked typeface.
    @Binding var premium: PremiumFeature?
    @Environment(\.palette) private var palette
    @Environment(EntitlementService.self) private var entitlements

    var body: some View {
        List(ReaderFont.allCases) { font in
            let isLocked = !entitlements.allows(font)
            Button {
                if isLocked {
                    premium = .premiumThemes
                } else {
                    selection = font
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(font.title)
                            .font(font.font(size: 20))
                            .foregroundStyle(palette.text)
                        Text(font.caption)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    if isLocked {
                        PremiumBadge()
                    } else if font == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(palette.accent)
                    }
                }
            }
            .accessibilityIdentifier("settings.font.\(font.rawValue)")
            .accessibilityAddTraits(font == selection ? .isSelected : [])
        }
        .themedScreen()
        .navigationTitle("Font")
    }
}
