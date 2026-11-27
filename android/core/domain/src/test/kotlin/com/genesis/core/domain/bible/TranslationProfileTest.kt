package com.genesis.core.domain.bible

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class TranslationProfileTest {
    private val english = listOf("KJV", "BSB", "WEB", "ASV").map { it to TranslationProfile.builtIn.getValue(it) }

    @Test fun suggestions() {
        assertEquals("WEB", TranslationProfile.suggestion(ReadingPurpose.STUDY, english))
        assertEquals("BSB", TranslationProfile.suggestion(ReadingPurpose.EVERYDAY, english))
        assertEquals("KJV", TranslationProfile.suggestion(ReadingPurpose.CLASSIC, english))
        assertNull(TranslationProfile.suggestion(ReadingPurpose.EVERYDAY, listOf("X" to TranslationProfile())))
    }

    @Test fun catalogWins() {
        val item = DownloadableBible(id = "KJV", name = "KJV", approach = "balanced")
        assertEquals(TranslationApproach.BALANCED, TranslationProfile.of(item, "KJV").approach)
        assertEquals(ReadingLevel.TRADITIONAL, TranslationProfile.of(item, "KJV").readingLevel)
    }
}
