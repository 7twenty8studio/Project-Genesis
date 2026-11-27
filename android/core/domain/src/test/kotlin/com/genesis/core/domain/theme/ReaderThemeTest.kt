package com.genesis.core.domain.theme

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ReaderThemeTest {
    @Test fun aReadableFreeChoiceAlwaysExists() {
        val free = ReaderTheme.entries.filterNot { it.isPremium }
        assertTrue(free.any { !it.isDark })
        assertTrue(ReaderTheme.NIGHT in free)
        assertTrue(ReaderTheme.HIGH_CONTRAST in free)
        assertTrue(ReaderTheme.STARLIGHT.isPremium)
    }

    @Test fun autoFollowsTheSystem() {
        assertEquals(ReaderTheme.SLATE, ReaderTheme.AUTOMATIC.resolved(systemIsDark = true))
        assertEquals(ReaderTheme.PAPER, ReaderTheme.AUTOMATIC.resolved(systemIsDark = false))
    }

    @Test fun seasonsFlipInTheSouth() {
        val november = LocalDate.of(2026, 11, 26)
        assertEquals(Season.AUTUMN, Season.current(november, "US"))
        assertEquals(Season.SPRING, Season.current(november, "BR"))
        assertFalse(ReaderTheme.SEASONS.resolved(false, november, "US") == ReaderTheme.SEASONS)
    }

    /** WCAG contrast of body text on the page: at least 7:1 on every theme. */
    @Test fun bodyTextIsReadableOnEveryTheme() {
        fun luminance(rgb: Int): Double {
            fun channel(c: Int): Double = (c / 255.0).let { if (it <= 0.03928) it / 12.92 else Math.pow((it + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(rgb shr 16 and 0xFF) + 0.7152 * channel(rgb shr 8 and 0xFF) + 0.0722 * channel(rgb and 0xFF)
        }
        for (theme in ReaderTheme.entries) {
            val p = theme.palette
            val (a, b) = luminance(p.text) to luminance(p.background)
            val ratio = (maxOf(a, b) + 0.05) / (minOf(a, b) + 0.05)
            assertTrue(ratio >= 7.0, "$theme text contrast $ratio")
        }
    }
}
