import Foundation

/// The study packs' light Markdown: one paragraph per blank line, "## "
/// for a heading, "- " for a list item, and inline only *italic*,
/// **bold** and links to verses ("verse:START-END") or articles
/// ("article:PACK/ID"). Everything else is escaped with a backslash.
enum StudyMarkup {
    enum Block: Hashable, Sendable {
        case heading(String)
        case listItem(String)
        case paragraph(String)
    }

    /// Where a link in a study text goes.
    enum Link: Hashable, Sendable {
        case verses(StudyRange)
        case article(pack: String, id: String)
    }

    static func blocks(_ text: String) -> [Block] {
        text.components(separatedBy: "\n\n").compactMap { raw in
            let block = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !block.isEmpty else { return nil }
            if block.hasPrefix("## ") { return .heading(String(block.dropFirst(3))) }
            if block.hasPrefix("- ") { return .listItem(String(block.dropFirst(2))) }
            return .paragraph(block)
        }
    }

    /// The inline Markdown as styled text; links keep their verse: and
    /// article: URLs for the view to open.
    static func attributed(_ inline: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: inline, options: options)) ?? AttributedString(inline)
    }

    /// The text without any markup, for search and accessibility.
    static func plain(_ inline: String) -> String {
        String(attributed(inline).characters)
    }

    static func link(_ url: URL) -> Link? {
        switch url.scheme {
        case "verse":
            let parts = url.absoluteString.dropFirst("verse:".count).split(separator: "-")
            guard let first = parts.first.flatMap({ Int($0) }), first > 1_000_000 else { return nil }
            let last = parts.count > 1 ? Int(parts[1]) ?? first : first
            return .verses(StudyRange(start: VerseID(rawValue: first), end: VerseID(rawValue: last)))
        case "article":
            let path = url.absoluteString.dropFirst("article:".count)
            guard let slash = path.firstIndex(of: "/") else { return nil }
            let pack = String(path[..<slash])
            let id = String(path[path.index(after: slash)...]).removingPercentEncoding ?? ""
            guard !pack.isEmpty, !id.isEmpty else { return nil }
            return .article(pack: pack, id: id)
        default:
            return nil
        }
    }

    /// Lower case without accents, as the packs' sort keys are.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Escapes LIKE's wildcards (with "\" as the escape character).
    static func likeEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
