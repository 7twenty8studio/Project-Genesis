package com.genesis.core.domain.journal

import kotlin.test.Test
import kotlin.test.assertEquals

class JournalTemplatesTest {
    private val parts = listOf(JournalTemplate.Part("Adoration", "Praise God."), JournalTemplate.Part("Confession", "Be honest."))

    @Test fun prayerTextIsPlain() {
        assertEquals("Adoration\nPraise God.\n\nConfession\nBe honest.\n", JournalTemplate.ACTS.text(parts))
    }

    @Test fun sermonTextIsMarkdown() {
        assertEquals("## Adoration\n*Praise God.*\n\n## Confession\n*Be honest.*\n", JournalTemplate.OUTLINE.text(parts))
    }

    @Test fun emptyBodyIsReplaced() {
        assertEquals(JournalTemplate.Inserted("T\n", 2), JournalTemplate.inserting("T\n", "  \n"))
    }

    @Test fun insertsAsNewParagraph() {
        assertEquals(JournalTemplate.Inserted("Hello\n\nT\n", 9), JournalTemplate.inserting("T\n", "Hello"))
        assertEquals("Hello\n\nT\n", JournalTemplate.inserting("T\n", "Hello\n").text)
        assertEquals("Hello\n\nT\n", JournalTemplate.inserting("T\n", "Hello\n\n").text)
    }

    @Test fun insertsAtCursorWithBreakAfter() {
        val result = JournalTemplate.inserting("T", "Hello world", 5)
        assertEquals("Hello\n\nT\n world", result.text)
        assertEquals(8, result.cursor)
    }

    @Test fun templatesByOwner() {
        assertEquals(5, JournalTemplate.templates(sermon = false).size)
        assertEquals(4, JournalTemplate.templates(sermon = true).size)
    }
}
