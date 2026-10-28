import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration

/// The verse widget's options, as people pick them when editing the widget.
/// Mirrors `VerseWidgetSource` case for case (same raw values, which are
/// saved in installed widgets: never change them).
enum VerseWidgetOption: String, AppEnum, CaseIterable {
    case verseOfTheDay, random, fromYourReading
    case hope, peace, faith, strength, comfort, love, gratitude, guidance

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Verse")

    static let caseDisplayRepresentations: [VerseWidgetOption: DisplayRepresentation] = [
        .verseOfTheDay: DisplayRepresentation(title: "Verse of the Day"),
        .random: DisplayRepresentation(title: "Random Verse"),
        .fromYourReading: DisplayRepresentation(title: "From Your Reading"),
        .hope: DisplayRepresentation(title: "Hope"),
        .peace: DisplayRepresentation(title: "Peace"),
        .faith: DisplayRepresentation(title: "Faith"),
        .strength: DisplayRepresentation(title: "Strength"),
        .comfort: DisplayRepresentation(title: "Comfort"),
        .love: DisplayRepresentation(title: "Love"),
        .gratitude: DisplayRepresentation(title: "Gratitude"),
        .guidance: DisplayRepresentation(title: "Guidance"),
    ]

    var source: VerseWidgetSource { VerseWidgetSource(rawValue: rawValue) ?? .verseOfTheDay }
}

/// The verse widget's background, as people pick it when editing the
/// widget. Mirrors `WidgetArtStyle` (same raw values, saved in installed
/// widgets: never change them). Everything but Classic is Premium.
enum VerseWidgetBackground: String, AppEnum, CaseIterable {
    case classic, paper, autumn, winter, spring, summer, night, photo, vintage
    case instantPhoto, pressedFlowers, filmStrip, typewriter, libraryCard, calendarPage

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Background")

    static let caseDisplayRepresentations: [VerseWidgetBackground: DisplayRepresentation] = [
        .classic: DisplayRepresentation(title: "Classic"),
        .paper: DisplayRepresentation(title: "Paper"),
        .autumn: DisplayRepresentation(title: "Autumn"),
        .winter: DisplayRepresentation(title: "Winter"),
        .spring: DisplayRepresentation(title: "Spring"),
        .summer: DisplayRepresentation(title: "Summer"),
        .night: DisplayRepresentation(title: "Night"),
        .photo: DisplayRepresentation(title: "Your Photo"),
        .vintage: DisplayRepresentation(title: "Vintage"),
        .instantPhoto: DisplayRepresentation(title: "Instant Photo"),
        .pressedFlowers: DisplayRepresentation(title: "Pressed Flowers"),
        .filmStrip: DisplayRepresentation(title: "Film Strip"),
        .typewriter: DisplayRepresentation(title: "Typewriter"),
        .libraryCard: DisplayRepresentation(title: "Library Card"),
        .calendarPage: DisplayRepresentation(title: "Calendar Page"),
    ]

    var style: WidgetArtStyle { WidgetArtStyle(rawValue: rawValue) ?? .classic }
}

/// The verse widget's settings. Widgets installed before it existed have no
/// saved choice and get the default, the verse of the day, as before.
struct VerseWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Verse"
    static var description: IntentDescription { IntentDescription("Choose which verse the widget shows.") }

    @Parameter(title: "Show", default: .verseOfTheDay)
    var option: VerseWidgetOption

    /// Widgets installed before backgrounds existed keep the Classic look.
    @Parameter(title: "Background", default: .classic)
    var background: VerseWidgetBackground

    init() {}
}

// MARK: - Timeline

struct VerseEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let source: VerseWidgetSource
    var background: WidgetArtStyle = .classic
}

