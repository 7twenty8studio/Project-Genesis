import UIKit

extension NSAttributedString.Key {
    /// `Int` raw value of the `VerseID` a run of text belongs to.
    static let verseID = NSAttributedString.Key("genesis.verseID")
}

/// Per-person marks drawn over a chapter. Scripture text itself is never changed.
struct ChapterDecorations: Equatable {
    var highlights: [VerseID: HighlightColor] = [:]
    var selection: Set<VerseID> = []
    var notedVerses: Set<VerseID> = []
    /// The verse being read aloud.
    var playing: VerseID?
}

/// A chapter laid out as styled text, plus where each verse starts.
struct BuiltChapter {
    let chapter: Chapter
    let text: NSAttributedString
    /// Character offset of each verse's first character (its number, if shown).
    let verseOffsets: [VerseID: Int]

    /// The verse at or after a character offset.
    func verse(atOffset offset: Int) -> VerseID? {
        guard text.length > 0 else { return nil }
        var index = min(max(offset, 0), text.length - 1)
        while index < text.length {
            var range = NSRange()
            if let raw = text.attribute(.verseID, at: index, effectiveRange: &range) as? Int {
                return VerseID(rawValue: raw)
            }
            index = NSMaxRange(range)
        }
        return chapter.verses.last?.id
    }
}

