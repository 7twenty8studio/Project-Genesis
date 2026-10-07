import SwiftUI

/// A heading or quote line in the notes editor. Lists are visible text
/// ("• ", "1. "), so they need no mark.
enum SermonLineStyle: String, Hashable, Sendable {
    case heading, quote
}

/// Marks heading and quote lines in the editor's text. Only the editor uses
/// it: notes are saved as Markdown.
enum SermonLineStyleAttribute: AttributedStringKey {
    typealias Value = SermonLineStyle
    static let name = "genesis.sermonLineStyle"
}

extension SermonMarkdown.Format {
    var lineStyle: SermonLineStyle? {
        switch self {
        case .heading: .heading
        case .quote: .quote
        default: nil
        }
    }
}

/// The sermon notes editor shows the notes formatted while they're saved as
/// Markdown (`SermonMarkdown`): bold and italic are fonts, headings and
/// quotes a line attribute, lists the visible marks "• " and "1. ". This
/// converts between the two and keeps each line's look whole as people
/// type. Positions are counted in Characters.
enum SermonRichText {
    typealias FontAttribute = AttributeScopes.SwiftUIAttributes.FontAttribute
    typealias ColorAttribute = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute

    static let bullet = "\u{2022} "

    /// The editor's fonts and the quote color.
    struct Style {
        var largeText = false
        var quoteColor = Color.secondary

        var body: Font { largeText ? .title2 : .body }
        var heading: Font { .system(largeText ? .title : .title3, design: .serif, weight: .semibold) }
        func quote(bold: Bool) -> Font { body.italic().bold(bold) }

        /// What a new line typed in this style starts with.
        func typingAttributes(_ lineStyle: SermonLineStyle?) -> AttributeContainer {
            var attributes = AttributeContainer()
            attributes[SermonLineStyleAttribute.self] = lineStyle
            switch lineStyle {
            case .heading: attributes[FontAttribute.self] = heading
            case .quote:
                attributes[FontAttribute.self] = quote(bold: false)
                attributes[ColorAttribute.self] = quoteColor
            case nil: break
            }
            return attributes
        }
    }

    // MARK: Markdown to the editor

