import SwiftUI
import UIKit

/// Typefaces offered in the reader. Literata, EB Garamond, Atkinson
/// Hyperlegible, Crimson Pro, Source Serif 4 and Spectral are bundled under
/// the SIL Open Font License (Resources/Fonts, built by Tools/Fonts); the rest
/// are built into iOS. The last three are Premium (`isPremium`).
enum ReaderFont: String, Codable, CaseIterable, Identifiable, Sendable {
    case newYork
    case sfPro
    case georgia
    case baskerville
    case atkinsonHyperlegible
    case literata
    case ebGaramond
    case crimsonPro
    case sourceSerif
    case spectral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newYork: "New York"
        case .sfPro: "SF Pro"
        case .georgia: "Georgia"
        case .baskerville: "Baskerville"
        case .atkinsonHyperlegible: "Atkinson Hyperlegible"
        case .literata: "Literata"
        case .ebGaramond: "EB Garamond"
        case .crimsonPro: "Crimson Pro"
        case .sourceSerif: "Source Serif"
        case .spectral: "Spectral"
        }
    }

    var caption: String {
        switch self {
        case .newYork: String(localized: "Apple's bookish serif")
        case .sfPro: String(localized: "Clean and modern")
        case .georgia: String(localized: "Warm, classic serif")
        case .baskerville: String(localized: "Traditional book face")
        case .atkinsonHyperlegible: String(localized: "Designed for low vision")
        case .literata: String(localized: "Made for long reading on screens")
        case .ebGaramond: String(localized: "An elegant old-style book face")
        case .crimsonPro: String(localized: "A graceful Garamond-style face for long chapters")
        case .sourceSerif: String(localized: "A calm, sturdy serif with an even rhythm")
        case .spectral: String(localized: "A light, refined face made for screens")
        }
    }

    /// Premium typefaces (`PremiumFeature.premiumThemes`); the rest are free.
    var isPremium: Bool {
        switch self {
        case .crimsonPro, .sourceSerif, .spectral: true
        default: false
        }
    }

    /// PostScript names of a bundled face: regular, semibold and italic.
    var bundledFaces: (regular: String, semibold: String, italic: String)? {
        switch self {
        case .literata: ("Literata-Regular", "Literata-SemiBold", "Literata-Italic")
        case .ebGaramond: ("EBGaramond-Regular", "EBGaramond-SemiBold", "EBGaramond-Italic")
        case .crimsonPro: ("CrimsonPro-Regular", "CrimsonPro-SemiBold", "CrimsonPro-Italic")
        case .sourceSerif: ("SourceSerif4-Regular", "SourceSerif4-SemiBold", "SourceSerif4-Italic")
        case .spectral: ("Spectral-Regular", "Spectral-SemiBold", "Spectral-Italic")
        default: nil
        }
    }

    /// A UIFont for body text at the given point size.
    func uiFont(size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        let base: UIFont
        switch self {
        case .sfPro:
            base = .systemFont(ofSize: size, weight: weight)
        case .newYork:
            let system = UIFont.systemFont(ofSize: size, weight: weight)
            base = system.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? system
        case .georgia:
            base = UIFont(name: weight.rawValue >= UIFont.Weight.semibold.rawValue ? "Georgia-Bold" : "Georgia", size: size) ?? .systemFont(ofSize: size, weight: weight)
        case .baskerville:
            base = UIFont(name: weight.rawValue >= UIFont.Weight.semibold.rawValue ? "Baskerville-SemiBold" : "Baskerville", size: size) ?? .systemFont(ofSize: size, weight: weight)
        case .atkinsonHyperlegible:
            base = UIFont(name: weight.rawValue >= UIFont.Weight.semibold.rawValue ? "AtkinsonHyperlegible-Bold" : "AtkinsonHyperlegible-Regular", size: size)
                ?? .systemFont(ofSize: size, weight: weight)
        case .literata, .ebGaramond, .crimsonPro, .sourceSerif, .spectral:
            if let faces = bundledFaces {
                if italic, let face = UIFont(name: faces.italic, size: size) { return face }
                base = UIFont(name: weight.rawValue >= UIFont.Weight.semibold.rawValue ? faces.semibold : faces.regular, size: size)
                    ?? .systemFont(ofSize: size, weight: weight)
            } else {
                base = .systemFont(ofSize: size, weight: weight)
            }
        }
        guard italic, let descriptor = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.traitItalic)) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// A SwiftUI font for previews and app chrome.
    func font(size: CGFloat, weight: UIFont.Weight = .regular) -> Font {
        Font(uiFont(size: size, weight: weight))
    }
}

extension EntitlementService {
    /// Free typefaces always; Premium ones with Premium.
    func allows(_ font: ReaderFont) -> Bool {
        !font.isPremium || allows(.premiumThemes)
    }
}
