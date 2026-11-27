package com.genesis.core.domain.home

import com.genesis.core.domain.bible.VerseId
import java.time.LocalDate
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals

class HomeTest {
    private val utc = ZoneId.of("UTC")
    private val chicago = ZoneId.of("America/Chicago")

    @Test fun theListStartsOnIOSReferenceDay() {
        assertEquals(VerseId(43, 3, 16), DailyVerse.verse(LocalDate.of(2001, 1, 1), utc))
        assertEquals(VerseId(19, 23, 1), DailyVerse.verse(LocalDate.of(2001, 1, 2), utc))
        assertEquals(VerseId(43, 3, 16), DailyVerse.verse(LocalDate.of(2001, 3, 2), utc))
    }

    @Test fun westOfGreenwichTheReferenceDayIsTheDayBefore() {
        // iOS starts counting at the local day of 1 January 2001 00:00 UTC:
        // 31 December 2000 in Chicago.
        assertEquals(VerseId(43, 3, 16), DailyVerse.verse(LocalDate.of(2000, 12, 31), chicago))
        assertEquals(VerseId(66, 21, 4), DailyVerse.verse(LocalDate.of(2000, 12, 30), chicago))
    }

    @Test fun greetingsFollowTheHour() {
        assertEquals(Greeting.EVENING, Greeting.at(3))
        assertEquals(Greeting.MORNING, Greeting.at(4))
        assertEquals(Greeting.AFTERNOON, Greeting.at(12))
        assertEquals(Greeting.EVENING, Greeting.at(17))
    }

    @Test fun progressCountsFinishedChapters() {
        assertEquals(0.0, progressThroughBook(VerseId(43, 1, 1)))
        assertEquals(10.0 / 21, progressThroughBook(VerseId(43, 11, 1)), 0.0001)
    }
}
