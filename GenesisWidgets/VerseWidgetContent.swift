import SwiftUI
import UIKit
import WidgetKit

// The verse widget's look, shared by the widget extension and the app (the
// Widget Styles previews in Settings), so a preview is the widget itself.
// The widget adds its container background and link (DailyVerseView); the
// previews draw the same backdrop behind the content themselves.

/// The verse itself, verbatim, set in a serif with room to breathe. Free
/// widgets follow light and dark; Premium ones the reading theme.
struct VerseWidgetContent: View {
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
        Text(ScriptureDirection.display(passage?.text ?? ""))
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
            Text(ScriptureDirection.display(passage?.text ?? ""))
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
            Text(ScriptureDirection.display(passage?.text ?? ""))
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

/// What goes behind the verse: the chosen background's picture or paper,
/// or the Classic colours. The widget sets it as its container background;
/// the app's Widget Styles previews draw it behind the same content.
struct VerseWidgetBackdrop: View {
    let art: WidgetArtStyle
    let colors: WidgetColors
    let family: WidgetFamily

    var body: some View {
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
