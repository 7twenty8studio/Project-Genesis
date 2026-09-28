import UIKit

/// Splits styled text into page-sized ranges with TextKit 1, the same engine
/// `ReaderTextView` draws with, so each page shows exactly what was measured.
@MainActor
enum Paginator {
    static func pages(for text: NSAttributedString, pageSize: CGSize) -> [NSRange] {
        guard text.length > 0, pageSize.width > 20, pageSize.height > 20 else {
            return [NSRange(location: 0, length: text.length)]
        }

        let storage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        var pages: [NSRange] = []
        // A generous cap guards against a pathological layout never finishing.
        let maximumPages = text.length / 8 + 10
        while pages.count < maximumPages {
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)

            let glyphRange = layoutManager.glyphRange(for: container)
            guard glyphRange.length > 0 else { break }
            pages.append(layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil))
            if NSMaxRange(glyphRange) >= layoutManager.numberOfGlyphs { break }
        }
        return pages.isEmpty ? [NSRange(location: 0, length: text.length)] : pages
    }
}
