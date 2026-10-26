import SwiftUI
import WidgetKit

// The keepsake verse widgets, after the owner's light Canva mockups: soft
// linen, cream cards, sage and terracotta type. Each is a Background on the
// verse widget (Premium). Medium: a text card beside a picture card. Large:
// the picture on top, the text below. Small: the whole verse when it fits,
// otherwise the reference (tapping opens the verse). Every verse is drawn
// here, verbatim, never baked into a picture.
//
// Pictures come from the widget bundle (`KeepsakeImage`, built by
// Tools/WidgetArt/make_keepsake.py from images the owner generated with
// Canva's AI or ChatGPT and owns; never Canva library content) or the
// person's own photo; anything missing is drawn instead, so the widget
// always works.

// MARK: - Palette and type

enum Keepsake {
    static let linen = Color(light: 0xEEE8DE, dark: 0xEEE8DE)
    static let card = Color(light: 0xF7F2E9, dark: 0xF7F2E9)
    static let sage = Color(light: 0x80825B, dark: 0x80825B)
    static let body = Color(light: 0x5D5B55, dark: 0x5D5B55)
    static let ink = Color(light: 0x3D3B36, dark: 0x3D3B36)
    static let terracotta = Color(light: 0xC17C62, dark: 0xC17C62)
    static let fadedRed = Color(light: 0xD48670, dark: 0xD48670)
    static let ruleRed = Color(light: 0xE2A59A, dark: 0xE2A59A)
    static let ruleBlue = Color(light: 0xC9DCEB, dark: 0xC9DCEB)
    static let amber = Color(light: 0xD8A56D, dark: 0xD8A56D)

    /// EB Garamond, bundled with the widgets (UIAppFonts).
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? "EBGaramond-Italic" : "EBGaramond-Regular", size: size)
    }

    /// The iPhone's own typewriter face.
    static func typewriter(_ size: CGFloat) -> Font {
        .custom("AmericanTypewriter", size: size)
    }
}

/// The bundled pictures (JPEG in the widget extension).
enum KeepsakeImage: String {
    case flowers = "keepsake-flowers"
    case sprigs = "keepsake-sprigs"
    case beach = "keepsake-beach"
    case typewriter = "keepsake-typewriter"
    case linen = "keepsake-linen"
    case meadow = "keepsake-meadow"
    case paper = "keepsake-paper"
    /// A blank tear-off calendar pad, cut to the pad; the date is written on it.
    case pad = "keepsake-pad"
    /// An empty library card pocket, cut to the pocket; the date is stamped on it.
    case pocket = "keepsake-pocket"

    var image: UIImage? {
        Bundle.main.path(forResource: rawValue, ofType: "jpg").flatMap(UIImage.init(contentsOfFile:))
    }
}

/// Cream paper behind a text card, lightened toward white; flat colour
/// until the picture is bundled.
struct KeepsakePaper: View {
    var lighten: Double = 0
    var fallback: Color = Keepsake.card

    var body: some View {
        if let paper = KeepsakeImage.paper.image {
            Image(uiImage: paper)
                .resizable()
                .scaledToFill()
                .overlay(Color.white.opacity(lighten))
        } else {
            fallback
        }
    }
}

/// Linen behind everything.
struct KeepsakeBackground: View {
    var body: some View {
        if let linen = KeepsakeImage.linen.image {
            Image(uiImage: linen).resizable().scaledToFill()
        } else {
            Keepsake.linen
        }
    }
}

// MARK: - The widget

struct KeepsakeWidgetView: View {
    let style: WidgetArtStyle
    let passage: WidgetSnapshot.Passage?
    let title: String
    let family: WidgetFamily
    let date: Date
    let isVerseOfTheDay: Bool

