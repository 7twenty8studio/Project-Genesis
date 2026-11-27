package com.genesis.core.domain.original

import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.bible.VersificationMap

/**
 * Hebrew and Greek verse text put together from WordStudy.sqlite's words, as
 * OriginalText.swift: every word verbatim; a word ending in maqaf joins the
 * next with no space, a trailing paseq is set apart by a space, otherwise
 * one space.
 */
object OriginalText {
    const val MAQAF = '־'
    const val PASEQ = '׀'

    data class Segment(val text: String, val separator: String)

    fun segments(words: List<String>): List<Segment> = words.mapIndexed { index, word ->
        val last = index == words.lastIndex
        val joined = word.isEmpty() || word.last() == MAQAF
        Segment(display(word), if (last || joined) "" else " ")
    }

    fun joined(words: List<String>): String = segments(words).joinToString("") { it.text + it.separator }

    /** A word as shown: verbatim, except that a paseq at its end stands apart. */
    fun display(word: String): String {
        if (word.length <= 1 || word.last() != PASEQ) return word
        val text = word.dropLast(1)
        if (text.endsWith(' ')) return word
        return "$text $PASEQ"
    }
}

/** A verse of the Bible being read, verbatim, for the Original parallel. */
data class ParallelVerse(val id: VerseId, val text: String)

/** One row of the Original parallel Bible. */
data class OriginalParallelRow(
    val verse: VerseId,
    val text: String,
    /** Empty when there are none, when shown with an earlier verse, or in a preview. */
    val words: List<OriginalWord>,
    /** Where the original covers more than this verse: the verse numbers it covers. */
    val covers: IntRange?,
    /** The original for this verse was shown with an earlier one. */
    val isContinuation: Boolean,
) {
    val number: Int get() = verse.verse
}

object OriginalParallel {
    /** Free accounts see the original of this many verses of each chapter. */
    const val PREVIEW_VERSES = 2

    fun kjvVerses(verses: List<VerseId>, map: VersificationMap): List<VerseId> = map.alignments(verses).flatMap { it.kjv }

    fun rows(
        verses: List<ParallelVerse>,
        map: VersificationMap,
        words: Map<VerseId, List<OriginalWord>>,
        limit: Int? = null,
    ): List<OriginalParallelRow> {
        val present = verses.map { it.id }.toSet()
        return verses.mapIndexed { index, verse ->
            val alignment = map.alignment(verse.id)
            val first = alignment.verses.firstOrNull { it in present } ?: verse.id
            val isContinuation = first != verse.id
            val shown = limit?.let { index < it } ?: true
            val original = if (isContinuation || !shown) emptyList() else alignment.kjv.flatMap { words[it].orEmpty() }
            val numbers = alignment.verses.filter { it.chapterId == verse.id.chapterId }.map { it.verse }
            val covers = if (numbers.size > 1) numbers.min()..numbers.max() else null
            OriginalParallelRow(verse.id, verse.text, original, covers, isContinuation)
        }
    }
}

/**
 * The copy of a Hebrew or Greek word handed to the speech voice, as
 * PronunciationText on iOS; the word on screen stays exactly as written.
 * Hebrew drops cantillation, meteg and punctuation (a maqaf becomes a
 * space); Greek becomes monotonic.
 */
object PronunciationText {
    fun spoken(word: String, language: OriginalLanguage): String {
        val text = if (language == OriginalLanguage.HEBREW) hebrew(word) else greek(word)
        return text.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
    }

    private fun hebrew(word: String): String = buildString {
        word.codePoints().forEach { c ->
            when {
                c in 0x0591..0x05AF || c == 0x05BD -> Unit
                c == 0x05BE -> append(' ')
                isPunctuation(c) -> Unit
                else -> appendCodePoint(c)
            }
        }
    }

    private fun greek(word: String): String {
        val decomposed = java.text.Normalizer.normalize(word, java.text.Normalizer.Form.NFD)
        val text = buildString {
            decomposed.codePoints().forEach { c ->
                when {
                    c == 0x0313 || c == 0x0314 || c == 0x0345 || c == 0x0304 || c == 0x0306 -> Unit
                    c == 0x0300 || c == 0x0342 -> append('́')
                    isPunctuation(c) -> Unit
                    else -> appendCodePoint(c)
                }
            }
        }
        return java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFC)
    }

    private fun isPunctuation(c: Int): Boolean = when (Character.getType(c).toByte()) {
        Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
        Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
        Character.OTHER_PUNCTUATION -> true
        else -> false
    }
}
