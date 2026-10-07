import UIKit

/// Lays out a journal export page by page: text flows across pages with
/// TextKit, pictures move to the next page when they don't fit, and every
/// page gets the footer. Used only inside `JournalPDFRenderer.render`.
final class PDFPageWriter {
    private let context: UIGraphicsPDFRendererContext
    private let pageSize: CGSize
    private let content: CGRect
    private let style: PDFStyle
    private var y: CGFloat = 0
    private var pageNumber = 0
    private var pageIsEmpty = true

    init(context: UIGraphicsPDFRendererContext, pageSize: CGSize, content: CGRect, style: PDFStyle) {
        self.context = context
        self.pageSize = pageSize
        self.content = content
        self.style = style
    }

    // MARK: Pages

    private func beginPage() {
        context.beginPage()
        pageNumber += 1
        y = content.minY
        pageIsEmpty = true
        drawFooter()
    }

    private var remaining: CGFloat { content.maxY - y }

    /// Starts a new page unless `height` fits on this one (or the page is empty).
    private func ensureSpace(_ height: CGFloat) {
        if remaining < height, !pageIsEmpty { beginPage() }
    }

    private func drawFooter() {
        let footer = NSAttributedString(
            string: String(localized: "Made with Genesis"),
            attributes: style.attributes(style.body(8.5, italic: true), color: style.quiet, paragraph: style.paragraph(alignment: .center))
        )
        let baseline = pageSize.height - (pageSize.height - content.maxY) / 2
        footer.draw(in: CGRect(x: content.minX, y: baseline - 6, width: content.width, height: 14))
        guard pageNumber > 1 else { return }
        let number = NSAttributedString(
            string: String(pageNumber),
            attributes: style.attributes(style.body(9), color: style.quiet, paragraph: style.paragraph(alignment: .right))
        )
        number.draw(in: CGRect(x: content.minX, y: baseline - 6, width: content.width, height: 14))
    }

    // MARK: Title page

    func drawTitlePage(_ export: JournalExport) {
        beginPage()
        y = content.minY + content.height * 0.3
        drawRule(width: 60)
        y += 28
        let centered = style.paragraph(spacing: 10, alignment: .center, lineHeight: 1.1)
        drawText(NSAttributedString(string: export.title, attributes: style.attributes(style.body(30, weight: .semibold), paragraph: centered)))
        if !export.subtitle.isEmpty {
            drawText(NSAttributedString(string: export.subtitle, attributes: style.attributes(style.body(14, italic: true), color: style.quiet, paragraph: centered)))
        }
        y += 18
        drawRule(width: 60)
        y += 18
        let created = export.createdAt.formatted(date: .long, time: .omitted)
        drawText(NSAttributedString(string: created, attributes: style.attributes(style.body(11), color: style.quiet, paragraph: centered)))
    }

    // MARK: Entries

    func draw(_ entry: JournalExport.Entry, isFirst: Bool) {
        if isFirst {
            beginPage()
        } else {
            ensureSpace(180)
            if !pageIsEmpty {
                y += 20
                drawRule(width: 40)
                y += 24
            }
        }
        drawText(NSAttributedString(string: entry.title, attributes: style.attributes(style.body(20, weight: .semibold), paragraph: style.paragraph(spacing: 6, lineHeight: 1.1))))
        for line in entry.details where !line.isEmpty {
            drawText(NSAttributedString(string: line, attributes: style.attributes(style.body(10.5), color: style.quiet, paragraph: style.paragraph(spacing: 2))))
        }
        y += 12
        let body = PDFMarkdown(style: style).text(entry.body)
        if body.length > 0 { drawText(body, after: 8) }
        if let answer = entry.answer {
            drawLabel(String(localized: "Answered", comment: "PDF export: heading over how a prayer was answered"))
            drawText(NSAttributedString(string: answer, attributes: style.attributes(style.body(12, italic: true), paragraph: style.paragraph())), after: 8)
        }
        drawPassages(entry.passages)
        entry.pictures.forEach(drawPicture)
        drawFileList(entry)
    }

    private func drawPassages(_ passages: [JournalExport.Passage]) {
        guard !passages.isEmpty else { return }
        drawLabel(String(localized: "Passages", comment: "PDF export: heading over the Bible passages attached"))
        for passage in passages {
            ensureSpace(60)
            let reference = "\(passage.reference) · \(passage.translation)"
            drawText(NSAttributedString(string: reference, attributes: style.attributes(style.body(10.5, weight: .semibold), color: style.accent, paragraph: style.paragraph(spacing: 3, indent: 14))))
            let verse = NSAttributedString(string: passage.text, attributes: style.attributes(style.body(12), paragraph: style.paragraph(spacing: 10, indent: 14)))
            drawText(verse)
        }
    }

    private func drawFileList(_ entry: JournalExport.Entry) {
        var lines: [String] = entry.recordings.map { recording in
            let length = VoiceLevel.timeText(recording.duration)
            let line = String(localized: "Voice recording, \(length)", comment: "PDF export: a recording and its length, e.g. 3:05")
            return recording.caption.isEmpty ? line : "\(line) · \(recording.caption)"
        }
        lines += entry.documents.map { document in
            let line = String(localized: "PDF, \(document.pageCount) pages", comment: "PDF export: an imported PDF and its page count")
            return document.caption.isEmpty ? line : "\(line) · \(document.caption)"
        }
        guard !lines.isEmpty else { return }
        drawLabel(String(localized: "Also attached", comment: "PDF export: heading over recordings and PDFs, which can't be printed"))
        for line in lines {
            drawText(NSAttributedString(string: "\u{2022}  " + line, attributes: style.attributes(style.body(11), color: style.quiet, paragraph: style.paragraph(spacing: 3, indent: 14))))
        }
        y += 6
    }