    var body: some View {
        switch family {
        case .systemSmall:
            small
        case .systemMedium:
            HStack(spacing: 8) {
                textCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                pictureCard
                    .frame(width: 118)
            }
        default:
            VStack(spacing: 8) {
                pictureCard
                    .frame(maxWidth: .infinity)
                    .frame(height: 168)
                textCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Small

    /// The picture styles show their picture with the reference (tapping
    /// opens the verse); the paper styles show the whole verse when it
    /// fits, otherwise the picture with the reference.
    @ViewBuilder
    private var small: some View {
        switch style {
        case .instantPhoto:
            InstantPrint(photo: photo ?? KeepsakeImage.beach.image, caption: passage?.reference)
        case .pressedFlowers, .filmStrip:
            smallPicture
        default:
            ViewThatFits(in: .vertical) {
                textCard
                smallPicture
            }
        }
    }

    private var smallPicture: some View {
        pictureCard
            .overlay(alignment: .bottomLeading) {
                Text(passage?.reference ?? title)
                    .font(Keepsake.serif(13))
                    .foregroundStyle(Keepsake.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Keepsake.card.opacity(0.92), in: Capsule())
                    .padding(8)
            }
    }

    // MARK: Text cards

    @ViewBuilder
    private var textCard: some View {
        switch style {
        case .filmStrip: filmText
        case .typewriter: typewriterText
        case .libraryCard: libraryText
        case .calendarPage: calendarText
        default: plainText
        }
    }

    private var verseSize: CGFloat {
        switch family {
        case .systemSmall: 12.5
        case .systemMedium: 14.5
        default: 16
        }
    }

    /// Instant Photo and Pressed Flowers: heading, a short rule, the verse.
    private var plainText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(style == .pressedFlowers ? title : title.uppercased())
                .font(Keepsake.serif(style == .pressedFlowers ? 21 : 15))
                .foregroundStyle(Keepsake.sage)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Rectangle().fill(Keepsake.sage.opacity(0.4)).frame(width: 34, height: 0.75)
            Text(passage?.text ?? "")
                .font(Keepsake.serif(verseSize, italic: style == .instantPhoto))
                .foregroundStyle(Keepsake.body)
                .lineSpacing(1.5)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            reference(Keepsake.sage)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Keepsake.card.opacity(0.9), in: card)
    }

    /// Film Strip: the text in a pale frame with sprocket holes.
    private var filmText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(passage?.text ?? "")
                .font(Keepsake.serif(verseSize + 1))
                .foregroundStyle(Keepsake.sage)
                .lineSpacing(2)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            reference(Keepsake.sage)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { FilmFrame(edgeMark: "11A \u{25B8}", frameMark: "12") }
        .clipShape(card)
    }

    /// Typewriter: white paper, a gold paperclip, typed words.
    private var typewriterText: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Small: just the typed verse, so it has room.
            if family != .systemSmall {
                Text(title.uppercased())
                    .font(Keepsake.serif(14))
                    .foregroundStyle(Keepsake.sage)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.trailing, 20)
                Rectangle().fill(Keepsake.sage.opacity(0.4)).frame(width: 34, height: 0.75)
            }
            Text(passage?.text ?? "")
                .font(Keepsake.typewriter(verseSize - 1))
                .foregroundStyle(Keepsake.ink)
                .lineSpacing(2)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            reference(Keepsake.fadedRed)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            KeepsakePaper(lighten: 0.55, fallback: Color(light: 0xFCFBF8, dark: 0xFCFBF8))
                .clipShape(card)
        }
        .overlay(alignment: .topTrailing) {
            Paperclip()
                .frame(width: 14, height: 40)
                .rotationEffect(.degrees(8))
                .offset(x: -14, y: -6)
        }
    }

    /// Library Card: ruled lines, a red rule under the heading, a margin line.
    private var libraryText: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isVerseOfTheDay ? String(localized: "Due for Today") : title)
                .font(Keepsake.serif(family == .systemSmall ? 15 : 18))
                .foregroundStyle(Keepsake.sage)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 26, alignment: .bottomLeading)
                .padding(.leading, 12)
            Text(passage?.text ?? "")
                .font(Keepsake.serif(verseSize - 0.5))
                .foregroundStyle(Keepsake.body)
                .lineSpacing(18 - (verseSize - 0.5) * 1.2)
                .minimumScaleFactor(0.6)
                .padding(.leading, 22)
                .padding(.trailing, 10)
                .padding(.top, 6)
            Spacer(minLength: 0)
            reference(Keepsake.sage)
                .padding(.leading, 22)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                KeepsakePaper(lighten: 0.4, fallback: Color(red: 0.98, green: 0.97, blue: 0.94))
                RuledLines()
            }
        }
        .clipShape(card)
    }

    /// Calendar Page: month, the day in terracotta, weekday, the verse.
    private var calendarText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date.formatted(.dateTime.month(.wide)).uppercased())
                .font(Keepsake.serif(13))
                .foregroundStyle(Keepsake.sage)
            Text(date.formatted(.dateTime.day()))
                .font(Keepsake.serif(family == .systemSmall ? 34 : 40))
                .foregroundStyle(Keepsake.terracotta)
                .frame(height: family == .systemSmall ? 36 : 42)
            Text(date.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(Keepsake.serif(12))
                .foregroundStyle(Keepsake.sage)
                .padding(.bottom, 3)
            Text(passage?.text ?? "")
                .font(Keepsake.serif(verseSize - 1.5))
                .foregroundStyle(Keepsake.body)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            reference(Keepsake.sage)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { KeepsakePaper(lighten: 0.3).clipShape(card) }
    }

    private func reference(_ color: Color) -> some View {
        Text(citation)
            .font(style == .typewriter ? Keepsake.typewriter(10.5) : Keepsake.serif(12))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// "Psalm 118:24 — KJV"; the small widget keeps just the reference.
    private var citation: String {
        guard let passage else { return "" }
        if family == .systemSmall { return passage.reference }
        return passage.reference + " \u{2014} " + passage.translation
    }

    // MARK: Picture cards

    @ViewBuilder
    private var pictureCard: some View {
        switch style {
        case .instantPhoto:
            InstantPrint(photo: photo ?? KeepsakeImage.beach.image)
        case .pressedFlowers:
            picture(KeepsakeImage.flowers.image)
        case .filmStrip:
            FilmFrame(edgeMark: "12", frameMark: "12A", photo: photo ?? KeepsakeImage.meadow.image ?? KeepsakeImage.beach.image)
                .clipShape(card)
        case .typewriter:
            // The machine itself in the wide large widget; baby's breath elsewhere.
            if family == .systemLarge {
                picture(KeepsakeImage.typewriter.image, alignment: .bottom)
            } else {
                picture(KeepsakeImage.sprigs.image)
            }
        case .libraryCard:
            if let pocket = KeepsakeImage.pocket.image {
                // The stamp on the pocket's front, below the card's tab.
                PhotoWithMark(image: pocket, markCenter: UnitPoint(x: 0.5, y: 0.6)) {
                    RubberStampMark(date: date, size: family == .systemSmall ? 13 : 15)
                }
                .background { KeepsakePaper().clipShape(card) }
                .clipShape(card)
            } else {
                RubberStampMark(date: date)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Keepsake.card.opacity(0.9), in: card)
            }
        default:
            if let pad = KeepsakeImage.pad.image {
                // Today's date on the pad's blank page, below the torn edge.
                PhotoWithMark(image: pad, markCenter: UnitPoint(x: 0.48, y: 0.55)) {
                    CalendarDate(date: date, scale: family == .systemSmall ? 0.85 : 1)
                }
                .background(Keepsake.linen)
                .clipShape(card)
            } else {
                TearOffPage(date: date)
            }
        }
    }

    /// The person's photo (Settings › Widget Photo), if they chose one.
    private var photo: UIImage? {
        WidgetArtImage.load(.photo, family: family)
    }

    private func picture(_ image: UIImage?, alignment: Alignment = .center) -> some View {
        Keepsake.card
            .overlay(alignment: alignment) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(card)
    }

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: family == .systemSmall ? 14 : 16, style: .continuous)
    }
}

