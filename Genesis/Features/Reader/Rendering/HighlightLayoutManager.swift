import UIKit

/// Draws the reader's highlights (and the verse being read aloud) like a
/// marker on paper: one rounded band per line, as long as that line's words
/// and as tall as the text, so the page shows between the lines.
///
/// TextKit's own `.backgroundColor` fills whole line fragments: the full line
/// height (with its spacing, so the lines run together into a block), out to
/// the margin on every line that wraps, and as tall as a large first letter.
/// This draws the same colour from the same attribute, so nothing else in the
/// text changes.
final class HighlightLayoutManager: NSLayoutManager {
    /// Where the text container is drawn; TextKit hands it to
    /// `drawBackground` but not to `fillBackgroundRectArray`.
    private var drawingOrigin: CGPoint = .zero

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        drawingOrigin = origin
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<CGRect>,
        count rectCount: Int,
        forCharacterRange charRange: NSRange,
        color: UIColor
    ) {
        guard let storage = textStorage, rectCount > 0 else { return }
        // The rects TextKit would fill tell which lines this call is for.
        let given = (0..<rectCount).map { rectArray[$0] }
        let origin = drawingOrigin
        let text = storage.string as NSString
        let runGlyphs = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard runGlyphs.length > 0 else { return }

        color.setFill()
        enumerateLineFragments(forGlyphRange: runGlyphs) { lineRect, _, container, lineGlyphs, _ in
            let lineOnScreen = lineRect.offsetBy(dx: origin.x, dy: origin.y)
            guard given.contains(where: { $0.intersects(lineOnScreen) }) else { return }

            // This line's part of the run, without spaces or line breaks at
            // either end, so the band stops where the words stop.
            var segment = NSIntersectionRange(lineGlyphs, runGlyphs)
            while segment.length > 0, self.isBlank(glyphAt: segment.location, in: text) {
                segment = NSRange(location: segment.location + 1, length: segment.length - 1)
            }
            while segment.length > 0, self.isBlank(glyphAt: NSMaxRange(segment) - 1, in: text) {
                segment.length -= 1
            }
            guard segment.length > 0 else { return }

            let lastGlyph = NSMaxRange(segment) - 1
            let lastCharacter = self.characterIndexForGlyph(at: lastGlyph)
            // The body text's size, not a large first letter's.
            let font = storage.attribute(.font, at: lastCharacter, effectiveRange: nil) as? UIFont
                ?? UIFont.preferredFont(forTextStyle: .body)
            let baseline = lineRect.minY + self.location(forGlyphAt: lastGlyph).y

            let words = self.boundingRect(forGlyphRange: segment, in: container)
            let padX = font.pointSize * 0.12
            let padY = font.pointSize * 0.06
            let band = CGRect(
                x: words.minX - padX,
                y: baseline - font.ascender - padY,
                width: words.width + padX * 2,
                height: font.ascender - font.descender + padY * 2
            ).offsetBy(dx: origin.x, dy: origin.y)
            UIBezierPath(roundedRect: band, cornerRadius: font.pointSize * 0.18).fill()
        }
    }

    private func isBlank(glyphAt glyph: Int, in text: NSString) -> Bool {
        let index = characterIndexForGlyph(at: glyph)
        guard index < text.length, let scalar = Unicode.Scalar(text.character(at: index)) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
