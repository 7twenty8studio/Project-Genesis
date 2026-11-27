package com.genesis.core.bible

import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.VerseId

/** One verse, verbatim from the database. Never altered. */
data class Verse(
    val id: VerseId,
    /** The text exactly as stored; poetry lines are separated by \n. */
    val text: String,
    /** True when a new paragraph starts at this verse. */
    val startsParagraph: Boolean,
    /** True for poetry, set line by line. */
    val isPoetry: Boolean,
    /** For verses the translation joins ("16–17"): the last verse this one holds. */
    val lastVerse: Int? = null,
) {
    val number: Int get() = id.verse

    /** "16", or "16–17" for joined verses. */
    val numberLabel: String get() = lastVerse?.takeIf { it > number }?.let { "$number–$it" } ?: number.toString()

    /** One line, for copying, sharing and search results (as `plainText` on iOS). */
    val plainText: String get() = text.replace('\n', ' ')

    /** The one line, ready to show beside other text (a Hebrew letter kept from turning it around: ScriptureDirection). */
    val displayText: String get() = com.genesis.core.domain.bible.ScriptureDirection.display(plainText)
}

/** A section heading from the translation, shown before a verse. */
data class Heading(val beforeVerse: Int, val text: String)

/** A footnote from the translation: where its marker goes in the verse's text (UTF-16 offset), and the note. */
data class Footnote(val verse: VerseId, val offset: Int, val text: String)

data class Chapter(
    val id: ChapterId,
    val translation: Translation,
    val verses: List<Verse>,
    val headings: List<Heading>,
    /** Every footnote, shown as small letters that open the note (licensed Bibles require them all). */
    val footnotes: List<Footnote> = emptyList(),
)
