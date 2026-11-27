package com.genesis.core.domain.study

import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId

/**
 * Selected verses as plain text to copy or share, as
 * ChapterTextBuilder.shareText on iOS: the words exactly as stored, in
 * quotation marks, then the reference and the translation's abbreviation.
 * Several verses keep their numbers.
 */
object ShareText {
    fun of(verses: List<Pair<VerseId, String>>, abbreviation: String, language: String): String {
        if (verses.isEmpty()) return ""
        val sorted = verses.sortedBy { it.first.rawValue }
        val body = sorted.joinToString(" ") { (id, text) -> if (sorted.size > 1) "${id.verse} $text" else text }
        val reference = ReferenceParser.describe(sorted.first().first.rawValue, sorted.last().first.rawValue, language)
        return "“$body”\n— $reference ($abbreviation)"
    }
}
