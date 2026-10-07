import SwiftUI
import WidgetKit

// MARK: - Colours

/// The colours one widget draws with: the person's reader theme for Premium
/// (theme-matched widgets), the default Paper and Slate look otherwise.
struct WidgetColors: Sendable {
    let accent: Color
    let text: Color
    let secondary: Color
    let background: Color
    /// Set when the colours come from the reader theme.
    let theme: WidgetSnapshot.Theme?

    private init(accent: Color, text: Color, secondary: Color, background: Color, theme: WidgetSnapshot.Theme?) {
        self.accent = accent
        self.text = text
        self.secondary = secondary
        self.background = background
        self.theme = theme
    }

    /// Theme-matched for Premium, the default look otherwise.
    init(_ snapshot: WidgetSnapshot) {
        self.init(isPremium: snapshot.isPremium == true, theme: snapshot.theme)
    }

    init(isPremium: Bool, theme: WidgetSnapshot.Theme?) {
        guard isPremium, let theme else {
            self.init(accent: WidgetPalette.accent, text: WidgetPalette.text, secondary: WidgetPalette.secondary, background: WidgetPalette.background, theme: nil)
            return
        }
        self.init(
            accent: Color(light: theme.light.accent, dark: theme.dark.accent),
            text: Color(light: theme.light.text, dark: theme.dark.text),
            secondary: Color(light: theme.light.secondary, dark: theme.dark.secondary),
            background: Color(light: theme.light.background, dark: theme.dark.background),
            theme: theme
        )
    }
}

/// A widget's background: the theme's page colour, on textured paper for
/// the Premium themes (like the reader).
struct WidgetBackground: View {
    let colors: WidgetColors
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let variant = colors.theme.map { colorScheme == .dark ? $0.dark : $0.light }
        ZStack {
            colors.background
            if let variant, variant.hasPaperTexture {
                PaperGrain(isDark: variant.isDark)
            }
        }
    }
}

/// A faint grain with a few fibres, drawn the same way every time. It sits
/// behind the text, so contrast is unchanged.
private struct PaperGrain: View {
    let isDark: Bool

    var body: some View {
        Canvas { context, size in
            var random = GrainRandom(seed: 7)
            let ink: Color = isDark ? .white : Color(red: 0.35, green: 0.27, blue: 0.16)
            // Fine grain, scaled to the widget's area.
            let specks = Int(size.width * size.height / 30)
            for _ in 0..<specks {
                let x = random.next() * size.width
                let y = random.next() * size.height
                let radius = 0.35 + random.next() * 0.55
                let opacity = isDark ? 0.03 + random.next() * 0.03 : 0.035 + random.next() * 0.045
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(ink.opacity(opacity)))
            }
            // Fibres: short, thin strokes.
            let fibres = Int(size.width * size.height / 900)
            for _ in 0..<fibres {
                let start = CGPoint(x: random.next() * size.width, y: random.next() * size.height)
                let angle = random.next() * .pi * 2
                let length = 6 + random.next() * 18
                var path = Path()
                path.move(to: start)
                path.addLine(to: CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length))
                context.stroke(path, with: .color(ink.opacity(0.04 + random.next() * 0.05)), lineWidth: 0.3 + random.next() * 0.4)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A small repeatable generator so the paper looks the same on every reload.
private struct GrainRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    /// 0..<1
    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(state >> 11) / CGFloat(UInt64(1) << 53)
    }
}

/// Small capitals above a widget's content.
struct Eyebrow: View {
    let text: String
    var color: Color = WidgetPalette.accent

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(1)
            .foregroundStyle(color)
    }
}

// MARK: - Premium access

extension WidgetSize {
    init(_ family: WidgetFamily) {
        switch family {
        case .systemSmall: self = .small
        case .systemMedium: self = .medium
        case .systemLarge: self = .large
        case .systemExtraLarge: self = .extraLarge
        case .accessoryCircular: self = .accessoryCircular
        case .accessoryRectangular: self = .accessoryRectangular
        case .accessoryInline: self = .accessoryInline
        @unknown default: self = .large
        }
    }
}

extension WidgetSnapshot {
    /// Whether this widget, at this size, shows its content.
    func unlocks(_ kind: WidgetKind, in family: WidgetFamily) -> Bool {
        WidgetAccess.isUnlocked(kind: kind, size: WidgetSize(family), isPremium: isPremium == true)
    }
}

/// What a Premium widget shows without Premium: a calm card that says so and
/// opens Genesis. The default look, never the reader theme.
struct PremiumLockedView: View {
    /// One short sentence about what the widget does with Premium.
    let message: String
    let symbol: String
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if WidgetSize(family).isAccessory { Color.clear } else { WidgetPalette.background }
            }
            .widgetURL(GenesisLink.home)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Label(String(localized: "Genesis Premium"), systemImage: "lock")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: symbol)
                    .font(.title3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Genesis Premium"))
            .accessibilityHint(Text(message))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(String(localized: "Genesis Premium"), systemImage: "lock")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(WidgetPalette.accent)
                    .accessibilityHidden(true)
                Eyebrow(text: String(localized: "Premium"))
                Text(message)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(WidgetPalette.text)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
