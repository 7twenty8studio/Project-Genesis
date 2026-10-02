import SwiftUI
import UIKit

/// A paper theme for the reader and the rest of the app. Colours are muted
/// and warm; nothing is saturated.
enum ReaderTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Follows the system: Paper by day, Slate by night.
    case automatic
    case paper
    case cream
    case sepia
    case parchment
    case slate
    case highContrast
    case midnight
    case sage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: String(localized: "Auto", comment: "Reader theme name")
        case .paper: String(localized: "Paper", comment: "Reader theme name")
        case .cream: String(localized: "Cream", comment: "Reader theme name")
        case .sepia: String(localized: "Sepia", comment: "Reader theme name")
        case .parchment: String(localized: "Parchment", comment: "Reader theme name")
        case .slate: String(localized: "Slate", comment: "Reader theme name")
        case .highContrast: String(localized: "Contrast", comment: "Reader theme name")
        case .midnight: String(localized: "Midnight", comment: "Reader theme name")
        case .sage: String(localized: "Sage", comment: "Reader theme name")
        }
    }

    /// Resolves `.automatic` for the current appearance.
    func resolved(for scheme: ColorScheme) -> ReaderTheme {
        guard self == .automatic else { return self }
        return scheme == .dark ? .slate : .paper
    }

    var isDark: Bool { self == .slate || self == .highContrast || self == .midnight }

    /// Themes that come with Genesis Premium. Auto, Paper, Sepia, Slate and
    /// High Contrast stay free, so a readable light, dark and high-contrast
    /// choice is always available.
    var isPremium: Bool {
        switch self {
        case .cream, .parchment, .midnight, .sage: true
        case .automatic, .paper, .sepia, .slate, .highContrast: false
        }
    }

    var palette: ThemePalette {
        switch self {
        case .automatic, .paper:
            ThemePalette(background: 0xFBF8F1, surface: 0xF3EEE3, text: 0x2B2A27, secondaryText: 0x7D776B, accent: 0xA8844E, separator: 0xE4DDCD)
        case .cream:
            ThemePalette(background: 0xF6EFDF, surface: 0xEDE4CF, text: 0x2F2B24, secondaryText: 0x7E7564, accent: 0xA07C44, separator: 0xE0D5BD)
        case .sepia:
            ThemePalette(background: 0xEFE3CC, surface: 0xE5D6BA, text: 0x44372A, secondaryText: 0x806D57, accent: 0x94703C, separator: 0xD9C8A8)
        case .parchment:
            ThemePalette(background: 0xE9DCC0, surface: 0xDFD0B0, text: 0x3B3225, secondaryText: 0x76694F, accent: 0x6F7042, separator: 0xD2C19D)
        case .slate:
            ThemePalette(background: 0x1E2226, surface: 0x272C31, text: 0xDAD5C8, secondaryText: 0x8D9196, accent: 0xC9A96E, separator: 0x353B41)
        case .highContrast:
            ThemePalette(background: 0x000000, surface: 0x141414, text: 0xFFFFFF, secondaryText: 0xC8C8C8, accent: 0xF0CF86, separator: 0x3A3A3A)
        case .midnight:
            ThemePalette(background: 0x161B26, surface: 0x1E2432, text: 0xD6D9E0, secondaryText: 0x8A91A0, accent: 0xB9A77C, separator: 0x2C3342)
        case .sage:
            ThemePalette(background: 0xEEF0E6, surface: 0xE3E7D8, text: 0x2C3128, secondaryText: 0x6F7866, accent: 0x6E7F5A, separator: 0xD3D9C4)
        }
    }
}

/// Resolved colours for one theme, usable from both SwiftUI and UIKit.
struct ThemePalette: Equatable, Sendable {
    let backgroundHex: UInt32
    let surfaceHex: UInt32
    let textHex: UInt32
    let secondaryTextHex: UInt32
    let accentHex: UInt32
    let separatorHex: UInt32

    init(background: UInt32, surface: UInt32, text: UInt32, secondaryText: UInt32, accent: UInt32, separator: UInt32) {
        backgroundHex = background
        surfaceHex = surface
        textHex = text
        secondaryTextHex = secondaryText
        accentHex = accent
        separatorHex = separator
    }

    var uiBackground: UIColor { UIColor(hex: backgroundHex) }
    var uiSurface: UIColor { UIColor(hex: surfaceHex) }
    var uiText: UIColor { UIColor(hex: textHex) }
    var uiSecondaryText: UIColor { UIColor(hex: secondaryTextHex) }
    var uiAccent: UIColor { UIColor(hex: accentHex) }
    var uiSeparator: UIColor { UIColor(hex: separatorHex) }

    var background: Color { Color(uiColor: uiBackground) }
    var surface: Color { Color(uiColor: uiSurface) }
    var text: Color { Color(uiColor: uiText) }
    var secondaryText: Color { Color(uiColor: uiSecondaryText) }
    var accent: Color { Color(uiColor: uiAccent) }
    var separator: Color { Color(uiColor: uiSeparator) }
}

/// Highlight colours. Each has a name so meaning never depends on colour alone.
enum HighlightColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case yellow, blue, green, purple, pink, orange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yellow: String(localized: "Yellow", comment: "Highlight colour")
        case .blue: String(localized: "Blue", comment: "Highlight colour")
        case .green: String(localized: "Green", comment: "Highlight colour")
        case .purple: String(localized: "Purple", comment: "Highlight colour")
        case .pink: String(localized: "Pink", comment: "Highlight colour")
        case .orange: String(localized: "Orange", comment: "Highlight colour")
        }
    }

    private var hex: UInt32 {
        switch self {
        case .yellow: 0xF2D98B
        case .blue: 0xA9C7E8
        case .green: 0xB9D8A8
        case .purple: 0xCBB7E3
        case .pink: 0xEDB8C8
        case .orange: 0xF2C39B
        }
    }

    /// The swatch colour shown in pickers.
    var swatch: Color { Color(uiColor: UIColor(hex: hex)) }

    /// A shape for each colour, shown on swatches when Differentiate Without
    /// Colour is on (Settings › Accessibility › Display & Text Size).
    var symbol: String {
        switch self {
        case .yellow: "circle.fill"
        case .blue: "square.fill"
        case .green: "triangle.fill"
        case .purple: "diamond.fill"
        case .pink: "heart.fill"
        case .orange: "star.fill"
        }
    }

    /// A distinct underline for each colour in the reader, with Differentiate
    /// Without Colour on, so highlights can be told apart without colour.
    var underline: NSUnderlineStyle {
        switch self {
        case .yellow: [.single]
        case .blue: [.double]
        case .green: [.single, .patternDash]
        case .purple: [.single, .patternDot]
        case .pink: [.single, .patternDashDot]
        case .orange: [.thick]
        }
    }

    /// The wash drawn behind highlighted text. Softer on dark themes.
    func textBackground(onDarkTheme isDark: Bool) -> UIColor {
        UIColor(hex: hex).withAlphaComponent(isDark ? 0.32 : 0.6)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
