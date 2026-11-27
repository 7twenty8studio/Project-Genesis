package com.genesis.core.domain.audio

import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.VerseId

/** A verse to read aloud, verbatim from the Bible database. */
data class NarrationVerse(val id: VerseId, val text: String, val startsParagraph: Boolean)

/** One thing the voice says: the chapter's title or a verse, then a short pause. */
data class NarrationItem(val text: String, val verse: VerseId?, val pauseAfterMillis: Long)

/**
 * How a chapter is read aloud by the device's voice, as SpeechNarrator on
 * iOS: the title in the Bible's language when reading from the start, then
 * each verse word for word (nothing rewritten), a longer pause at paragraphs.
 */
object Narration {
    val speeds: List<Double> = listOf(0.75, 1.0, 1.25, 1.5, 2.0)

    fun clampSpeed(speed: Double): Double = if (speed > 0) speed.coerceIn(0.5, 2.0) else 1.0

    /** "John, chapter 3." or "Juan, capítulo 3." (Spanish and Portuguese). */
    fun title(bookName: String, chapter: Int, language: String): String {
        val capitulo = language.startsWith("es") || language.startsWith("pt")
        return if (capitulo) "$bookName, capítulo $chapter." else "$bookName, chapter $chapter."
    }

    /** What to say, from [from] (or the start, with the title). */
    fun script(verses: List<NarrationVerse>, from: VerseId?, title: String, speed: Double): List<NarrationItem> {
        val start = from?.let { wanted -> verses.firstOrNull { it.id >= wanted } }?.id ?: verses.firstOrNull()?.id ?: return emptyList()
        val scale = 1.0 / maxOf(speed, 0.5)
        val items = mutableListOf<NarrationItem>()
        if (start == verses.first().id) items += NarrationItem(title, null, (600 * scale).toLong())
        verses.filter { it.id >= start }.forEach { verse ->
            items += NarrationItem(verse.text.replace('\n', ' '), verse.id, ((if (verse.startsParagraph) 350 else 150) * scale).toLong())
        }
        return items
    }

    /** Like a music player: back to the start, or the chapter before when barely begun (verse 1–2). */
    fun previous(chapter: ChapterId, verse: VerseId?): ChapterId {
        val barelyStarted = verse == null || verse.verse <= 2
        return if (barelyStarted) chapter.previous ?: chapter else chapter
    }

    /** The verse before or after [current] within the chapter's verses. */
    fun skip(verses: List<VerseId>, current: VerseId, forward: Boolean): VerseId? {
        val index = verses.indexOf(current).takeIf { it >= 0 } ?: return null
        return verses[(index + if (forward) 1 else -1).coerceIn(0, verses.lastIndex)]
    }

    /** "1×", "1.25×", "0.75×". */
    fun speedLabel(speed: Double): String =
        (if (speed % 1.0 == 0.0) speed.toInt().toString() else speed.toString().trimEnd('0')) + "×"
}
