import SwiftUI
import UIKit

/// The look of the handwritten page behind the ink.
enum PaperStyle: String, CaseIterable, Identifiable {
    case lined, plain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lined: String(localized: "Lined paper")
        case .plain: String(localized: "Plain paper")
        }
    }
}

/// Page geometry, in page points. The page is a fixed width and is scaled to
/// fit the screen, so a page written on iPad looks the same on iPhone.
enum HandwritingLayout {
    static let pageWidth: CGFloat = 768
    static let lineSpacing: CGFloat = 44
    /// Room to keep writing below the lowest stroke.
    static let overscroll: CGFloat = 400
}

/// Ruled lines under the ink. A tiled pattern, so a long page doesn't need a
/// page-sized bitmap.
final class PaperLinesView: UIView {
    private var style: PaperStyle = .lined
    private var lineColor: UIColor = .separator
    private var spacing: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(style newStyle: PaperStyle, lineColor newColor: UIColor, spacing newSpacing: CGFloat) {
        guard newStyle != style || newColor != lineColor || abs(newSpacing - spacing) > 0.01 else { return }
        style = newStyle
        lineColor = newColor
        spacing = newSpacing
        backgroundColor = style == .lined && spacing >= 4 ? Self.pattern(color: lineColor, spacing: spacing) : .clear
    }

    /// One row of the ruling: transparent, with a hairline at the bottom.
    private static func pattern(color: UIColor, spacing: CGFloat) -> UIColor {
        let size = CGSize(width: 8, height: spacing)
        let tile = UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: spacing - 1, width: size.width, height: 1))
        }
        return UIColor(patternImage: tile)
    }
}

extension ThemePalette {
    /// True for the dark themes (Slate, Contrast, Midnight), from the page colour.
    var isDarkPaper: Bool {
        let red = Double((backgroundHex >> 16) & 0xFF) / 255
        let green = Double((backgroundHex >> 8) & 0xFF) / 255
        let blue = Double(backgroundHex & 0xFF) / 255
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue < 0.5
    }
}
