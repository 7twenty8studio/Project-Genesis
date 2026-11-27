package com.genesis.core.bible

import com.genesis.core.domain.bible.BibleBook
import com.genesis.core.domain.bible.PassageReference
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.search.FullTextQuery
import com.genesis.core.domain.search.SearchOrder
import com.genesis.core.domain.search.SearchScope

/** Everything found for one search: a reference, matching books and verses. */
data class SearchResults(
    val text: String = "",
    val reference: PassageReference? = null,
    val bookSuggestions: List<BibleBook> = emptyList(),
    val verses: List<Verse> = emptyList(),
    val totalMatches: Int = 0,
    val terms: List<String> = emptyList(),
) {
    val isEmpty: Boolean get() = reference == null && bookSuggestions.isEmpty() && verses.isEmpty()
}

/** One search over a translation, as BibleSearch on iOS. Off the main thread. */
object BibleSearch {
    fun run(
        text: String,
        repository: BibleRepository,
        scope: SearchScope = SearchScope.WholeBible,
        order: SearchOrder = SearchOrder.RELEVANCE,
        limit: Int = 200,
    ): SearchResults {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return SearchResults()
        val portugueseFirst = repository.translation.language == "pt"
        val reference = ReferenceParser.parse(trimmed, portugueseFirst)
        val books = if (reference == null) ReferenceParser.booksMatching(trimmed, portugueseFirst).take(5) else emptyList()
        val query = FullTextQuery.of(text)
            ?: return SearchResults(text = trimmed, reference = reference, bookSuggestions = books)
        val verses = repository.search(query.matchExpression, scope, order, limit)
        val total = if (verses.size < limit) verses.size else repository.countMatches(query.matchExpression, scope)
        return SearchResults(trimmed, reference, books, verses, total, query.terms)
    }
}