/// The verse of the day changes at midnight; Random Verse and the categories
/// every three hours (`VerseWidgetSchedule`).
struct VerseProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> VerseEntry {
        VerseEntry(date: .now, snapshot: .placeholder, source: .verseOfTheDay)
    }

    func snapshot(for configuration: VerseWidgetIntent, in context: Context) async -> VerseEntry {
        let snapshot = context.isPreview ? WidgetSnapshot.galleryPreview : (WidgetSnapshot.load() ?? .placeholder)
        return VerseEntry(date: .now, snapshot: snapshot, source: configuration.option.source, background: configuration.background.style)
    }

    func timeline(for configuration: VerseWidgetIntent, in context: Context) async -> Timeline<VerseEntry> {
        let snapshot = WidgetSnapshot.load() ?? .placeholder
        let source = configuration.option.source
        let background = configuration.background.style
        var dates = VerseWidgetSchedule.entryDates(rotates: source.rotates, from: .now)
        // Seasonal backgrounds drift on: a step every minute for an hour.
        if SeasonalDrift.moves(background) {
            dates = SeasonalDrift.entryDates(adding: dates, from: .now)
        }
        return Timeline(entries: dates.map { VerseEntry(date: $0, snapshot: snapshot, source: source, background: background) }, policy: .atEnd)
    }
}

// MARK: - Widget

/// Free at every size with Verse of the Day or Random Verse in the Classic
/// look; the categories, From Your Reading and the backgrounds are Premium.
/// A Premium choice without Premium shows the verse of the day in the
/// Classic look with a small Premium tag, never a locked card. The kind is
/// unchanged from the earlier static widget, so installed widgets carry on.
struct DailyVerseWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.dailyVerse.rawValue, intent: VerseWidgetIntent.self, provider: VerseProvider()) { entry in
            DailyVerseView(entry: entry)
        }
        .configurationDisplayName("Verse of the Day")
        .description("A new verse each morning, a random verse, or verses on hope, peace and more.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct DailyVerseView: View {
    let entry: VerseEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if art == .photo && WidgetArtImage.load(.photo, family: family) == nil {
            PremiumLockedView(message: String(localized: "Choose your photo in Versely: Settings › Widget Photo."), symbol: "photo.badge.plus")
        } else {
            VerseContentView(
                passage: entry.snapshot.passage(for: source, on: entry.date),
                title: title,
                colors: WidgetColors(entry.snapshot),
                family: family,
                art: art,
                date: entry.date,
                isVerseOfTheDay: source == .verseOfTheDay,
                showsPremiumTag: showsPremiumTag
            )
        }
    }

    private var isPremium: Bool { entry.snapshot.isPremium == true }

    /// The option shown: a Premium one without Premium falls back to the
    /// verse of the day (its verses aren't written without Premium).
    private var source: VerseWidgetSource {
        WidgetAccess.isUnlocked(entry.source, isPremium: isPremium) ? entry.source : .verseOfTheDay
    }

    /// The background shown: the Lock Screen's widgets have none, and a
    /// Premium one without Premium falls back to Classic.
    private var art: WidgetArtStyle {
        if WidgetSize(family).isAccessory { return .classic }
        return WidgetAccess.isUnlocked(entry.background, isPremium: isPremium) ? entry.background : .classic
    }

    /// A Premium option or background was chosen without Premium. The
    /// Lock Screen has no room for the tag; it just shows the free verse.
    private var showsPremiumTag: Bool {
        guard !WidgetSize(family).isAccessory else { return false }
        return source != entry.source || art != entry.background
    }

    /// The small capitals above the verse.
    private var title: String {
        switch source {
        case .verseOfTheDay: String(localized: "Verse of the Day")
        case .random: String(localized: "A Verse for You")
        case .fromYourReading: String(localized: "From Your Reading")
        case .hope: String(localized: "Hope")
        case .peace: String(localized: "Peace")
        case .faith: String(localized: "Faith")
        case .strength: String(localized: "Strength")
        case .comfort: String(localized: "Comfort")
        case .love: String(localized: "Love")
        case .gratitude: String(localized: "Gratitude")
        case .guidance: String(localized: "Guidance")
        }
    }
}

