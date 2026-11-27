package com.genesis.core.domain.home

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TextFitTest {
    @Test
    fun aShortVerseKeepsTheLargestSize() {
        assertEquals(16, TextFit.fit(60, 300.0, 140.0, largest = 16, smallest = 11).fontSizeSp)
    }

    @Test
    fun aLongVerseShrinksToFit() {
        // Zephaniah 3:17 (KJV, 165 characters) in a small widget.
        val fit = TextFit.fit(165, 157.0, 140.0, largest = 15, smallest = 11)
        assertTrue(fit.fontSizeSp < 15)
        assertTrue(fit.maxLines >= 7)
    }

    @Test
    fun theSmallestSizeIsTheFloor() {
        val fit = TextFit.fit(2_000, 100.0, 50.0, largest = 15, smallest = 11)
        assertEquals(11, fit.fontSizeSp)
        assertEquals(3, fit.maxLines)
    }
}
