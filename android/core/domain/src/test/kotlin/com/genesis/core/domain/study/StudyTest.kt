package com.genesis.core.domain.study

import com.genesis.core.domain.bible.VerseId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StudyModelsTest {
    @Test
    fun otherNamesLeaveOutRepeatsAndTheNameItself() {
        assertEquals("", OtherNames.distinct("Lucas", "Lucas"))
        assertEquals("Saul", OtherNames.distinct("Saul, Paul, saul", "Paul"))
        assertEquals("Cephas", OtherNames.distinct("Simon, Simón, Cephas", "Simon (son of Jonah)"))
        assertEquals("", OtherNames.distinct("", "Moses"))
        assertEquals("Moisés", OtherNames.distinct("Moisés", "Moses"))
    }

    @Test
    fun yearsAsTheyAreWritten() {
        assertEquals(ApproximateYear("1491", true), ApproximateYear.of(-1490))
        assertEquals(ApproximateYear("1", true), ApproximateYear.of(0))
        assertEquals(ApproximateYear("30", false), ApproximateYear.of(30))
    }

    @Test
    fun eraRanges() {
        val era = Era("kings", "Kings", "", true, VerseId(9, 1, 1))
        val events = listOf(TimelineEvent(1, "a", "kings", -1000, null, null), TimelineEvent(2, "b", "kings", null, null, null), TimelineEvent(3, "c", "kings", -930, null, null))
        assertEquals(-1000 to -930, yearRange(era, events))
        assertNull(yearRange(era.copy(isDated = false), events))
        assertNull(yearRange(era, emptyList()))
    }

    @Test
    fun certaintyBands() {
        assertEquals(PlaceCertainty.KNOWN, PlaceCertainty.of(1000))
        assertEquals(PlaceCertainty.KNOWN, PlaceCertainty.of(750))
        assertEquals(PlaceCertainty.LIKELY, PlaceCertainty.of(500))
        assertEquals(PlaceCertainty.UNCERTAIN, PlaceCertainty.of(499))
        assertEquals(PlaceCertainty.UNCERTAIN, PlaceCertainty.of(null))
    }

    @Test
    fun familyPutsFathersFirst() {
        val mother = PersonSummary(1, "Sarah", "", 50)
        val father = PersonSummary(2, "Abraham", "", 200)
        val son = PersonSummary(3, "Jacob", "", 300)
        val family = Family.of(listOf("child" to son, "mother" to mother, "father" to father))
        assertEquals(listOf(father, mother), family.parents)
        assertEquals(listOf(son), family.children)
        assertTrue(Family().isEmpty)
    }

    @Test
    fun likeEscapesWildcards() {
        assertEquals("Ab%", likePrefix("Ab"))
        assertEquals("50\\%\\_a\\\\%", likePrefix("50%_a\\"))
    }
}
