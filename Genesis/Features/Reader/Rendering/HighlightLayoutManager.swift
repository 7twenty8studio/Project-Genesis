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
/// A chapter's large first letter (`.largeInitial`) gets a block of its own,
/// as tall as the letter, joined to its line's band: the whole letter reads as
/// highlighted rather than cut across at the body text's height. Everything is
/// filled as one path, so where the shapes meet the (translucent) colour
/// isn't laid on twice.
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
            let radius = font.pointSize * 0.18
            marks.append(UIBezierPath(roundedRect: band, cornerRadius: radius))

            if let block = self.initialBlock(
                in: segment, of: storage, container: container, baseline: baseline,
                bottom: band.maxY - origin.y, padding: padX
            ) {
                marks.append(UIBezierPath(roundedRect: block.offsetBy(dx: origin.x, dy: origin.y), cornerRadius: radius))
            }
        }
        color.setFill()
        marks.fill()
    }

    /// The block behind a large first letter in these glyphs, if there is one:
    /// from just above the letter's top down to the band's foot.
    private func initialBlock(
        in segment: NSRange,
        of storage: NSTextStorage,
        container: NSTextContainer,
        baseline: CGFloat,
        bottom: CGFloat,
        padding: CGFloat
    ) -> CGRect? {
        let characters = characterRange(forGlyphRange: segment, actualGlyphRange: nil)
        var initial: NSRange?
        storage.enumerateAttribute(.largeInitial, in: characters) { value, range, stop in
            if value != nil {
                initial = range
                stop.pointee = true
            }
        }
        guard let initial else { return nil }
        let glyphs = glyphRange(forCharacterRange: initial, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        let letters = boundingRect(forGlyphRange: glyphs, in: container)

        let rise: CGFloat
        if let picture = storage.attribute(.attachment, at: initial.location, effectiveRange: nil) as? NSTextAttachment {
            rise = picture.bounds.height > 0 ? picture.bounds.maxY : (picture.image?.size.height ?? 0)
        } else if let font = storage.attribute(.font, at: initial.location, effectiveRange: nil) as? UIFont {
            let text = (storage.string as NSString).substring(with: initial)
            rise = LargeInitialMetrics.rise(of: text, capHeight: font.capHeight, ascender: font.ascender)
        } else {
            return nil
        }
        let top = baseline - rise - padding
        guard bottom > top else { return nil }
        return CGRect(x: letters.minX - padding, y: top, width: letters.width + padding * 2, height: bottom - top)
    }

    private func isBlank(glyphAt glyph: Int, in text: NSString) -> Bool {
        let index = characterIndexForGlyph(at: glyph)
        guard index < text.length, let scalar = Unicode.Scalar(text.character(at: index)) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}

/// How far a chapter's large first letter reaches, shared by the text (to
/// keep room for it) and the highlight (to cover it).
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
