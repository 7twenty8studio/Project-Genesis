package com.genesis.core.domain.reader

import com.genesis.core.domain.theme.ReaderTheme
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NightReadingTest {
    @Test fun windowCrossesMidnight() {
        assertTrue(NightReading.isNight(22, 20, 6))
        assertTrue(NightReading.isNight(3, 20, 6))
        assertFalse(NightReading.isNight(6, 20, 6))
        assertFalse(NightReading.isNight(12, 20, 20))
        assertTrue(NightReading.isNight(13, 12, 14))
    }

    @Test fun themes() {
        val late = LocalDateTime.of(2026, 11, 27, 23, 0)
        val noon = late.withHour(12)
        val hours = NightReadingSchedule(NightTheme.STARLIGHT, NightReadingTiming.HOURS)
        assertEquals(ReaderTheme.STARLIGHT, NightReading.theme(hours, ReaderTheme.CREAM, late, false, premium = true))
        assertEquals(ReaderTheme.NIGHT, NightReading.theme(hours, ReaderTheme.CREAM, late, false, premium = false))
        assertEquals(ReaderTheme.CREAM, NightReading.theme(hours, ReaderTheme.CREAM, noon, true, premium = true))
        val dark = NightReadingSchedule(NightTheme.NIGHT)
        assertEquals(ReaderTheme.NIGHT, NightReading.theme(dark, ReaderTheme.CREAM, noon, systemIsDark = true, premium = false))
        assertEquals(ReaderTheme.CREAM, NightReading.theme(NightReadingSchedule(), ReaderTheme.CREAM, late, true, true))
    }

    @Test fun nextChange() {
        val now = ZonedDateTime.of(2026, 11, 27, 21, 30, 0, 0, ZoneId.of("America/Chicago"))
        val schedule = NightReadingSchedule(NightTheme.NIGHT, NightReadingTiming.HOURS)
        assertEquals(now.plusDays(1).withHour(6).withMinute(0), NightReading.nextChange(now, schedule))
        assertNull(NightReading.nextChange(now, NightReadingSchedule(NightTheme.NIGHT)))
    }

    @Test fun preferencesRoundTrip() {
        val prefs = ReaderPreferences(margins = ReaderMargins.WIDE, pageTurn = PageTurnStyle.SLIDE, layout = TextLayout.VERSE_PER_LINE, leftHanded = true,
            nightReading = NightReadingSchedule(NightTheme.STARLIGHT, NightReadingTiming.HOURS, 21, 5), paragraphSpacing = 1.0)
        assertEquals(prefs, ReaderPreferences.decoded(prefs.encoded()))
        assertEquals(ReaderPreferences(), ReaderPreferences.decoded("{\"margins\":\"huge\"}"))
    }
}