// MARK: - Drawn pieces

/// A white instant print, slightly turned, with a wide bottom border.
private struct InstantPrint: View {
    let photo: UIImage?
    /// Written on the wide bottom border (the small widget's reference).
    var caption: String? = nil

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height / 1.17) * 0.92
            VStack(spacing: 0) {
                ZStack {
                    LinearGradient(colors: [Color(light: 0xDCE6EC, dark: 0xDCE6EC), Color(light: 0xF2E7D3, dark: 0xF2E7D3)], startPoint: .top, endPoint: .bottom)
                    if let photo { Image(uiImage: photo).resizable().scaledToFill() }
                }
                .frame(width: side - 12, height: side - 12)
                .clipped()
                .padding(.top, 6)
                if let caption {
                    Text(caption)
                        .font(Keepsake.serif(side * 0.09, italic: true))
                        .foregroundStyle(Keepsake.body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                        .frame(maxHeight: .infinity)
                }
                Spacer(minLength: 0)
            }
            .frame(width: side, height: side * 1.17)
            .background(Color(light: 0xFDFCF9, dark: 0xFDFCF9))
            .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
            .rotationEffect(.degrees(-3))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// A pale film frame: sprocket holes along the top and bottom, amber edge
/// numbers, and a photo in the middle when there is one.
private struct FilmFrame: View {
    let edgeMark: String
    let frameMark: String
    var photo: UIImage? = nil

    var body: some View {
        ZStack {
            Color(light: 0xF4EEE3, dark: 0xF4EEE3)
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .padding(.vertical, 18)
                    .padding(.horizontal, 4)
                    .clipped()
            }
            VStack {
                holes
                Spacer()
                holes
            }
            .padding(.vertical, 4)
            VStack {
                HStack {
                    Text(verbatim: edgeMark)
                    Spacer()
                    Text(verbatim: frameMark)
                }
                Spacer()
            }
            .font(.system(size: 6.5, weight: .semibold))
            .foregroundStyle(Keepsake.amber.opacity(0.8))
            .padding(.horizontal, 6)
            .padding(.top, 1)
        }
        .accessibilityHidden(true)
    }

    private var holes: some View {
        GeometryReader { proxy in
            let count = max(4, Int(proxy.size.width / 17))
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(light: 0xE6DCCB, dark: 0xE6DCCB))
                        .frame(width: 7, height: 8)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 8)
    }
}

