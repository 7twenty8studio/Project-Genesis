import SwiftUI
import UIKit

/// Typefaces offered in the reader. All are built into iOS except Atkinson
/// Hyperlegible, which is bundled under the SIL Open Font License.
enum ReaderFont: String, Codable, CaseIterable, Identifiable, Sendable {
    case newYork
    case sfPro
    case georgia
    case baskerville
    case atkinsonHyperlegible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newYork: "New York"
        case .sfPro: "SF Pro"
        case .georgia: "Georgia"
        case .baskerville: "Baskerville"
        case .atkinsonHyperlegible: "Atkinson Hyperlegible"
        }
    }

    var caption: String {
        switch self {
        case .newYork: String(localized: "Apple's bookish serif")
        case .sfPro: String(localized: "Clean and modern")
        case .georgia: String(localized: "Warm, classic serif")
        case .baskerville: String(localized: "Traditional book face")
        case .atkinsonHyperlegible: String(localized: "Designed for low vision")
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
