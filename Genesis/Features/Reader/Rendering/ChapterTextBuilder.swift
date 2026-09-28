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

            if style.showsVerseNumbers {
                var numberAttributes = attributes
                numberAttributes[.font] = style.font.uiFont(size: size * 0.58, weight: .semibold)
                numberAttributes[.foregroundColor] = palette.uiAccent
                numberAttributes[.baselineOffset] = size * 0.32
                numberAttributes[.backgroundColor] = nil
                result.append(NSAttributedString(string: "\(verse.id.verse)\u{2009}", attributes: numberAttributes))
            }

            var textAttributes = attributes
            if decorations.selection.contains(verse.id) {
                textAttributes[.underlineStyle] = NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue
                textAttributes[.underlineColor] = palette.uiAccent
            }
            // Poetry lines stay in one paragraph so indentation is consistent.
            let text = verse.text.replacingOccurrences(of: "\n", with: "\u{2028}")
            result.append(NSAttributedString(string: text, attributes: textAttributes))

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
        return "\u{201C}\(body)\u{201D}\n\u{2014} \(reference) (\(translation.abbreviation))"
    }

    // MARK: - Pieces

    private static func appendTitle(for chapter: Chapter, style: ReaderStyle, into result: NSMutableAttributedString) {
        let palette = style.palette
        let size = style.fontSize
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center

        let bookTitle = NSMutableParagraphStyle()
        bookTitle.alignment = .center
        bookTitle.paragraphSpacing = size * 0.2

        result.append(NSAttributedString(string: chapter.book.name.uppercased() + "\n", attributes: [
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
