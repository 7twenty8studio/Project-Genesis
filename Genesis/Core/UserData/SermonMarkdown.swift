import Foundation

/// Sermon notes are stored as plain Markdown text: **bold**, *italic*,
/// "## " headings, "- " bullets, "1. " numbered lists and "> " quotes. Plain
/// text syncs, searches and exports simply. The editor shows the notes
/// formatted (`SermonRichText`); the PDF export reads them with `blocks(_:)`.
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
    }

    /// The text after an edit, and what to select.
    struct Edit: Equatable, Sendable {
        var text: String
        var selection: Range<Int>
    }

    // MARK: Lines

    /// The line format a line starts with, if any.
    static func lineFormat(of line: String) -> Format? {
        lineParts(line).format
    }

    /// The line without its heading, list or quote mark.
    static func stripLinePrefix(_ line: String) -> String {
        lineParts(line).content
    }

    /// A list line's mark as typed ("- ", "\u{2022} ", "3. "), or nil.
    static func listPrefix(of line: String) -> String? {
        let parts = lineParts(line)
        guard parts.format == .bullet || parts.format == .numbered else { return nil }
        return String(line.dropLast(parts.content.count))
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
            .replacingOccurrences(of: "\\*", with: "\u{1}")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "\u{1}", with: "*")
    }

    // MARK: Bold and italic

    /// A stretch of a line's text that is bold, italic, both or neither.
    struct Span: Equatable, Sendable {
        var text: String
        var bold = false
        var italic = false
    }

    /// One line's text split where bold and italic start and end. A mark
    /// with no partner is kept as typed, and "\*" is a plain asterisk.
    static func spans(_ line: String) -> [Span] {
        let characters = Array(line)
        var spans: [Span] = []
        var current = ""
        var bold = false
        var italic = false
        func flush() {
            if !current.isEmpty { spans.append(Span(text: current, bold: bold, italic: italic)) }
            current = ""
        }
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count, characters[index + 1] == "*" {
                current.append("*")
                index += 2
                continue
            }
            guard character == "*" else {
                current.append(character)
                index += 1
                continue
            }
            var run = 0
            while index + run < characters.count, characters[index + run] == "*" { run += 1 }
            let width = min(run, 3)
            let togglesBold = width >= 2
            let togglesItalic = width != 2
            let closes = (!togglesBold || bold) && (!togglesItalic || italic)
                && index > 0 && !characters[index - 1].isWhitespace
            let opens = (!togglesBold || !bold) && (!togglesItalic || !italic)
                && index + width < characters.count && !characters[index + width].isWhitespace
                && hasCloser(characters, from: index + width, width: width)
            if closes || opens {
                flush()
                if togglesBold { bold.toggle() }
                if togglesItalic { italic.toggle() }
                index += width
            } else {
                current.append(contentsOf: String(repeating: "*", count: run))
                index += run
            }
        }
        flush()
        return spans
    }

    private static func hasCloser(_ characters: [Character], from start: Int, width: Int) -> Bool {
        var index = start
        while index < characters.count {
            if characters[index] == "\\" {
                index += 2
                continue
            }
            guard characters[index] == "*" else {
                index += 1
                continue
            }
            var run = 0
            while index + run < characters.count, characters[index + run] == "*" { run += 1 }
            if run >= width, index > start, !characters[index - 1].isWhitespace { return true }
            index += run
        }
        return false
    }

    /// Spans back to Markdown: marks hug the words (spaces stay outside) and
    /// typed asterisks are escaped.
    static func markdown(_ spans: [Span]) -> String {
        var merged: [Span] = []
        for span in spans where !span.text.isEmpty {
            if let last = merged.last, last.bold == span.bold, last.italic == span.italic {
                merged[merged.count - 1].text += span.text
            } else {
                merged.append(span)
            }
        }
        return merged.map { span in
            let text = span.text.replacingOccurrences(of: "*", with: "\\*")
            let mark = span.bold && span.italic ? "***" : span.bold ? "**" : span.italic ? "*" : ""
            let core = text.trimmingCharacters(in: .whitespaces)
            guard !mark.isEmpty, !core.isEmpty else { return text }
            let leading = String(text.prefix { $0.isWhitespace })
            let trailing = String(text.reversed().prefix { $0.isWhitespace }.reversed())
            return leading + mark + core + mark + trailing
        }.joined()
    }

    /// The spans without their first `count` characters.
    static func dropping(_ count: Int, from spans: [Span]) -> [Span] {
        var remaining = count
        return spans.compactMap { span in
            guard remaining > 0 else { return span }
            let dropped = min(remaining, span.text.count)
            remaining -= dropped
            var rest = span
            rest.text = String(span.text.dropFirst(dropped))
            return rest.text.isEmpty ? nil : rest
        }
    }

    /// One line's inline Markdown (bold, italic) as styled text; anything that
    /// doesn't parse is shown as typed.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