/// The verse itself, verbatim, set in a serif with room to breathe. Free
/// widgets follow light and dark; Premium ones the reading theme.
private struct VerseContentView: View {
    let passage: WidgetSnapshot.Passage?
    let title: String
    let colors: WidgetColors
    let family: WidgetFamily
    var art: WidgetArtStyle = .classic
    var date: Date = .now
    var isVerseOfTheDay = true
    /// The Classic look standing in for a Premium choice.
    var showsPremiumTag = false

    var body: some View {
        content
            .background {
                // Leaves, snow, petals or light drifting behind the words,
                // out to the widget's edges.
                if !WidgetSize(family).isAccessory, SeasonalDrift.moves(art) {
                    SeasonalMotionLayer(style: art, date: date)
                        .padding(-24)
                }
            }
            .containerBackground(for: .widget) {
                if WidgetSize(family).isAccessory {
                    Color.clear
                } else if art.isKeepsake {
                    KeepsakeBackground()
                } else if art == .vintage {
                    VintageBackground(showsStamp: family != .systemSmall)
                } else if art != .classic, let image = WidgetArtImage.load(art, family: family) {
                    WidgetArtBackground(image: image, style: art)
                } else {
                    WidgetBackground(colors: colors)
                }
            }
            .widgetURL(passage.map { GenesisLink.read($0.verse) })
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text(passage?.reference ?? title)
        case .accessoryRectangular:
            lockScreen
        default:
            if art.isKeepsake {
                KeepsakeWidgetView(style: art, passage: passage, title: title, family: family, date: date, isVerseOfTheDay: isVerseOfTheDay)
            } else if art == .vintage {
                vintage
            } else {
                homeScreen
            }
        }
    }

    /// The Lock Screen's rectangle is a fixed size set by iOS (half the
    /// width, two rows), so the reference stays small and the verse takes
    /// the room: the largest size that shows it whole, then smaller, and
    /// only a very long verse is cut short.
    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(passage?.reference ?? title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .widgetAccentable()
            ViewThatFits(in: .vertical) {
                lockScreenVerse(.caption, lines: nil)
                lockScreenVerse(.caption2, lines: nil)
                lockScreenVerse(.caption2, lines: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func lockScreenVerse(_ style: Font.TextStyle, lines: Int?) -> some View {
        Text(passage?.text ?? "")
            .font(.system(style, design: .serif))
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: lines == nil)
    }

    /// The postcard: a spaced, ruled eyebrow, the verse, an italic citation,
    /// and room on the right for the stamp (medium and large).
    private var vintage: some View {
        let ink = WidgetArtInk.colors(for: .vintage)
        // Clear of the stamp and its postmark lines (96 pt, 12 from the edge).
        let stampRoom: CGFloat = family == .systemSmall ? 0 : 100
        return VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
            HStack(spacing: 8) {
                // The heading keeps its full width; the rule takes what's left.
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(family == .systemSmall ? 1.2 : 2.2)
                    .foregroundStyle(ink.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                Rectangle()
                    .fill(ink.secondary.opacity(0.45))
                    .frame(minWidth: 0, maxHeight: 0.75)
            }
            .padding(.trailing, stampRoom)
            // The verse gets the room first, and shrinks rather than cuts off.
            Text(passage?.text ?? "")
                .font(.system(textStyle, design: .serif))
                .lineSpacing(family == .systemSmall ? 1 : 2)
                .foregroundStyle(ink.text)
                .minimumScaleFactor(0.5)
                .layoutPriority(1)
                .padding(.trailing, stampRoom)
            Spacer(minLength: 0)
            Text(vintageCitation)
                .font(.system(.caption, design: .serif).italic())
                .foregroundStyle(ink.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Matthew 11:28 — KJV"
    private var vintageCitation: String {
        guard let passage else { return "" }
        return passage.reference + " \u{2014} " + passage.translation
    }

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
            Eyebrow(text: title, color: ink.accent)
            Text(passage?.text ?? "")
                .font(.system(textStyle, design: .serif))
                .lineSpacing(family == .systemSmall ? 1 : 3)
                .foregroundStyle(ink.text)
                .minimumScaleFactor(0.5)
                .layoutPriority(1)
                .shadow(color: art.isDark ? .black.opacity(0.35) : .clear, radius: 3, y: 1)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text(citation)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
                if showsPremiumTag {
                    Spacer(minLength: 0)
                    PremiumTag(isCompact: family == .systemSmall, color: ink.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The theme's colours, or ones chosen for the background's art.
    private var ink: (text: Color, secondary: Color, accent: Color) {
        if art == .vintage || art.isKeepsake { return WidgetArtInk.colors(for: art) }
        if art == .classic || WidgetArtImage.load(art, family: family) == nil {
            return (colors.text, colors.secondary, colors.accent)
        }
        return WidgetArtInk.colors(for: art)
    }

    private var textStyle: Font.TextStyle {
        switch family {
        case .systemSmall: .footnote
        case .systemLarge, .systemExtraLarge: .title3
        default: .body
        }
    }

    /// "Psalms 23:1 · KJV"
    private var citation: String {
        guard let passage else { return "" }
        return passage.reference + " \u{00B7} " + passage.translation
    }
}

// MARK: - Backgrounds with pictures

/// The background picture for a widget size, from the App Group (drawn by
/// the app, or the person's photo).
enum WidgetArtImage {
    static func shape(for family: WidgetFamily) -> WidgetArtShape {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        default: .large
        }
    }

    static func load(_ style: WidgetArtStyle, family: WidgetFamily) -> UIImage? {
        WidgetArt.url(style, shape: shape(for: family)).flatMap { UIImage(contentsOfFile: $0.path) }
    }
}

/// The picture filling the widget; a photo gets a soft shade, darker toward
/// the bottom, so white words read on any photo.
private struct WidgetArtBackground: View {
    let image: UIImage
    let style: WidgetArtStyle

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
            if style == .photo {
                LinearGradient(colors: [.black.opacity(0.28), .black.opacity(0.42), .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Ink for each background: the season's own colours on the light art,
/// white and soft gold on the night sky and photos.
enum WidgetArtInk {
    static func colors(for style: WidgetArtStyle) -> (text: Color, secondary: Color, accent: Color) {
        switch style {
        case .night, .photo:
            (.white, .white.opacity(0.78), Color(light: 0xE8D3A2, dark: 0xE8D3A2))
        case .autumn:
            (Color(light: 0x36291F, dark: 0x36291F), Color(light: 0x80695A, dark: 0x80695A), Color(light: 0xA65F34, dark: 0xA65F34))
        case .winter:
            (Color(light: 0x262C33, dark: 0x262C33), Color(light: 0x6E7782, dark: 0x6E7782), Color(light: 0x5D7A8E, dark: 0x5D7A8E))
        case .spring:
            (Color(light: 0x2F2A2B, dark: 0x2F2A2B), Color(light: 0x7C7072, dark: 0x7C7072), Color(light: 0xA86F7E, dark: 0xA86F7E))
        case .summer:
            (Color(light: 0x2C2B25, dark: 0x2C2B25), Color(light: 0x76725F, dark: 0x76725F), Color(light: 0x4E8481, dark: 0x4E8481))
        case .vintage:
            (Color(light: 0x2E2A26, dark: 0x2E2A26), Color(light: 0x6F675C, dark: 0x6F675C), Color(light: 0x9B2C2C, dark: 0x9B2C2C))
        case .instantPhoto, .pressedFlowers, .filmStrip, .typewriter, .libraryCard, .calendarPage:
            (Color(light: 0x5D5B55, dark: 0x5D5B55), Color(light: 0x80825B, dark: 0x80825B), Color(light: 0x80825B, dark: 0x80825B))
        case .paper, .classic:
            (Color(light: 0x2B2A27, dark: 0x2B2A27), Color(light: 0x7D776B, dark: 0x7D776B), Color(light: 0xA8844E, dark: 0xA8844E))
        }
    }
}

// MARK: - Vintage postcard

/// Cream card stock with a fine grain, and (medium and large) a stamp with a
/// postmark in the top corner. Drawn the same way every time.
private struct VintageBackground: View {
    let showsStamp: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(light: 0xF6F1E7, dark: 0xF6F1E7)
            Canvas { context, size in
                // Grain.
                var seed: UInt64 = 0x5EED
                func next() -> CGFloat {
                    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    return CGFloat(seed >> 11) / CGFloat(UInt64(1) << 53)
                }
                for _ in 0..<Int(size.width * size.height / 28) {
                    let r = 0.3 + next() * 0.5
                    let rect = CGRect(x: next() * size.width - r, y: next() * size.height - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.4, green: 0.33, blue: 0.24).opacity(0.04 + next() * 0.04)))
                }
            }
            if showsStamp {
                VintageStamp()
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A blank stamp with perforated edges, slightly turned, a round postmark
/// over its corner and wavy cancellation lines beside it.
private struct VintageStamp: View {
    var body: some View {
        Canvas { context, size in
            let stamp = CGRect(x: 18, y: 4, width: 58, height: 70)
            let ink = Color(red: 0.42, green: 0.40, blue: 0.38)
            var turned = context
            turned.translateBy(x: stamp.midX, y: stamp.midY)
            turned.rotate(by: .degrees(4))
            turned.translateBy(x: -stamp.midX, y: -stamp.midY)
            // Shadow, paper and perforations.
            turned.fill(Path(stamp.offsetBy(dx: 1, dy: 1.5)), with: .color(.black.opacity(0.08)))
            turned.fill(Path(stamp), with: .color(Color(red: 0.99, green: 0.98, blue: 0.95)))
            let hole: CGFloat = 2.2
            var holes = Path()
            var x = stamp.minX
            while x <= stamp.maxX {
                holes.addEllipse(in: CGRect(x: x - hole, y: stamp.minY - hole, width: hole * 2, height: hole * 2))
                holes.addEllipse(in: CGRect(x: x - hole, y: stamp.maxY - hole, width: hole * 2, height: hole * 2))
                x += 6
            }
            var y = stamp.minY
            while y <= stamp.maxY {
                holes.addEllipse(in: CGRect(x: stamp.minX - hole, y: y - hole, width: hole * 2, height: hole * 2))
                holes.addEllipse(in: CGRect(x: stamp.maxX - hole, y: y - hole, width: hole * 2, height: hole * 2))
                y += 6
            }
            turned.fill(holes, with: .color(Color(red: 0.965, green: 0.945, blue: 0.906)))
            turned.stroke(Path(stamp.insetBy(dx: 5, dy: 5)), with: .color(ink.opacity(0.25)), lineWidth: 0.6)
            // Postmark.
            let center = CGPoint(x: stamp.maxX - 4, y: stamp.maxY - 6)
            for radius in [17.0, 12.5] {
                context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(ink.opacity(0.55)), lineWidth: 1)
            }
            var bars = Path()
            for row in 0..<3 {
                let rowY = center.y - 5 + CGFloat(row) * 5
                bars.move(to: CGPoint(x: center.x - 9, y: rowY))
                bars.addLine(to: CGPoint(x: center.x + 9, y: rowY))
            }
            context.stroke(bars, with: .color(ink.opacity(0.4)), lineWidth: 0.8)
            // Wavy cancellation lines to the left.
            for row in 0..<4 {
                var wave = Path()
                let baseY = stamp.maxY - 26 + CGFloat(row) * 6
                wave.move(to: CGPoint(x: 0, y: baseY))
                var waveX: CGFloat = 0
                while waveX < stamp.minX + 14 {
                    wave.addQuadCurve(to: CGPoint(x: waveX + 8, y: baseY), control: CGPoint(x: waveX + 4, y: baseY + (Int(waveX / 8) % 2 == 0 ? -2.5 : 2.5)))
                    waveX += 8
                }
                context.stroke(wave, with: .color(ink.opacity(0.5)), lineWidth: 0.9)
            }
        }
        .frame(width: 96, height: 96)
    }
}