    static func attributed(_ markdown: String, style: Style) -> AttributedString {
        var result = AttributedString()
        for (index, line) in markdown.components(separatedBy: "\n").enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            result.append(attributedLine(line, style: style))
        }
        return result
    }

    private static func attributedLine(_ line: String, style: Style) -> AttributedString {
        let lineStyle = SermonMarkdown.lineFormat(of: line)?.lineStyle
        var result = AttributedString()
        if lineStyle == nil, let prefix = SermonMarkdown.listPrefix(of: line) {
            result.append(AttributedString(prefix.hasSuffix(". ") ? prefix : bullet))
        }
        for span in SermonMarkdown.spans(SermonMarkdown.stripLinePrefix(line)) {
            var attributes = style.typingAttributes(lineStyle)
            switch lineStyle {
            case .heading: break
            case .quote: attributes[FontAttribute.self] = style.quote(bold: span.bold)
            case nil:
                if span.bold || span.italic {
                    attributes[FontAttribute.self] = style.body.bold(span.bold).italic(span.italic)
                }
            }
            result.append(AttributedString(span.text, attributes: attributes))
        }
        return result
    }

    // MARK: The editor to Markdown

    static func markdown(_ text: AttributedString, context: Font.Context) -> String {
        var lines: [String] = []
        var spans: [SermonMarkdown.Span] = []
        var lineStyle: SermonLineStyle?
        var atLineStart = true
        func endLine() {
            lines.append(markdownLine(spans, style: lineStyle))
            spans = []
            lineStyle = nil
            atLineStart = true
        }
        for run in text.runs {
            let resolved = run[FontAttribute.self]?.resolve(in: context)
            let pieces = String(text[run.range].characters).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, piece) in pieces.enumerated() {
                if index > 0 { endLine() }
                guard !piece.isEmpty else { continue }
                if atLineStart {
                    lineStyle = run[SermonLineStyleAttribute.self]
                    atLineStart = false
                }
                spans.append(.init(text: String(piece), bold: resolved?.isBold ?? false, italic: resolved?.isItalic ?? false))
            }
        }
        endLine()
        return lines.joined(separator: "\n")
    }

    private static func markdownLine(_ spans: [SermonMarkdown.Span], style: SermonLineStyle?) -> String {
        switch style {
        case .heading:
            return "## " + SermonMarkdown.markdown(spans.map { .init(text: $0.text) })
        case .quote:
            return "> " + SermonMarkdown.markdown(spans.map { .init(text: $0.text, bold: $0.bold) })
        case nil:
            let plain = spans.map(\.text).joined()
            guard let prefix = SermonMarkdown.listPrefix(of: plain) else { return SermonMarkdown.markdown(spans) }
            let rest = SermonMarkdown.dropping(prefix.count, from: spans)
            return (prefix == bullet ? "- " : prefix) + SermonMarkdown.markdown(rest)
        }
    }

    // MARK: Keeping lines whole

    /// Each line takes the style of its first character (or `forcing`'s, by
    /// line number), so typing, pasting or joining lines keeps a heading or
    /// quote whole. Line breaks carry no style, so a new line starts plain.
    static func normalized(
        _ text: AttributedString,
        style: Style,
        context: Font.Context,
        forcing: [Int: SermonLineStyle?] = [:]
    ) -> AttributedString {
        var result = AttributedString()
        var lineIndex = 0
        var lineStyle: SermonLineStyle?
        var atLineStart = true
        for run in text.runs {
            let runStyle = run[SermonLineStyleAttribute.self]
            let font = run[FontAttribute.self]
            let isBold = font?.resolve(in: context).isBold ?? false
            let pieces = String(text[run.range].characters).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, piece) in pieces.enumerated() {
                if index > 0 {
                    var lineBreak = run.attributes
                    lineBreak[SermonLineStyleAttribute.self] = nil
                    lineBreak[FontAttribute.self] = nil
                    lineBreak[ColorAttribute.self] = nil
                    result.append(AttributedString("\n", attributes: lineBreak))
                    lineIndex += 1
                    atLineStart = true
                }
                guard !piece.isEmpty else { continue }
                if atLineStart {
                    lineStyle = forcing[lineIndex] ?? runStyle
                    atLineStart = false
                }
                var attributes = run.attributes
                attributes[SermonLineStyleAttribute.self] = lineStyle
                switch lineStyle {
                case .heading:
                    attributes[FontAttribute.self] = style.heading
                    attributes[ColorAttribute.self] = nil
                case .quote:
                    attributes[FontAttribute.self] = style.quote(bold: isBold && runStyle != .heading)
                    attributes[ColorAttribute.self] = style.quoteColor
                case nil:
                    if runStyle != nil || font == style.heading {
                        attributes[FontAttribute.self] = isBold && runStyle == .quote ? style.body.bold() : nil
                        attributes[ColorAttribute.self] = nil
                    }
                }
                result.append(AttributedString(String(piece), attributes: attributes))
            }
        }
        return result
    }

    // MARK: Line formats

    /// Turns a heading, quote or list on for every line the selection
    /// touches, or off when they all have it. Returns the text and what to
    /// select: the end of the line for a cursor, otherwise the lines.
    static func toggling(
        _ format: SermonMarkdown.Format,
        in text: AttributedString,
        selection: Range<Int>,
        style: Style,
        context: Font.Context
    ) -> (text: AttributedString, selection: Range<Int>) {
        let lines = lineRanges(in: text)
        let plainLines = lines.map { String(text[$0].characters) }
        var touched: [Int] = []
        var start = 0
        for (index, line) in plainLines.enumerated() {
            let end = start + line.count
            let touches = selection.isEmpty
                ? (selection.lowerBound >= start && selection.lowerBound <= end)
                : (selection.lowerBound <= end && selection.upperBound > start)
            if touches { touched.append(index) }
            start = end + 1
        }
        if touched.isEmpty { touched = [lines.count - 1] }

        let target = format.lineStyle
        let removing = if let target {
            touched.allSatisfy { lineStyle(of: text[lines[$0]]) == target }
        } else {
            touched.allSatisfy { SermonMarkdown.lineFormat(of: plainLines[$0]) == format }
        }

        var result = AttributedString()
        var forcing: [Int: SermonLineStyle?] = [:]
        var firstStart = 0
        var lastEnd = 0
        var offset = 0
        for (index, range) in lines.enumerated() {
            if index > 0 {
                result.append(AttributedString("\n"))
                offset += 1
            }
            var line = AttributedString(text[range])
            if let position = touched.firstIndex(of: index) {
                if index == touched.first { firstStart = offset }
                if target == nil || !removing, let mark = SermonMarkdown.listPrefix(of: plainLines[index]) {
                    line = AttributedString(line[line.characters.index(line.startIndex, offsetBy: mark.count)...])
                }
                if target == nil, !removing {
                    var marked = AttributedString(format == .bullet ? bullet : "\(position + 1). ")
                    marked.append(line)
                    line = marked
                }
                if target != nil || !removing {
                    forcing.updateValue(removing ? nil : target, forKey: index)
                }
                offset += line.characters.count
                if index == touched.last { lastEnd = offset }
            } else {
                offset += line.characters.count
            }
            result.append(line)
        }
        let restyled = normalized(result, style: style, context: context, forcing: forcing)
        return (restyled, selection.isEmpty ? lastEnd..<lastEnd : firstStart..<lastEnd)
    }

    // MARK: Return

    /// When `new` is `old` with a line break typed just before `cursor`, the
    /// line that was ended: where it starts and its text.
    static func endedLine(old: String, new: String, cursor: Int) -> (start: Int, text: String)? {
        guard new.count == old.count + 1, cursor > 0, cursor <= new.count else { return nil }
        var characters = Array(new)
        guard characters[cursor - 1] == "\n" else { return nil }
        var start = cursor - 1
        while start > 0, characters[start - 1] != "\n" { start -= 1 }
        let line = String(characters[start..<(cursor - 1)])
        characters.remove(at: cursor - 1)
        guard String(characters) == old else { return nil }
        return (start, line)
    }

    /// The mark a list's next item starts with after Return, or nil. An
    /// empty item ends the list instead (`endsList`).
    static func continuation(of line: String) -> String? {
        guard let mark = SermonMarkdown.listPrefix(of: line), line.count > mark.count else { return nil }
        if mark.hasSuffix(". "), let number = Int(mark.dropLast(2)) { return "\(number + 1). " }
        return mark
    }

    static func endsList(_ line: String) -> Bool {
        !line.isEmpty && SermonMarkdown.listPrefix(of: line) == line
    }

    // MARK: Positions

    static func lineRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
        let characters = text.characters
        var ranges: [Range<AttributedString.Index>] = []
        var start = characters.startIndex
        var index = characters.startIndex
        while index < characters.endIndex {
            if characters[index] == "\n" {
                ranges.append(start..<index)
                start = characters.index(after: index)
            }
            index = characters.index(after: index)
        }
        ranges.append(start..<characters.endIndex)
        return ranges
    }

    static func lineStyle(of line: AttributedSubstring) -> SermonLineStyle? {
        line.runs.first.flatMap { $0[SermonLineStyleAttribute.self] }
    }

    /// The style of the line starting at `offset`.
    static func lineStyle(at offset: Int, in text: AttributedString) -> SermonLineStyle? {
        let characters = text.characters
        guard offset < characters.count else { return nil }
        let index = characters.index(characters.startIndex, offsetBy: offset)
        guard characters[index] != "\n" else { return nil }
        return text[index..<characters.index(after: index)][SermonLineStyleAttribute.self]
    }

    static func isEmptyLine(at offset: Int, in text: AttributedString) -> Bool {
        let characters = Array(text.characters)
        guard offset >= 0, offset <= characters.count else { return false }
        return (offset == 0 || characters[offset - 1] == "\n")
            && (offset == characters.count || characters[offset] == "\n")
    }

    static func replacing(_ range: Range<Int>, with replacement: AttributedString, in text: AttributedString) -> AttributedString {
        var result = text
        let characters = result.characters
        let lower = characters.index(characters.startIndex, offsetBy: range.lowerBound)
        let upper = characters.index(lower, offsetBy: range.count)
        result.replaceSubrange(lower..<upper, with: replacement)
        return result
    }

    /// The selection as Character offsets: from its start to its end.
    static func offsets(of selection: AttributedTextSelection, in text: AttributedString) -> Range<Int> {
        let characters = text.characters
        func offset(_ index: AttributedString.Index) -> Int {
            characters.distance(from: characters.startIndex, to: min(index, characters.endIndex))
        }
        switch selection.indices(in: text) {
        case let .insertionPoint(index):
            let position = offset(index)
            return position..<position
        case let .ranges(ranges):
            guard let first = ranges.ranges.first, let last = ranges.ranges.last else {
                return characters.count..<characters.count
            }
            return offset(first.lowerBound)..<offset(last.upperBound)
        }
    }

    static func selection(
        _ range: Range<Int>,
        in text: AttributedString,
        typingAttributes: AttributeContainer? = nil
    ) -> AttributedTextSelection {
        let characters = text.characters
        let count = characters.count
        let lowerOffset = min(max(0, range.lowerBound), count)
        let upperOffset = min(max(lowerOffset, range.upperBound), count)
        let lower = characters.index(characters.startIndex, offsetBy: lowerOffset)
        let upper = characters.index(characters.startIndex, offsetBy: upperOffset)
        return lower == upper
            ? AttributedTextSelection(insertionPoint: lower, typingAttributes: typingAttributes)
            : AttributedTextSelection(range: lower..<upper)
    }
}
