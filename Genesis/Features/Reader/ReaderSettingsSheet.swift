import SwiftUI

/// "Aa" reading settings: theme, font, size, spacing, margins, brightness and layout.
struct ReaderSettingsSheet: View {
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var brightness: CGFloat = 0.5

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
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
                }

                Section("Text") {
                    NavigationLink {
                        FontList(selection: $settings.preferences.font)
                    } label: {
                        LabeledContent("Font") {
                            Text(settings.preferences.font.title)
                                .font(settings.preferences.font.font(size: 17))
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

                    labeledSlider("Line spacing", value: $settings.preferences.lineSpacing, in: ReaderPreferences.lineSpacingRange)
                    labeledSlider("Paragraph spacing", value: $settings.preferences.paragraphSpacing, in: ReaderPreferences.paragraphSpacingRange)

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
                    Toggle(isOn: $settings.preferences.leftHanded) {
                        Text("Left-handed mode")
                        Text("Tap the left edge to turn forward; study panel on the left.")
                    }
                }

                Section {
                    Button("Reset to Defaults", role: .destructive) { settings.reset() }
                }
            }
            .themedScreen()
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { brightness = DeviceScreen.brightness }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
    }

    private func themePicker(selection: Binding<ReaderTheme>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(ReaderTheme.allCases) { theme in
                    let isSelected = selection.wrappedValue == theme
                    Button {
                        selection.wrappedValue = theme
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
                            .frame(width: 48, height: 48)
                            .overlay(Circle().strokeBorder(isSelected ? palette.accent : palette.separator, lineWidth: isSelected ? 2.5 : 1))
                            Text(theme.title)
                                .font(.caption2)
                                .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(theme.title) theme")
                    .accessibilityIdentifier("settings.theme.\(theme.rawValue)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
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
    @Environment(\.palette) private var palette

    var body: some View {
        List(ReaderFont.allCases) { font in
            Button {
                selection = font
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
                    if font == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(palette.accent)
                    }
                }
            }
            .accessibilityAddTraits(font == selection ? .isSelected : [])
        }
        .themedScreen()
        .navigationTitle("Font")
    }
}
