package com.genesis.core.domain.study

import com.genesis.core.domain.bible.VerseId
import kotlin.test.Test
import kotlin.test.assertEquals

class StudyTest {
    private fun john1(verse: Int) = VerseId(43_001_000 + verse)

    @Test fun oneVerseHasNoNumber() {
        assertEquals(
            "“In the beginning was the Word.”\n— John 1:1 (KJV)",
            ShareText.of(listOf(john1(1) to "In the beginning was the Word."), "KJV", "en"),
        )
    }

    @Test fun severalVersesKeepTheirNumbersInOrder() {
        assertEquals(
            "“4 In him was life. 5 And the light shineth.”\n— Juan 1:4–5 (RV1909)",
            ShareText.of(listOf(john1(5) to "And the light shineth.", john1(4) to "In him was life."), "RV1909", "es"),
        )
    }

    @Test fun recentColorsComeFirstThenTheStandardOrder() {
        assertEquals(listOf(HighlightColor.YELLOW, HighlightColor.BLUE, HighlightColor.GREEN), RecentHighlightColors.shown(emptyList()))
        val recent = RecentHighlightColors.after(HighlightColor.PINK, listOf(HighlightColor.BLUE, HighlightColor.PINK, HighlightColor.GREEN))
        assertEquals(listOf(HighlightColor.PINK, HighlightColor.BLUE, HighlightColor.GREEN), recent)
        assertEquals(listOf(HighlightColor.ORANGE, HighlightColor.YELLOW, HighlightColor.BLUE), RecentHighlightColors.shown(listOf(HighlightColor.ORANGE)))
    }

    @Test fun unknownColorReadsAsYellow() {
        assertEquals(HighlightColor.YELLOW, HighlightColor.withId("teal"))
        assertEquals(HighlightColor.GREEN, HighlightColor.withId("green"))
    }
}