/// Builds the attributed text for a chapter: title, headings, verse numbers,
/// paragraphs and poetry, with highlights and selection applied.
@MainActor
enum ChapterTextBuilder {
    static func build(_ chapter: Chapter, style: ReaderStyle, decorations: ChapterDecorations) -> BuiltChapter {
        let palette = style.palette
        let size = style.fontSize
        let bodyFont = style.font.uiFont(size: size)
        let result = NSMutableAttributedString()
        var offsets: [VerseID: Int] = [:]

        appendTitle(for: chapter, style: style, into: result)

        let prose = paragraphStyle(style: style, firstLineIndent: 0, headIndent: 0)
        let poetry = paragraphStyle(style: style, firstLineIndent: size * 1.2, headIndent: size * 2.4)
        let headingsByVerse = Dictionary(grouping: chapter.headings, by: \.beforeVerse)
        let noteMarker = noteMarkerAttachment(font: bodyFont, color: palette.uiAccent)

        for (index, verse) in chapter.verses.enumerated() {
            let previous = index > 0 ? chapter.verses[index - 1] : nil
            let paragraph = verse.isPoetry ? poetry : prose

            for heading in headingsByVerse[verse.id.verse] ?? [] {
                if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
                result.append(NSAttributedString(string: heading.text, attributes: [
                    .font: style.font.uiFont(size: size * 0.82, italic: true),
                    .foregroundColor: palette.uiSecondaryText,
                    .paragraphStyle: paragraphStyle(style: style, firstLineIndent: 0, headIndent: 0, spacingBefore: size * 0.4),
                ]))
            }

            // Decide whether this verse starts a new line.
            let startsNewParagraph = index == 0
                || style.layout == .versePerLine
                || verse.isPoetry
                || verse.startsParagraph
                || (previous?.isPoetry ?? false)
            if result.length > 0 {
                result.append(NSAttributedString(string: startsNewParagraph ? "\n" : " ", attributes: [.font: bodyFont, .paragraphStyle: paragraph]))
            }

            offsets[verse.id] = result.length
            var attributes: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: palette.uiText,
                .paragraphStyle: paragraph,
                .verseID: verse.id.rawValue,
            ]
            if let color = decorations.highlights[verse.id] {
                attributes[.backgroundColor] = color.textBackground(onDarkTheme: style.theme.isDark)
            }
            if decorations.playing == verse.id {
                attributes[.backgroundColor] = palette.uiAccent.withAlphaComponent(style.theme.isDark ? 0.28 : 0.16)
            }

            // The chapter opens with a large first letter instead of "1",
            // as printed Bibles do (the chapter number is above it).
            let opensWithInitial = index == 0 && verse.id.verse == 1 && style.largeInitial
            if style.showsVerseNumbers && !opensWithInitial {
                var numberAttributes = attributes
                numberAttributes[.font] = style.font.uiFont(size: size * 0.58, weight: .semibold)
                numberAttributes[.foregroundColor] = palette.uiAccent
                numberAttributes[.baselineOffset] = size * 0.32
                numberAttributes[.backgroundColor] = nil
                result.append(NSAttributedString(string: "\(verse.id.verse)\u{2009}", attributes: numberAttributes))
            }

            var textAttributes = attributes
            if style.differentiatesWithoutColor, let color = decorations.highlights[verse.id] {
                textAttributes[.underlineStyle] = color.underline.rawValue
                textAttributes[.underlineColor] = palette.uiText.withAlphaComponent(0.55)
            }
            if decorations.selection.contains(verse.id) {
                textAttributes[.underlineStyle] = NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue
                textAttributes[.underlineColor] = palette.uiAccent
            }
            // Poetry lines stay in one paragraph so indentation is consistent.
            let text = verse.text.replacingOccurrences(of: "\n", with: "\u{2028}")
            if opensWithInitial, let split = initialSplit(text), style.initialStyle == .illuminated,
               let ornament = illuminatedInitial(split.initial, style: style, bodyFont: bodyFont) {
                // The illuminated letter is a picture placed just before the
                // verse. The verse's own characters follow it unchanged: the
                // drawn letter is hidden (clear and almost no width) so it
                // isn't shown twice, but it's still there for VoiceOver,
                // search and the verse offsets. The picture is U+FFFC, an
                // extra character before the verse, never inside it.
                let picture = NSMutableAttributedString(attributedString: NSAttributedString(attachment: ornament))
                var pictureAttributes = attributes
                pictureAttributes[.font] = bodyFont
                picture.addAttributes(pictureAttributes, range: NSRange(location: 0, length: picture.length))
                result.append(picture)

                var hiddenAttributes = textAttributes
                hiddenAttributes[.font] = UIFont(descriptor: bodyFont.fontDescriptor, size: 0.1)
                hiddenAttributes[.foregroundColor] = UIColor.clear
                hiddenAttributes[.backgroundColor] = nil
                hiddenAttributes[.underlineStyle] = nil
                result.append(NSAttributedString(string: split.initial, attributes: hiddenAttributes))
                result.append(NSAttributedString(string: split.rest, attributes: textAttributes))
            } else if opensWithInitial, let split = initialSplit(text) {
                // Only the styling changes: the letters are the verse's own.
                var initialAttributes = textAttributes
                initialAttributes[.font] = style.font.uiFont(size: size * 2.6)
                initialAttributes[.foregroundColor] = palette.uiAccent
                result.append(NSAttributedString(string: split.initial, attributes: initialAttributes))
                result.append(NSAttributedString(string: split.rest, attributes: textAttributes))
            } else {
                result.append(NSAttributedString(string: text, attributes: textAttributes))
            }

            if decorations.notedVerses.contains(verse.id), let noteMarker {
                let marker = NSMutableAttributedString(string: "\u{2009}")
                marker.append(NSAttributedString(attachment: noteMarker))
                marker.addAttributes([.verseID: verse.id.rawValue, .paragraphStyle: paragraph], range: NSRange(location: 0, length: marker.length))
                result.append(marker)
            }
        }

