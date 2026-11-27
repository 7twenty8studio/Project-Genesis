package com.genesis.core.domain.bible

import kotlin.test.Test
import kotlin.test.assertEquals

class VersificationTest {
    @Test
    fun webDoxologyLandsInChapterFourteen() {
        val map = OriginalVersification.parallelMap("WEB")
        assertEquals(VerseId(45, 14, 24) to VerseId(45, 14, 26), map.ownRange(VerseId(45, 16, 25), VerseId(45, 16, 27)))
        assertEquals(emptyList(), map.alignment(VerseId(45, 16, 25)).kjv)
        assertEquals(listOf(VerseId(45, 16, 26)), map.alignment(VerseId(45, 14, 25)).kjv)
    }

    @Test
    fun kjvAndUnknownBiblesKeepTheirNumbers() {
        val verse = VerseId(43, 3, 16)
        assertEquals(verse to verse, OriginalVersification.parallelMap("KJV").ownRange(verse, verse))
        assertEquals(verse to verse, OriginalVersification.parallelMap("BLIVRE").ownRange(verse, verse))
    }

    @Test
    fun nivSplitsThirdJohnFourteen() {
        val map = OriginalVersification.parallelMap("NIV")
        assertEquals(VerseId(64, 1, 14) to VerseId(64, 1, 15), map.ownRange(VerseId(64, 1, 14), VerseId(64, 1, 14)))
    }
}