    private func drawLabel(_ text: String) {
        ensureSpace(70)
        y += 6
        let label = NSAttributedString(string: text.uppercased(), attributes: style.attributes(style.body(9.5, weight: .semibold), color: style.accent, paragraph: style.paragraph(spacing: 6)))
        drawText(label)
    }

    private func drawPicture(_ picture: JournalExport.Picture) {
        guard let image = UIImage(data: picture.data), image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(content.width / image.size.width, content.height * 0.55 / image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        ensureSpace(size.height + (picture.caption.isEmpty ? 12 : 34))
        image.draw(in: CGRect(x: content.midX - size.width / 2, y: y, width: size.width, height: size.height))
        y += size.height + 6
        pageIsEmpty = false
        if !picture.caption.isEmpty {
            let caption = NSAttributedString(string: picture.caption, attributes: style.attributes(style.body(10, italic: true), color: style.quiet, paragraph: style.paragraph(alignment: .center)))
            drawText(caption)
        }
        y += 10
    }

    private func drawRule(width: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: content.midX - width / 2, y: y))
        path.addLine(to: CGPoint(x: content.midX + width / 2, y: y))
        path.lineWidth = 0.75
        style.accent.setStroke()
        path.stroke()
    }

    // MARK: Flowing text

    /// Draws text at the current position, continuing on new pages as needed.
    private func drawText(_ text: NSAttributedString, after spacing: CGFloat = 0) {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let total = layout.numberOfGlyphs
        var laidOut = 0
        while laidOut < total {
            let container = NSTextContainer(size: CGSize(width: content.width, height: max(0, remaining)))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            let range = layout.glyphRange(for: container)
            guard range.length > 0 else {
                // Nothing fits: a fresh page, unless this one already is.
                if pageIsEmpty { return }
                beginPage()
                continue
            }
            let origin = CGPoint(x: content.minX, y: y)
            layout.drawBackground(forGlyphRange: range, at: origin)
            layout.drawGlyphs(forGlyphRange: range, at: origin)
            y += layout.usedRect(for: container).maxY
            pageIsEmpty = false
            laidOut = NSMaxRange(range)
            if laidOut < total { beginPage() }
        }
        y += spacing
    }
}

/// Sermon notes' Markdown (and prayers' plain text) as styled text for the PDF.
struct PDFMarkdown {
    let style: PDFStyle

    func text(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for block in SermonMarkdown.blocks(markdown) {
            result.append(line(block))
            result.append(NSAttributedString(string: "\n", attributes: style.attributes(style.body(12))))
        }
        // No paragraph break after the last block.
        if result.length > 0 { result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1)) }
        return result
    }

    private func line(_ block: SermonMarkdown.Block) -> NSAttributedString {
        switch block.kind {
        case .heading:
            let paragraph = style.paragraph(spacing: 4, lineHeight: 1.15)
            return inline(block.text, size: 14.5, weight: .semibold, paragraph: paragraph, spacingBefore: 8)
        case .bullet:
            return prefixed("\u{2022}", block.text)
        case let .numbered(number):
            return prefixed("\(number).", block.text)
        case .quote:
            return inline(block.text, italic: true, color: style.quiet, paragraph: style.paragraph(indent: 18))
        case .paragraph:
            return inline(block.text, paragraph: style.paragraph())
        }
    }

    private func prefixed(_ marker: String, _ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.setParagraphStyle(style.paragraph(spacing: 3))
        paragraph.firstLineHeadIndent = 4
        paragraph.headIndent = 22
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 22)]
        let result = NSMutableAttributedString(string: marker + "\t", attributes: style.attributes(style.body(12), color: style.accent, paragraph: paragraph))
        result.append(inline(text, paragraph: paragraph))
        return result
    }

    /// Bold and italic from the line's inline Markdown.
    private func inline(
        _ text: String,
        size: CGFloat = 12,
        weight: UIFont.Weight = .regular,
        italic: Bool = false,
        color: UIColor? = nil,
        paragraph: NSParagraphStyle,
        spacingBefore: CGFloat = 0
    ) -> NSAttributedString {
        var paragraphStyle = paragraph
        if spacingBefore > 0, let mutable = paragraph.mutableCopy() as? NSMutableParagraphStyle {
            mutable.paragraphSpacingBefore = spacingBefore
            paragraphStyle = mutable
        }
        let parsed = SermonMarkdown.inline(text)
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            let bold = intent.contains(.stronglyEmphasized) || weight != .regular
            let font = style.body(size, weight: bold ? .semibold : .regular, italic: italic || intent.contains(.emphasized))
            let piece = String(parsed[run.range].characters)
            result.append(NSAttributedString(string: piece, attributes: style.attributes(font, color: color, paragraph: paragraphStyle)))
        }
        return result
    }
}
