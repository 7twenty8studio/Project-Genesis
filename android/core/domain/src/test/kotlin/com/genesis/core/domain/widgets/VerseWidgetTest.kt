package com.genesis.core.domain.widgets

import com.genesis.core.domain.bible.VerseId
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class VerseWidgetTest {
    private val zone = ZoneId.of("America/New_York")

    @Test fun mixMatchesTheIPhone() {
        // splitmix64, as WidgetVerses.mix on iOS (values worked out independently).
        assertEquals(7070836379803831728, WidgetVerses.mix(0))
        assertEquals(6904514525105968747, WidgetVerses.mix(43003016))
        assertEquals(1635312068028924514, WidgetVerses.mix(-5))
    }

    @Test fun sourcesAndPremium() {
        assertEquals(VerseWidgetSource.VERSE_OF_THE_DAY, VerseWidgetSource.of(null))
        assertEquals(VerseWidgetSource.HOPE, VerseWidgetSource.of("hope"))
        assertFalse(VerseWidgetSource.RANDOM.needsPremium)
        assertTrue(VerseWidgetSource.FROM_YOUR_READING.needsPremium)
        assertTrue(VerseWidgetSource.PEACE.rotates)
        assertFalse(VerseWidgetSource.FROM_YOUR_READING.rotates)
        assertEquals(VerseCategory.LOVE, VerseWidgetSource.LOVE.category)
    }

    @Test fun categoriesHoldShortPassagesInOneChapter() {
        for (category in VerseCategory.entries) {
            val passages = VerseCategories.passages(category)
            assertTrue(passages.size in 15..30, "$category has ${passages.size}")
            passages.forEach { assertTrue(it.verseIds.size in 1..3) }
        }
        assertEquals(VerseCategories.encouraging.size, VerseCategories.encouraging.toSet().size)
        assertEquals(listOf(VerseId(43, 3, 16)), VerseCategories.passages(VerseCategory.LOVE).first().verseIds)
    }

    @Test fun scheduleRotatesEveryThreeHours() {
        val morning = LocalDateTime.of(2026, 11, 27, 7, 0)
        assertEquals(VerseWidgetSchedule.slot(morning, zone), VerseWidgetSchedule.slot(morning.plusHours(1), zone))
        assertEquals(VerseWidgetSchedule.slot(morning, zone) + 1, VerseWidgetSchedule.slot(morning.plusHours(2), zone))
        assertEquals(LocalDateTime.of(2026, 11, 27, 9, 0), VerseWidgetSchedule.nextChange(morning, rotates = true))
        assertEquals(LocalDateTime.of(2026, 11, 28, 0, 0), VerseWidgetSchedule.nextChange(morning, rotates = false))
        assertEquals(LocalDateTime.of(2026, 11, 28, 0, 0), VerseWidgetSchedule.nextChange(LocalDateTime.of(2026, 11, 27, 22, 30), rotates = true))
        assertNull(VerseWidgetSchedule.index(morning, 0, zone))
        // New York's day 0 is 31 December 2000, as on iOS (the local day of 2001-01-01 00:00 UTC).
        assertEquals(0, VerseWidgetSchedule.dayNumber(LocalDate.of(2000, 12, 31), zone))
        assertEquals(0, VerseWidgetSchedule.dayNumber(LocalDate.of(2001, 1, 1), ZoneId.of("Europe/London")))
    }

    @Test fun randomPoolIsTheSameAllDayAndNewTomorrow() {
        val today = WidgetVerses.randomPool(9000)
        assertEquals(WidgetVerses.RANDOM_POOL_SIZE, today.size)
        assertEquals(today, WidgetVerses.randomPool(9000))
        assertNotEquals(today, WidgetVerses.randomPool(9001))
    }

    @Test fun ownBibleOnlyWhereItNumbersLikeTheKjv() {
        val romans = CategoryPassage(VerseId(45, 16, 25), VerseId(45, 16, 25))
        assertFalse(WidgetVerses.usesOwnBible(romans, "WEB"))
        assertTrue(WidgetVerses.usesOwnBible(romans, "KJV"))
        assertTrue(WidgetVerses.usesOwnBible(romans, "BLIVRE"))
    }

    @Test fun comfortableVerses() {
        assertTrue(ReadingVersePicker.isComfortable("For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish."))
        assertTrue(ReadingVersePicker.isComfortable("¿No es esta la palabra que te hablamos en Egipto, para que nos dejes servir?"))
        assertTrue(ReadingVersePicker.isComfortable("“Don’t let your heart be troubled. Believe in God. Believe also in me.”"))
        assertFalse(ReadingVersePicker.isComfortable("Jesus wept."))
        assertFalse(ReadingVersePicker.isComfortable("and he said unto them, Go ye into all the world, and preach the gospel to every creature."))
        assertFalse(ReadingVersePicker.isComfortable("Being confident of this very thing, that he which hath begun a good work in you will perform it,"))
        val verses = mapOf(1 to listOf("Jesus wept.", "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish."))
        assertEquals(verses[1]!![1], ReadingVersePicker.pick(listOf(1), 5, { verses[it].orEmpty() }, { it }))
        assertNull(ReadingVersePicker.pick(emptyList<Int>(), 5, { emptyList<String>() }, { it }))
    }
}