/// Ruled index card lines: blue rules, a red rule under the heading, a red margin.
private struct RuledLines: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 50
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.75)), with: .color(Keepsake.ruleBlue))
                y += 18
            }
            context.fill(Path(CGRect(x: 0, y: 31, width: size.width, height: 1)), with: .color(Keepsake.ruleRed))
            context.fill(Path(CGRect(x: 15, y: 31, width: 0.75, height: size.height)), with: .color(Keepsake.ruleRed.opacity(0.7)))
        }
        .accessibilityHidden(true)
    }
}

/// A faded red date stamp, slightly turned.
private struct RubberStampMark: View {
    let date: Date
    var size: CGFloat = 15

    var body: some View {
        Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
            .font(Keepsake.serif(size))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Keepsake.fadedRed.opacity(0.85))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Keepsake.fadedRed.opacity(0.75), lineWidth: 1.5))
            .rotationEffect(.degrees(-9))
            .accessibilityHidden(true)
    }
}

/// A picture shown whole (fitted, centred) with something written on it at
/// a point given as a fraction of the picture, so it stays on the paper
/// whatever the widget's size.
private struct PhotoWithMark<Mark: View>: View {
    let image: UIImage
    let markCenter: UnitPoint
    @ViewBuilder var mark: Mark

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    mark.position(x: proxy.size.width * markCenter.x, y: proxy.size.height * markCenter.y)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

/// Month, day and weekday as printed on a calendar page.
private struct CalendarDate: View {
    let date: Date
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 1 * scale) {
            Text(date.formatted(.dateTime.month(.wide)).uppercased())
                .font(Keepsake.serif(10 * scale, italic: true))
                .foregroundStyle(Keepsake.sage)
            Text(date.formatted(.dateTime.day()))
                .font(Keepsake.serif(36 * scale))
                .foregroundStyle(Keepsake.terracotta)
            Rectangle().fill(Keepsake.sage.opacity(0.35)).frame(width: 40 * scale, height: 0.75)
            Text(date.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(Keepsake.serif(9 * scale))
                .foregroundStyle(Keepsake.sage)
                .padding(.top, 2 * scale)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// A tear-off calendar page: torn top edge, two binding holes, the date.
private struct TearOffPage: View {
    let date: Date

    var body: some View {
        VStack(spacing: 1) {
            Text(date.formatted(.dateTime.month(.wide)).uppercased())
                .font(Keepsake.serif(10, italic: true))
                .foregroundStyle(Keepsake.sage)
            Text(date.formatted(.dateTime.day()))
                .font(Keepsake.serif(38))
                .foregroundStyle(Keepsake.terracotta)
            Rectangle().fill(Keepsake.sage.opacity(0.35)).frame(width: 46, height: 0.75)
            Text(date.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(Keepsake.serif(9))
                .foregroundStyle(Keepsake.sage)
                .padding(.top, 2)
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            TornPage()
                .fill(Color(light: 0xFBF8F2, dark: 0xFBF8F2))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
        }
        .overlay(alignment: .top) {
            HStack(spacing: 36) {
                Circle().fill(Keepsake.body.opacity(0.5)).frame(width: 4, height: 4)
                Circle().fill(Keepsake.body.opacity(0.5)).frame(width: 4, height: 4)
            }
            .padding(.top, 9)
        }
        .rotationEffect(.degrees(2))
        .padding(6)
        .accessibilityHidden(true)
    }
}

/// A rectangle whose top edge is torn: small irregular zigzags.
private struct TornPage: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let teeth = 18
        let step = rect.width / CGFloat(teeth)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 4))
        for i in 0..<teeth {
            let x = rect.minX + CGFloat(i) * step
            let dip: CGFloat = [2.5, 0.5, 3.5, 1.5, 2.8, 0.8][i % 6]
            path.addLine(to: CGPoint(x: x + step / 2, y: rect.minY + dip))
            path.addLine(to: CGPoint(x: x + step, y: rect.minY + 4 - dip / 2))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A gold paperclip: one wire, three loops.
private struct Paperclip: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var path = Path()
            path.move(to: CGPoint(x: w * 0.15, y: h * 0.75))
            path.addLine(to: CGPoint(x: w * 0.15, y: w * 0.45))
            path.addArc(center: CGPoint(x: w * 0.5, y: w * 0.45), radius: w * 0.35, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: w * 0.85, y: h - w * 0.4))
            path.addArc(center: CGPoint(x: w * 0.55, y: h - w * 0.4), radius: w * 0.3, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: w * 0.25, y: h * 0.3))
            path.addArc(center: CGPoint(x: w * 0.45, y: h * 0.3), radius: w * 0.2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.62))
            context.stroke(path, with: .color(.black.opacity(0.15)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            context.stroke(path.offsetBy(dx: -0.3, dy: -0.4), with: .color(Color(red: 0.79, green: 0.66, blue: 0.43)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