        return BuiltChapter(chapter: chapter, text: result, verseOffsets: offsets)
    }

    /// Plain text for copying or sharing, with the reference and translation.
    static func shareText(for verses: [Verse], translation: Translation) -> String {
        guard let reference = PassageReference(verses: verses.map(\.id)) else { return "" }
        let body = verses.map { verses.count > 1 ? "\($0.id.verse) \($0.plainText)" : $0.plainText }.joined(separator: " ")
        return "\u{201C}\(body)\u{201D}\n\u{2014} \(reference.description(in: translation.language)) (\(translation.abbreviation))"
    }

    // MARK: - Pieces

    /// The text up to and including its first letter (so an opening quotation
    /// mark stays with it), and the rest; nil if there's no letter. The two
    /// parts together are exactly the original text.
    nonisolated static func initialSplit(_ text: String) -> (initial: String, rest: String)? {
        guard let letter = text.firstIndex(where: \.isLetter) else { return nil }
        let end = text.index(after: letter)
        return (String(text[..<end]), String(text[end...]))
    }

    /// An illuminated initial: the opening letter (with any quotation mark
    /// before it) drawn inside a square frame with a fine double border,
    /// small corner flourishes and a soft fill in the theme's tones, about two
    /// lines tall. TextKit 1 can't wrap lines around an inline picture (and
    /// pages would need matching exclusion paths), so it sits in the first
    /// line, its foot on the text's descender, and that line grows to fit.
    static func illuminatedInitial(_ initial: String, style: ReaderStyle, bodyFont: UIFont) -> NSTextAttachment? {
        guard let letter = initial.last else { return nil }
        let palette = style.palette
        let accent = palette.uiAccent
        let side = (bodyFont.lineHeight * 2 - abs(bodyFont.descender)).rounded(.up)
        guard side > 8 else { return nil }
        let gap = (style.fontSize * 0.22).rounded()
        let canvas = CGSize(width: side + gap, height: side)

        // The letter, with any opening punctuation smaller before it, sized to
        // sit comfortably inside the inner frame.
        var letterSize = side * 0.6
        func makeLettering(_ size: CGFloat) -> NSAttributedString {
            let font = style.font.uiFont(size: size, weight: .semibold)
            let text = NSMutableAttributedString()
            let prefix = String(initial.dropLast())
            if !prefix.isEmpty {
                text.append(NSAttributedString(string: prefix, attributes: [
                    .font: style.font.uiFont(size: size * 0.5),
                    .foregroundColor: accent,
                ]))
            }
            text.append(NSAttributedString(string: String(letter), attributes: [.font: font, .foregroundColor: accent]))
            return text
        }
        var drawn = makeLettering(letterSize)
        let maxWidth = side * 0.7
        if drawn.size().width > maxWidth {
            letterSize *= maxWidth / drawn.size().width
            drawn = makeLettering(letterSize)
        }
        let letterFont = style.font.uiFont(size: letterSize, weight: .semibold)
        let lettering = drawn

        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            let cg = context.cgContext
            let unit = side * 0.09
            let outer = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: unit * 0.45, dy: unit * 0.45)
            let inner = outer.insetBy(dx: unit * 0.55, dy: unit * 0.55)

            // Soft fill: the page's surface, warmed with the accent towards the lower corner.
            palette.uiSurface.setFill()
            UIRectFill(outer)
            cg.saveGState()
            UIBezierPath(rect: outer).addClip()
            let tint = style.theme.isDark ? 0.22 : 0.16
            let colors = [accent.withAlphaComponent(tint * 0.35).cgColor, accent.withAlphaComponent(tint).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: outer.minX, y: outer.minY), end: CGPoint(x: outer.maxX, y: outer.maxY), options: [])
            }
            cg.restoreGState()

            // A fine double border.
            accent.setStroke()
            let outerBorder = UIBezierPath(rect: outer)
            outerBorder.lineWidth = max(1, side * 0.025)
            outerBorder.stroke()
            accent.withAlphaComponent(0.75).setStroke()
            let innerBorder = UIBezierPath(rect: inner)
            innerBorder.lineWidth = max(0.5, side * 0.012)
            innerBorder.stroke()

            // Corner flourishes: a diamond on each outer corner and a small
            // curl with a dot inside each inner corner.
            let corners: [(CGPoint, CGPoint, CGFloat, CGFloat)] = [
                (CGPoint(x: outer.minX, y: outer.minY), CGPoint(x: inner.minX, y: inner.minY), 1, 1),
                (CGPoint(x: outer.maxX, y: outer.minY), CGPoint(x: inner.maxX, y: inner.minY), -1, 1),
                (CGPoint(x: outer.minX, y: outer.maxY), CGPoint(x: inner.minX, y: inner.maxY), 1, -1),
                (CGPoint(x: outer.maxX, y: outer.maxY), CGPoint(x: inner.maxX, y: inner.maxY), -1, -1),
            ]
            accent.setFill()
            for (outerCorner, innerCorner, dx, dy) in corners {
                let r = unit * 0.42
                let diamond = UIBezierPath()
                diamond.move(to: CGPoint(x: outerCorner.x, y: outerCorner.y - r))
                diamond.addLine(to: CGPoint(x: outerCorner.x + r, y: outerCorner.y))
                diamond.addLine(to: CGPoint(x: outerCorner.x, y: outerCorner.y + r))
                diamond.addLine(to: CGPoint(x: outerCorner.x - r, y: outerCorner.y))
                diamond.close()
                diamond.fill()

                let curl = UIBezierPath()
                curl.move(to: CGPoint(x: innerCorner.x + dx * unit * 1.9, y: innerCorner.y + dy * unit * 0.4))
                curl.addQuadCurve(
                    to: CGPoint(x: innerCorner.x + dx * unit * 0.4, y: innerCorner.y + dy * unit * 1.9),
                    controlPoint: CGPoint(x: innerCorner.x + dx * unit * 0.45, y: innerCorner.y + dy * unit * 0.45)
                )
                curl.lineWidth = max(0.5, side * 0.014)
                curl.lineCapStyle = .round
                curl.stroke()
                let dotRadius = unit * 0.2
                let dotCenter = CGPoint(x: innerCorner.x + dx * unit * 1.05, y: innerCorner.y + dy * unit * 1.05)
                UIBezierPath(ovalIn: CGRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)).fill()
            }

            // The letter, its capital height centred in the frame.
            let width = lettering.size().width
            let baseline = outer.midY + letterFont.capHeight / 2
            lettering.draw(at: CGPoint(x: outer.midX - width / 2, y: baseline - letterFont.ascender))
        }

        let attachment = NSTextAttachment(image: image)
        attachment.bounds = CGRect(x: 0, y: bodyFont.descender, width: canvas.width, height: canvas.height)
        return attachment
    }

    private static func appendTitle(for chapter: Chapter, style: ReaderStyle, into result: NSMutableAttributedString) {
        let palette = style.palette
        let size = style.fontSize
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center

        let bookTitle = NSMutableParagraphStyle()
        bookTitle.alignment = .center
        bookTitle.paragraphSpacing = size * 0.2

        result.append(NSAttributedString(string: chapter.book.name(in: style.bibleLanguage).uppercased() + "\n", attributes: [
            .font: style.font.uiFont(size: size * 0.7, weight: .medium),
            .foregroundColor: palette.uiSecondaryText,
            .kern: size * 0.12,
            .paragraphStyle: bookTitle,
        ]))

        let numberStyle = NSMutableParagraphStyle()
        numberStyle.alignment = .center
        numberStyle.paragraphSpacing = size * 1.1
        result.append(NSAttributedString(string: "\(chapter.id.chapter)", attributes: [
            .font: style.font.uiFont(size: size * 2.4, weight: .light),
            .foregroundColor: palette.uiAccent,
            .paragraphStyle: numberStyle,
        ]))
    }

    private static func paragraphStyle(
        style: ReaderStyle,
        firstLineIndent: CGFloat,
        headIndent: CGFloat,
        spacingBefore: CGFloat = 0
    ) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = style.lineHeightMultiple
        paragraph.paragraphSpacing = style.paragraphSpacing
        paragraph.paragraphSpacingBefore = spacingBefore
        paragraph.firstLineHeadIndent = firstLineIndent
        paragraph.headIndent = headIndent
        paragraph.hyphenationFactor = 0.15
        paragraph.lineBreakStrategy = .standard
        return paragraph
    }

    private static func noteMarkerAttachment(font: UIFont, color: UIColor) -> NSTextAttachment? {
        let configuration = UIImage.SymbolConfiguration(pointSize: font.pointSize * 0.62, weight: .regular)
        guard let image = UIImage(systemName: "note.text", withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
        let attachment = NSTextAttachment(image: image)
        attachment.bounds = CGRect(x: 0, y: font.capHeight * 0.1, width: image.size.width, height: image.size.height)
        return attachment
    }
}
