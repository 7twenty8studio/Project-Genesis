import Foundation

/// Everything found for one search: a direct reference ("John 3:16"),
/// matching book names, and full-text verse matches.
struct SearchResults: Sendable {
    let text: String
    let reference: PassageReference?
    let bookSuggestions: [BibleBook]
    let verses: [Verse]
    let totalMatches: Int
    let terms: [String]

    static let empty = SearchResults(text: "", reference: nil, bookSuggestions: [], verses: [], totalMatches: 0, terms: [])

    var isEmpty: Bool { reference == nil && bookSuggestions.isEmpty && verses.isEmpty }
}

enum BibleSearch {
    /// Runs a search. Safe to call off the main actor; typically 1–5 ms.
    static func run(
        _ text: String,
        in repository: BibleRepository,
        scope: SearchScope = .wholeBible,
        order: SearchOrder = .relevance,
        limit: Int = 200
    ) throws -> SearchResults {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let reference = ReferenceParser.parse(trimmed)
        let books = reference == nil ? Array(ReferenceParser.books(matching: trimmed).prefix(5)) : []

        guard let query = FullTextQuery(text) else {
            return SearchResults(text: trimmed, reference: reference, bookSuggestions: books, verses: [], totalMatches: 0, terms: [])
        }
        // A pure reference like "John 3:16" still gets text matches for words
        // such as "John", which is harmless and sometimes useful.
        let verses = try repository.search(matchExpression: query.matchExpression, scope: scope, order: order, limit: limit)
        let total = try verses.count < limit
            ? verses.count
            : repository.countMatches(matchExpression: query.matchExpression, scope: scope)
        return SearchResults(
            text: trimmed,
            reference: reference,
            bookSuggestions: books,
            verses: verses,
            totalMatches: total,
            terms: query.terms
        )
    }
}
