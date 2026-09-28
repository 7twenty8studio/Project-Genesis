import Foundation

/// Turns what a person types into a safe SQLite FTS5 match expression.
///
/// - Words are ANDed together: `faith hope` finds verses containing both.
/// - Text wrapped in quotes is an exact phrase: `"the word was god"`.
/// - The last word matches as a prefix while typing: `forgiv` finds "forgiveness".
///
/// User text never reaches FTS5 syntax directly: every term is reduced to
/// letters and digits and then quoted, so operators like OR, NEAR or `*`
/// typed by the user are treated as plain words.
struct FullTextQuery: Equatable, Sendable {
    let matchExpression: String
    /// Lowercased search terms, for highlighting matches in results.
    let terms: [String]
    let isPhrase: Bool

    init?(_ input: String, prefixLastTerm: Bool = true) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let quoteCharacters: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]
        let isPhrase = trimmed.count > 1
            && quoteCharacters.contains(trimmed.first!)
            && quoteCharacters.contains(trimmed.last!)

        let terms = Self.terms(in: trimmed)
        guard !terms.isEmpty else { return nil }

        self.terms = terms
        self.isPhrase = isPhrase

        if isPhrase {
            matchExpression = "\"" + terms.joined(separator: " ") + "\""
        } else {
            // A trailing space means the last word is finished, so no prefix.
            let wantsPrefix = prefixLastTerm && !(input.last?.isWhitespace ?? false)
            matchExpression = terms.enumerated().map { index, term in
                let isLast = index == terms.count - 1
                return isLast && wantsPrefix && term.count >= 2 ? "\"\(term)\"*" : "\"\(term)\""
            }.joined(separator: " ")
        }
    }

    /// Splits text into lowercase words of letters and digits.
    static func terms(in text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

enum SearchHighlighter {
    /// Ranges of words in `text` that match any search term. Matching is by
    /// shared word start, so "loved" highlights for "love" and vice versa,
    /// roughly mirroring the stemming the index applies.
    static func matchRanges(in text: String, terms: [String]) -> [Range<String.Index>] {
        guard !terms.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter || text[index].isNumber else {
                index = text.index(after: index)
                continue
            }
            let start = index
            while index < text.endIndex, text[index].isLetter || text[index].isNumber {
                index = text.index(after: index)
            }
            let word = text[start..<index].lowercased()
            if terms.contains(where: { matches(word: word, term: $0) }) {
                ranges.append(start..<index)
            }
        }
        return ranges
    }

    private static func matches(word: String, term: String) -> Bool {
        if word.hasPrefix(term) { return true }
        // Allow stem differences such as "forgave"/"forgive" or "lovest"/"love".
        let stemLength = max(3, term.count - 2)
        guard word.count >= stemLength, term.count >= stemLength else { return false }
        return word.prefix(stemLength) == term.prefix(stemLength)
    }
}
