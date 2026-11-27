package com.genesis.core.domain.search

import com.genesis.core.domain.bible.Testament
import com.genesis.core.domain.bible.VerseId

/**
 * Turns what a person types into a safe SQLite FTS5 match expression, as
 * FullTextQuery.swift on iOS:
 *
 * - Words are ANDed together: `faith hope` finds verses containing both.
 * - Text wrapped in quotes is an exact phrase: `"the word was god"`.
 * - The last word matches as a prefix while typing: `forgiv` finds "forgiveness".
 *
 * Typed text never reaches FTS5 syntax: every term is reduced to letters and
 * digits and quoted, so OR, NEAR or `*` are plain words.
 */
data class FullTextQuery(val matchExpression: String, val terms: List<String>, val isPhrase: Boolean) {
    companion object {
        private val quotes = setOf('"', '“', '”')

        fun of(input: String, prefixLastTerm: Boolean = true): FullTextQuery? {
            val trimmed = input.trim()
            val isPhrase = trimmed.length > 1 && trimmed.first() in quotes && trimmed.last() in quotes
            val terms = terms(trimmed).ifEmpty { return null }
            val expression = if (isPhrase) {
                "\"" + terms.joinToString(" ") + "\""
            } else {
                // A trailing space means the last word is finished, so no prefix.
                val wantsPrefix = prefixLastTerm && input.lastOrNull()?.isWhitespace() != true
                terms.mapIndexed { index, term ->
                    if (index == terms.lastIndex && wantsPrefix && term.length >= 2) "\"$term\"*" else "\"$term\""
                }.joinToString(" ")
            }
            return FullTextQuery(expression, terms, isPhrase)
        }

        /** Lowercase words of letters and digits. */
        fun terms(text: String): List<String> =
            text.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
    }
}

/** Which verses a search looks through, as SearchScope on iOS. */
sealed interface SearchScope {
    data object WholeBible : SearchScope
    data class InTestament(val testament: Testament) : SearchScope
    data class Book(val book: Int) : SearchScope

    /** Inclusive verse-id bounds. */
    val idRange: IntRange
        get() = when (this) {
            WholeBible -> VerseId(1, 0, 0).rawValue..VerseId(66, 999, 999).rawValue
            is InTestament -> if (testament == Testament.OLD) {
                VerseId(1, 0, 0).rawValue..VerseId(39, 999, 999).rawValue
            } else {
                VerseId(40, 0, 0).rawValue..VerseId(66, 999, 999).rawValue
            }
            is Book -> VerseId(book, 0, 0).rawValue..VerseId(book, 999, 999).rawValue
        }
}

enum class SearchOrder { RELEVANCE, CANONICAL }

object SearchHighlighter {
    /**
     * Ranges of words in [text] that match any term. Matching is by shared word
     * start, so "loved" highlights for "love" and back, roughly as the index
     * stems them.
     */
    fun matchRanges(text: String, terms: List<String>): List<IntRange> {
        if (terms.isEmpty()) return emptyList()
        return Regex("[\\p{L}\\p{N}]+").findAll(text)
            .filter { match -> terms.any { matches(match.value.lowercase(), it) } }
            .map { it.range }
            .toList()
    }

    private fun matches(word: String, term: String): Boolean {
        if (word.startsWith(term)) return true
        // Stem differences such as "forgave"/"forgive" or "lovest"/"love".
        val stem = maxOf(3, term.length - 2)
        if (word.length < stem || term.length < stem) return false
        return word.take(stem) == term.take(stem)
    }
}
