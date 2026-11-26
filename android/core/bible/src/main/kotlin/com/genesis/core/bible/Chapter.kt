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
) {
    val number: Int get() = id.verse
}

/** A section heading from the translation, shown before a verse. */
data class Heading(val beforeVerse: Int, val text: String)

data class Chapter(
    val id: ChapterId,
    val translation: Translation,
    val verses: List<Verse>,
    val headings: List<Heading>,
)
