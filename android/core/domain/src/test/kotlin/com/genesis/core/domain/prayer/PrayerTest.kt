package com.genesis.core.domain.prayer

import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.VerseId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The same rules as iOS's prayer journal tests. */
class PrayerTest {
    @Test
    fun categoriesAreReadLeniently() {
        assertEquals(PrayerCategory.FAMILY, PrayerCategory.lenient(" Family "))
        assertEquals(PrayerCategory.WORK, PrayerCategory.lenient("school"))
        assertEquals(PrayerCategory.FRIENDS, PrayerCategory.lenient("friends"))
        assertEquals(PrayerCategory.PERSONAL, PrayerCategory.lenient("something else"))
    }

    @Test
    fun passagesParseWithinOneChapter() {
        val john = PrayerPassage.parse("John 3:16")!!
        assertEquals(VerseId(43, 3, 16), john.start)
        assertEquals(john.start, john.end)
        val range = PrayerPassage.parse("Philippians 4:6-7")!!
        assertEquals(VerseId(50, 4, 7), range.end)
        assertNull(PrayerPassage.parse("Psalm 23"))
        assertEquals(VerseId(19, 23, 6), PrayerPassage.parse("Psalm 23") { if (it == ChapterId(19, 23)) 6 else null }!!.end)
        assertNull(PrayerPassage.parse("not a verse"))
        assertEquals("John 3:16", john.reference("en"))
    }

    @Test
    fun aSelectionStaysInItsFirstChapter() {
        val passage = PrayerPassage.selection(listOf(VerseId(43, 3, 17), VerseId(43, 3, 16)))!!
        assertEquals(VerseId(43, 3, 16), passage.start)
        assertEquals(VerseId(43, 3, 17), passage.end)
        val across = PrayerPassage.selection(listOf(VerseId(43, 3, 36), VerseId(43, 4, 1)))!!
        assertEquals(across.start, across.end)
    }

    @Test
    fun storageIsLenient() {
        val passages = PrayerPassage.decode("43003016-43003017, junk,43003016-43003017,19023001")
        assertEquals(listOf("43003016-43003017", "19023001-19023001"), passages.map { it.id })
        assertEquals("43003016-43003017,19023001-19023001", PrayerPassage.encode(passages))
    }

    @Test
    fun answeringClearsTheReminder() {
        val prayer = Prayer("a", title = "Mum", reminderAt = 5, reminderRepeatsDaily = true)
        val answered = prayer.answered(true, "She's well", now = 10)
        assertTrue(answered.isAnswered)
        assertEquals(10L, answered.answeredAt)
        assertNull(answered.reminderAt)
        assertFalse(answered.reminderRepeatsDaily)
        assertEquals("She's well", answered.answerNote)
        val back = answered.answered(false, null, now = 20)
        assertNull(back.answeredAt)
        assertEquals("She's well", back.answerNote)
    }

    @Test
    fun passagesAttachOnceUpToTheLimit() {
        val passage = PrayerPassage.parse("John 3:16")!!
        val prayer = Prayer("a").attaching(passage).attaching(passage)
        assertEquals(1, prayer.passages.size)
        val full = (1..30).fold(Prayer("b")) { p, verse -> p.attaching(PrayerPassage.of(VerseId(19, 119, verse), VerseId(19, 119, verse))) }
        assertEquals(PrayerPassage.MAXIMUM_PER_PRAYER, full.passages.size)
        assertTrue(prayer.detaching(passage).passages.isEmpty())
    }

    @Test
    fun displayTitleAndSearch() {
        assertEquals("First line", Prayer("a", body = "First line\nSecond").displayTitle)
        assertNull(Prayer("a").displayTitle)
        val prayer = Prayer("a", title = "Oración por mamá", answerNote = "Healed")
        assertTrue(PrayerSearch.matches(prayer, "oracion"))
        assertTrue(PrayerSearch.matches(prayer, "HEALED"))
        assertFalse(PrayerSearch.matches(prayer, "work"))
        assertTrue(PrayerSearch.matches(prayer, "  "))
    }
}
