import CoreText
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
///
/// A chapter's large first letter (`.largeInitial`) is laid out at the body
/// size and drawn here, large, standing on the first line's baseline, so it
/// never changes the line's height. A highlight runs through it at the line's
/// own height (the letter's hidden body-size characters and its room are part
/// of the band), with the letter drawn over the band.
final class HighlightLayoutManager: NSLayoutManager {
    /// Where the text container is drawn; TextKit hands it to
    /// `drawBackground` but not to `fillBackgroundRectArray`.
    private var drawingOrigin: CGPoint = .zero

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        drawingOrigin = origin
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let context = UIGraphicsGetCurrentContext() else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard characters.length > 0 else { return }
        storage.enumerateAttribute(.largeInitial, in: characters) { value, range, _ in
            guard let mark = value as? LargeInitialMark else { return }
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let line = self.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let point = self.location(forGlyphAt: glyphs.location)
            mark.draw(
                atX: origin.x + line.minX + point.x,
                baseline: origin.y + line.minY + point.y,
                in: context
            )
        }
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

        let marks = UIBezierPath()
        marks.usesEvenOddFillRule = false
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
            marks.append(UIBezierPath(roundedRect: band, cornerRadius: font.pointSize * 0.18))
        }
        color.setFill()
        marks.fill()
    }

    private func isBlank(glyphAt glyph: Int, in text: NSString) -> Bool {
        let index = characterIndexForGlyph(at: glyph)
        guard index < text.length, let scalar = Unicode.Scalar(text.character(at: index)) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}

/// What HighlightLayoutManager draws for a chapter's large first letter:
/// the letters themselves (the verse's own, in a large size) or an
/// illuminated picture. Purely visual: the text keeps the real letters.
final class LargeInitialMark: NSObject {
    private let text: NSAttributedString?
    private let color: UIColor
    private let image: UIImage?
    private let descender: CGFloat

    init(text: String, font: UIFont, color: UIColor) {
        self.text = NSAttributedString(string: text, attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
        self.color = color
        image = nil
        descender = 0
    }

    /// An illuminated picture whose foot sits on the body text's descender.
    init(image: UIImage, descender: CGFloat) {
        text = nil
        color = .clear
        self.image = image
        self.descender = descender
    }

    func draw(atX x: CGFloat, baseline: CGFloat, in context: CGContext) {
        if let image {
            let size = image.size
            image.draw(in: CGRect(x: x, y: baseline - descender - size.height, width: size.width, height: size.height))
        } else if let text {
            let line = CTLineCreateWithAttributedString(text as CFAttributedString)
            context.saveGState()
            context.setFillColor(color.cgColor)
            context.textMatrix = .identity
            context.translateBy(x: x, y: baseline)
            context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }
}

/// How far a chapter's large first letter reaches above the baseline, so the
/// text keeps room for it above the first paragraph.
enum LargeInitialMetrics {
    /// The height above the baseline the letter reaches: a plain capital
    /// stops at the cap height; anything else (an accent, a lower-case
    /// letter) may reach the ascender.
    static func rise(of initial: String, capHeight: CGFloat, ascender: CGFloat) -> CGFloat {
        let plainCapital = initial.last.map { $0.isASCII && $0.isUppercase } ?? false
        return plainCapital ? capHeight : ascender
    }

    /// The room to keep before the first paragraph so a letter rising
    /// `rise` above the first baseline clears whatever is above it, with
    /// lines of a fixed `lineHeight` (TextKit sets the text at a line's foot,
    /// so the line holds `lineHeight + bodyDescender` above its baseline).
    static func roomAbove(rise: CGFloat, lineHeight: CGFloat, bodyDescender: CGFloat, fontSize: CGFloat) -> CGFloat {
        let above = lineHeight + bodyDescender
        let breathing = fontSize * 0.2
        return max(0, (rise + breathing - above).rounded(.up))
    }
}
