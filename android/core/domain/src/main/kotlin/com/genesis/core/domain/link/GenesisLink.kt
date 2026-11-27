package com.genesis.core.domain.link

import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.VerseId

/**
 * Versely's own links (versely://), as GenesisLink on iOS: the same
 * addresses on both phones, so a widget or notification opens the same place.
 * Only the reader's links for now; the others arrive with their screens.
 */
sealed interface GenesisLink {
    /** versely://read/<verse id>: the reader at that verse. */
    data class Read(val verse: VerseId) : GenesisLink

    /** versely://read: carry on where the person left off. */
    data object ContinueReading : GenesisLink

    /** versely://home */
    data object Home : GenesisLink

    companion object {
        const val SCHEME = "versely"

        fun read(verse: VerseId): String = "$SCHEME://read/${verse.rawValue}"

        /** Reads a link; anything else (another scheme, a verse that doesn't exist) is null. */
        fun parse(link: String): GenesisLink? {
            val rest = link.trim().removePrefix("$SCHEME://").takeIf { it != link.trim() } ?: return null
            val parts = rest.substringBefore('?').substringBefore('#').trim('/').split('/')
            return when (parts.first().lowercase()) {
                "read" -> when (parts.size) {
                    1 -> ContinueReading
                    else -> parts[1].toIntOrNull()?.let(::VerseId)?.takeIf(::exists)?.let(::Read)
                }
                "home" -> Home
                else -> null
            }
        }

        private fun exists(verse: VerseId): Boolean {
            val book = BibleBooks.all.getOrNull(verse.book - 1) ?: return false
            return verse.chapter in 1..book.chapterCount && verse.verse in 1..book.verseCount(verse.chapter)
        }
    }
}
