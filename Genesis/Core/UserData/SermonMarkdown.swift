import Foundation

/// Sermon notes are stored as plain Markdown text: **bold**, *italic*,
/// "## " headings, "- " bullets, "1. " numbered lists and "> " quotes. Plain
/// text syncs, searches and exports simply, and nothing is lost if a
/// formatting button is never used. The editor is a plain-text editor with
/// buttons that add or remove these marks; the notes are shown formatted
/// with `blocks(_:)` and SwiftUI's inline Markdown.
///
/// Positions here are counted in Characters.
enum SermonMarkdown {
    enum Format: String, CaseIterable, Identifiable, Sendable {
        case bold, italic, heading, bullet, numbered, quote

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bold: String(localized: "Bold")
            case .italic: String(localized: "Italic")
            case .heading: String(localized: "Heading")
            case .bullet: String(localized: "Bulleted List")
            case .numbered: String(localized: "Numbered List")
            case .quote: String(localized: "Quote")
            }
        }

        var systemImage: String {
            switch self {
            case .bold: "bold"
            case .italic: "italic"
            case .heading: "textformat.size"
            case .bullet: "list.bullet"
            case .numbered: "list.number"
            case .quote: "text.quote"
            }
        }

        /// The marks wrapped around a selection (bold and italic).
        var inlineMark: String? {
            switch self {
            case .bold: "**"
            case .italic: "*"
            default: nil
            }
        }
    }

    /// The text after an edit, and what to select.
    struct Edit: Equatable, Sendable {
        var text: String
        var selection: Range<Int>
    }

    // MARK: Formatting

    static func apply(_ format: Format, to text: String, selection: Range<Int>) -> Edit {
        let count = text.count
        let lower = min(max(0, selection.lowerBound), count)
        let upper = min(max(lower, selection.upperBound), count)
        if let mark = format.inlineMark {
            return toggleInline(mark, in: text, range: lower..<upper)
        }
        return toggleLines(format, in: text, range: lower..<upper)
    }

    private static func toggleInline(_ mark: String, in text: String, range: Range<Int>) -> Edit {
        let characters = Array(text)
        let width = mark.count
        let before = String(characters[max(0, range.lowerBound - width)..<range.lowerBound])
        let after = String(characters[range.upperBound..<min(characters.count, range.upperBound + width)])
        // Italic mustn't mistake bold's "**" for its own mark.
        let beforeMore = range.lowerBound - width - 1 >= 0 ? characters[range.lowerBound - width - 1] : nil
        let afterMore = range.upperBound + width < characters.count ? characters[range.upperBound + width] : nil
        let isWrapped = before == mark && after == mark
            && (width > 1 || (beforeMore != "*" && afterMore != "*"))
        if isWrapped {
            var result = characters
            result.removeSubrange(range.upperBound..<(range.upperBound + width))
            result.removeSubrange((range.lowerBound - width)..<range.lowerBound)
            return Edit(text: String(result), selection: (range.lowerBound - width)..<(range.upperBound - width))
        }
        var result = characters
        result.insert(contentsOf: Array(mark), at: range.upperBound)
        result.insert(contentsOf: Array(mark), at: range.lowerBound)
        return Edit(text: String(result), selection: (range.lowerBound + width)..<(range.upperBound + width))
    }

    private static func toggleLines(_ format: Format, in text: String, range: Range<Int>) -> Edit {
        var lines = text.components(separatedBy: "\n")
        // Which lines the selection touches.
        var start = 0
        var touched: [Int] = []
        for (index, line) in lines.enumerated() {
            let end = start + line.count
            let touches = range.isEmpty
                ? (range.lowerBound >= start && range.lowerBound <= end)
                : (range.lowerBound <= end && range.upperBound > start)
            if touches { touched.append(index) }
            start = end + 1
        }
        if touched.isEmpty { touched = [max(0, lines.count - 1)] }

        let removing = touched.allSatisfy { lineFormat(of: lines[$0]) == format }
        for (position, index) in touched.enumerated() {
            let content = stripLinePrefix(lines[index])
            lines[index] = removing ? content : prefix(for: format, number: position + 1) + content
        }

        let firstStart = lines[..<touched[0]].reduce(0) { $0 + $1.count + 1 }
        let lastIndex = touched[touched.count - 1]
        let lastEnd = lines[...lastIndex].reduce(0) { $0 + $1.count + 1 } - 1
        let newText = lines.joined(separator: "\n")
        let selection = range.isEmpty ? lastEnd..<lastEnd : firstStart..<lastEnd
        return Edit(text: newText, selection: selection)
    }

    private static func prefix(for format: Format, number: Int) -> String {
        switch format {
        case .heading: "## "
        case .bullet: "- "
        case .numbered: "\(number). "
        case .quote: "> "
        case .bold, .italic: ""
        }
    }

    /// The line format a line starts with, if any.
    static func lineFormat(of line: String) -> Format? {
        lineParts(line).format
    }

    /// The line without its heading, list or quote mark.
    static func stripLinePrefix(_ line: String) -> String {
        lineParts(line).content
    }

    private static func lineParts(_ line: String) -> (format: Format?, content: String, number: Int?) {
        let hashes = line.prefix { $0 == "#" }.count
        if (1...3).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") {
            return (.heading, String(line.dropFirst(hashes + 1)), nil)
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("\u{2022} ") {
            return (.bullet, String(line.dropFirst(2)), nil)
        }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        if (1...3).contains(digits.count), line.dropFirst(digits.count).hasPrefix(". ") {
            return (.numbered, String(line.dropFirst(digits.count + 2)), Int(digits))
        }
        if line.hasPrefix("> ") {
            return (.quote, String(line.dropFirst(2)), nil)
        }
        if line == ">" {
            return (.quote, "", nil)
        }
        return (nil, line, nil)
    }

    // MARK: Inserting a reference

    /// Puts `snippet` (e.g. "John 3:16") at the cursor, with a space either
    /// side where needed, or on a new line at the end when there's no cursor.
    static func inserting(_ snippet: String, into text: String, at offset: Int?) -> Edit {
        var characters = Array(text)
        guard let offset else {
            var insertion = snippet
            if let last = characters.last, last != "\n" { insertion = "\n" + insertion }
            let result = text + insertion
            return Edit(text: result, selection: result.count..<result.count)
        }
        let position = min(max(0, offset), characters.count)
        var insertion = snippet
        if position > 0, !characters[position - 1].isWhitespace { insertion = " " + insertion }
        if position < characters.count, !characters[position].isWhitespace { insertion += " " }
        characters.insert(contentsOf: Array(insertion), at: position)
        let end = position + insertion.count
        return Edit(text: String(characters), selection: end..<end)
    }

    // MARK: Reading

    struct Block: Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            case heading, bullet, numbered(Int), quote, paragraph
        }
        let kind: Kind
        /// The line's text, still with its inline marks (bold, italic).
        let text: String
    }

    /// The notes as lines to show formatted. Blank lines are left out.
    static func blocks(_ text: String) -> [Block] {
        text.components(separatedBy: "\n").compactMap { line -> Block? in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let parts = lineParts(line)
            let kind: Block.Kind = switch parts.format {
            case .heading: .heading
            case .bullet: .bullet
            case .numbered: .numbered(parts.number ?? 1)
            case .quote: .quote
            default: .paragraph
            }
            return Block(kind: kind, text: parts.content)
        }
    }

    /// The notes without any marks, for search and previews.
    static func plainText(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { stripLinePrefix($0) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "__", with: "")
    }

    /// One line's inline Markdown (bold, italic) as styled text; anything that
    /// doesn't parse is shown as typed.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
