package com.genesis.core.domain.audio

import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.VerseId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class NarrationTest {
    private val john3 = ChapterId(43, 3)
    private val verses = (1..4).map { NarrationVerse(VerseId(43, 3, it), "Verse $it\nline", startsParagraph = it == 3) }

    @Test
    fun fromTheStartTheTitleComesFirst() {
        val script = Narration.script(verses, null, Narration.title("John", 3, "en"), 1.0)
        assertEquals("John, chapter 3.", script.first().text)
        assertNull(script.first().verse)
        assertEquals(5, script.size)
        assertEquals("Verse 1 line", script[1].text)
        assertEquals(350, script[3].pauseAfterMillis)
        assertEquals(150, script[4].pauseAfterMillis)
    }

    @Test
    fun fromAVerseThereIsNoTitle() {
        val script = Narration.script(verses, VerseId(43, 3, 3), "t", 2.0)
        assertEquals(listOf(3, 4), script.map { it.verse?.verse })
        assertEquals(175, script.first().pauseAfterMillis)
        // A verse past the end reads from the start.
        assertEquals("t", Narration.script(verses, VerseId(43, 3, 40), "t", 1.0).first().text)
        assertEquals(emptyList(), Narration.script(emptyList(), null, "t", 1.0))
    }

    @Test
    fun titlesInTheBiblesLanguage() {
        assertEquals("Juan, capítulo 3.", Narration.title("Juan", 3, "es"))
        assertEquals("João, capítulo 3.", Narration.title("João", 3, "pt-PT"))
    }

    @Test
    fun previousRestartsOrGoesBack() {
        assertEquals(ChapterId(43, 2), Narration.previous(john3, VerseId(43, 3, 2)))
        assertEquals(ChapterId(43, 2), Narration.previous(john3, null))
        assertEquals(john3, Narration.previous(john3, VerseId(43, 3, 10)))
        assertEquals(ChapterId(1, 1), Narration.previous(ChapterId(1, 1), null))
    }

    @Test
    fun skipStaysInTheChapter() {
        val ids = verses.map { it.id }
        assertEquals(ids[1], Narration.skip(ids, ids[0], forward = true))
        assertEquals(ids[0], Narration.skip(ids, ids[0], forward = false))
        assertEquals(ids[3], Narration.skip(ids, ids[3], forward = true))
        assertNull(Narration.skip(ids, VerseId(1, 1, 1), forward = true))
    }

    @Test
    fun speeds() {
        assertEquals("1×", Narration.speedLabel(1.0))
        assertEquals("1.25×", Narration.speedLabel(1.25))
        assertEquals("0.75×", Narration.speedLabel(0.75))
        assertEquals(2.0, Narration.clampSpeed(3.0))
        assertEquals(1.0, Narration.clampSpeed(0.0))
    }
}
