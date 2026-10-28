import SwiftUI
import WidgetKit

/// Settings › Widget Styles: every look the verse widget can wear, each
/// previewed with today's verse as the widget itself draws it
/// (`VerseWidgetContent`, shared with the widget extension). The choice goes
/// to every verse widget whose Background is "Chosen in Versely" (the
/// default). Anyone can look; Premium styles carry a badge and open the
/// Premium screen.
struct WidgetStylesView: View {
    @Environment(\.palette) private var palette
    @Environment(EntitlementService.self) private var entitlements
    @Environment(ReaderSettings.self) private var settings
    @State private var chosen = WidgetStylePreference.current()
    @State private var shape: WidgetArtShape = .medium
    @State private var premium: PremiumFeature?
    @State private var choosingPhoto = false
    /// Today's verse as the widgets have it (verbatim), if the app has
    /// written it yet.
    @State private var passage = WidgetSnapshot.load()?.dailyPassage(on: .now)

    private var isPremium: Bool { entitlements.allows(.widgets) }

    /// Premium widgets wear the reading theme; free ones the brand's look.
    private var colors: WidgetColors {
        WidgetColors(isPremium: isPremium, theme: isPremium ? WidgetSnapshotWriter.widgetTheme(for: settings.preferences.theme) : nil)
    }

    var body: some View {
        List {
            ThemedRows {
                Section {
                    Picker("Widget size", selection: $shape) {
                        Text("Small").tag(WidgetArtShape.small)
                        Text("Medium").tag(WidgetArtShape.medium)
                        Text("Large").tag(WidgetArtShape.large)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("widgetStyles.size")
                } footer: {
                    Text("Your verse widgets use the style you choose here. To give one widget its own look, touch and hold it, tap Edit Widget and choose a Background.")
                }
                .listRowBackground(palette.surface)
                Section {
                    ForEach(WidgetArtStyle.galleryOrder, id: \.self) { style in
                        row(style)
                    }
                }
                .listRowBackground(palette.surface)
                .foregroundStyle(palette.text)
            }
        }
        .themedScreen()
        .navigationTitle("Widget Styles")
        .navigationBarTitleDisplayMode(.inline)
        .premiumSheet($premium)
        .navigationDestination(isPresented: $choosingPhoto) {
            WidgetPhotoSettingsView()
        }
        .onAppear {
            // The painted backgrounds the previews (and widgets) show.
            WidgetArtWriter.drawIfNeeded()
        }
    }

    private func row(_ style: WidgetArtStyle) -> some View {
        let locked = !WidgetAccess.isUnlocked(style, isPremium: isPremium)
        let selected = style == chosen && !locked
        return Button {
            choose(style, locked: locked)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                WidgetStylePreview(style: style, shape: shape, passage: passage, colors: colors)
                HStack {
                    Text(style.title)
                    Spacer()
                    if locked {
                        PremiumBadge()
                    } else if selected {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(palette.accent)
                            .transition(.opacity)
                    }
                }
                if style == .photo && !locked && WidgetArtWriter.photo == nil {
                    Text("Choose a photo to use this style.")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("widgetStyles.\(style.rawValue)")
    }

    private func choose(_ style: WidgetArtStyle, locked: Bool) {
        guard !locked else {
            premium = .widgets
            return
        }
        withAnimation(Motion.easeOut(0.2)) { chosen = style }
        WidgetSnapshotWriter.publishVerseStyle(style)
        if style == .photo && WidgetArtWriter.photo == nil {
            choosingPhoto = true
        }
    }
}

/// One style at one widget size: the widget's own content over its own
/// background, at the size of an iPhone widget (smaller if the row is
/// narrower).
struct WidgetStylePreview: View {
    let style: WidgetArtStyle
    let shape: WidgetArtShape
    let passage: WidgetSnapshot.Passage?
    let colors: WidgetColors

    var body: some View {
        let size = shape.pointSize
        GeometryReader { proxy in
            let scale = min(1, proxy.size.width / size.width)
            widget
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .frame(maxWidth: size.width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preview of the \(style.title) style"))
    }

    private var widget: some View {
        VerseWidgetContent(
            passage: passage,
            title: String(localized: "Verse of the Day"),
            colors: colors,
            family: shape.family,
            art: style,
            date: .now,
            isVerseOfTheDay: true
        )
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            VerseWidgetBackdrop(art: style, colors: colors, family: shape.family)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}

private extension WidgetArtShape {
    var family: WidgetFamily {
        switch self {
        case .small: .systemSmall
        case .medium: .systemMedium
        case .large: .systemLarge
        }
    }

    /// A 6.1-inch iPhone's widget sizes, in points.
    var pointSize: CGSize {
        switch self {
        case .small: CGSize(width: 158, height: 158)
        case .medium: CGSize(width: 338, height: 158)
        case .large: CGSize(width: 338, height: 354)
        }
    }
}
