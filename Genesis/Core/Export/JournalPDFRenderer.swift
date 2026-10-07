import UIKit

/// Typesets a `JournalExport` as a book-like PDF: a title page, then each
/// prayer or sermon with its notes (Markdown formatting kept), passages
/// verbatim with the translation's abbreviation, photos and Pencil pages
/// scaled to the page, recordings and PDFs listed, and a small "Made with
/// Genesis" footer. Uses the reader's typeface and generous margins.
///
/// Ligatures are turned off so the PDF's text (and so the verses) can be
/// searched and copied exactly as written.
struct JournalPDFRenderer: Sendable {
    var pageSize: CGSize
    /// Left and right margins; the top and bottom ones are `topMargin` and `bottomMargin`.
    var sideMargin: CGFloat = 76
    var topMargin: CGFloat = 72
    var bottomMargin: CGFloat = 84

    init(pageSize: CGSize = JournalPDFRenderer.paperSize()) {
        self.pageSize = pageSize
    }

    /// US Letter where it's the custom (the US and Canada), A4 elsewhere.
    static func paperSize(region: Locale.Region? = Locale.current.region) -> CGSize {
        let letter: Set<String> = ["US", "CA"]
        return letter.contains(region?.identifier ?? "") ? CGSize(width: 612, height: 792) : CGSize(width: 595.2, height: 841.8)
    }

    func render(_ export: JournalExport) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: export.title,
            kCGPDFContextCreator as String: "Genesis",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            let content = CGRect(
                x: sideMargin,
                y: topMargin,
                width: pageSize.width - 2 * sideMargin,
                height: pageSize.height - topMargin - bottomMargin
            )
            let page = PDFPageWriter(context: context, pageSize: pageSize, content: content, style: PDFStyle(font: export.font))
            page.drawTitlePage(export)
            for (index, entry) in export.entries.enumerated() {
                page.draw(entry, isFirst: index == 0)
            }
        }
    }
}

/// Fonts, colours and paragraph styles for the export.
struct PDFStyle {
    let font: ReaderFont
    let ink = UIColor(white: 0.13, alpha: 1)
    let quiet = UIColor(white: 0.42, alpha: 1)
    let accent = UIColor(red: 0.55, green: 0.42, blue: 0.22, alpha: 1)

    func body(_ size: CGFloat = 12, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        font.uiFont(size: size, weight: weight, italic: italic)
    }

    func paragraph(spacing: CGFloat = 6, indent: CGFloat = 0, alignment: NSTextAlignment = .natural, lineHeight: CGFloat = 1.25) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeight
        style.paragraphSpacing = spacing
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        style.alignment = alignment
        style.hyphenationFactor = 0
        return style
    }

    func attributes(_ font: UIFont, color: UIColor? = nil, paragraph: NSParagraphStyle? = nil) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color ?? ink,
            .paragraphStyle: paragraph ?? self.paragraph(),
            .ligature: 0,
        ]
    }
}
