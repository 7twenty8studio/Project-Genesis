package com.genesis.core.domain.link

import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.VerseId

/**
 * Versely's own links (versely://), as GenesisLink on iOS: the same
 * addresses on both phones, so a widget or notification opens the same place.
 * The rest arrive with their screens.
 */
sealed interface GenesisLink {
    /** versely://read/<verse id>: the reader at that verse. */
    data class Read(val verse: VerseId) : GenesisLink

    /** versely://read: carry on where the person left off. */
    data object ContinueReading : GenesisLink

    /** versely://home */
    data object Home : GenesisLink

    /** versely://plans: Reading Plans. */
    data object Plans : GenesisLink

    /** versely://prayer: the Prayer Journal. */
    data object Prayer : GenesisLink

    /** versely://memorise: Memorize Scripture (the Memorize widget). */
    data object Memorise : GenesisLink

    /** versely://sermons: Sermon Notes. */
    data object Sermons : GenesisLink

    /** versely://insights: Insights (the weekly recap). */
    data object Insights : GenesisLink

    /** versely://group/<id>: one of the person's groups (the Group Progress widget). */
    data class Group(val id: String) : GenesisLink

    /**
     * A church's sermon: versely://sermon/<slug>, or its one link
     * https://versely.7twenty8studio.com/s/<slug> (an App Link).
     */
    data class Sermon(val slug: String) : GenesisLink

    companion object {
        const val SCHEME = "versely"

        const val CONTINUE_READING = "$SCHEME://read"
        const val HOME = "$SCHEME://home"
        const val PLANS = "$SCHEME://plans"
        const val PRAYER = "$SCHEME://prayer"
        const val MEMORISE = "$SCHEME://memorise"
        const val SERMONS = "$SCHEME://sermons"
        const val INSIGHTS = "$SCHEME://insights"

        fun read(verse: VerseId): String = "$SCHEME://read/${verse.rawValue}"

        fun group(id: String): String = "$SCHEME://group/$id"

        /** Reads a link; anything else (another scheme, a verse that doesn't exist) is null. */
        fun parse(link: String): GenesisLink? {
            sermonSlug(link)?.let { return Sermon(it) }
            val rest = link.trim().removePrefix("$SCHEME://").takeIf { it != link.trim() } ?: return null
            val parts = rest.substringBefore('?').substringBefore('#').trim('/').split('/')
            return when (parts.first().lowercase()) {
                "read" -> when (parts.size) {
                    1 -> ContinueReading
                    else -> parts[1].toIntOrNull()?.let(::VerseId)?.takeIf(::exists)?.let(::Read)
                }
                "home" -> Home
                "plans" -> Plans
                "prayer" -> Prayer
                "memorise" -> Memorise
                "sermons" -> Sermons
                "insights" -> Insights
                "group" -> parts.getOrNull(1)?.takeIf { it.isNotBlank() }?.let { Group(it.lowercase()) }
                else -> null
            }
        }

        const val SERMON_HOST = "versely.7twenty8studio.com"

        /** Ten lowercase letters and digits, as the database makes them. */
        fun isSlug(text: String): Boolean = text.length == 10 && text.all { it in 'a'..'z' || it in '0'..'9' }

        private fun sermonSlug(link: String): String? {
            val trimmed = link.trim()
            val scheme = trimmed.substringBefore("://", "").lowercase()
            val rest = trimmed.substringAfter("://", "").substringBefore('?').substringBefore('#')
            val host = rest.substringBefore('/').lowercase()
            val parts = rest.substringAfter('/', "").split('/').filter { it.isNotEmpty() }
            val slug = when (scheme) {
                "https" -> if (host == SERMON_HOST && parts.size == 2 && parts[0] == "s") parts[1] else null
                SCHEME -> if (host == "sermon" && parts.size == 1) parts[0] else null
                else -> null
            }
            return slug?.takeIf(::isSlug)
        }

        private fun exists(verse: VerseId): Boolean {
            val book = BibleBooks.all.getOrNull(verse.book - 1) ?: return false
            return verse.chapter in 1..book.chapterCount && verse.verse in 1..book.verseCount(verse.chapter)
        }
    }
}
