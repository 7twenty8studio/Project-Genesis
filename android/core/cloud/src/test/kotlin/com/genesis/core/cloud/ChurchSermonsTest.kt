package com.genesis.core.cloud

import com.genesis.core.cloud.community.ChurchGathering
import com.genesis.core.cloud.community.ChurchLocation
import com.genesis.core.cloud.community.ChurchSermonLink
import com.genesis.core.cloud.community.ChurchSermonLookup
import com.genesis.core.cloud.community.ChurchSermonWire
import com.genesis.core.cloud.community.SavedHandouts
import com.genesis.core.cloud.community.SermonAnswers
import com.genesis.core.cloud.community.SermonBlanks
import com.genesis.core.cloud.community.SermonBlock
import com.genesis.core.cloud.community.SermonOutline
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ChurchSermonsTest {
    private val sample = """
        {"status":"ok","sermon":{"id":"0E6F0C7E-1111-4222-8333-444455556666","slug":"abcde12345","group_id":"7A1B2C3D-0000-4000-8000-000000000001",
        "church":"Grace Church","title":"Hope","speaker":"Pastor Ana","series":" ","preached_on":"2026-11-22T00:00:00","location":"","language":"en",
        "audience":"link","is_member":false,"revision":2,"answers":"revealed",
        "blocks":[{"id":"h1","kind":"heading","text":"Our [[1]] hope","level":7},
                  {"id":"p1","kind":"paragraph","text":"God is [[2]]."},
                  {"id":"s1","kind":"scripture","ref":{"raw":"Jn 3:16","start":43003016,"end":43003017,"status":"verified","label":"NIV","translation":"NIV"}},
                  {"id":"s2","kind":"scripture","ref":{"raw":"Bad","start":0,"status":"verified"}},
                  {"id":"x","kind":"video","text":"later"}],
        "blanks":[{"n":1,"open":false,"answer":"living"},{"n":2,"open":true,"answer":"secret"}],
        "locations":[{"name":"Main","street":"1 Elm","city":"Dallas","region":"TX","postal_code":"75146",
          "gatherings":[{"day":"sun","time":"11:00"},{"day":"sun","time":"09:00","note":"Spanish"},{"date":"2020-01-01","time":"10:00"},{"day":"sun","time":"9am"}]}]}}
    """.trimIndent()

    @Test
    fun readsAPublishedSermonLeniently() {
        val sermon = assertIs<ChurchSermonLookup.Found>(ChurchSermonWire.lookup(sample)).sermon
        assertEquals("0e6f0c7e-1111-4222-8333-444455556666", sermon.id)
        assertEquals("2026-11-22", sermon.preachedOn)
        assertNull(sermon.series)
        assertEquals(4, sermon.blocks.size)
        assertEquals(3, (sermon.blocks[0] as SermonBlock.Heading).level)
        val verified = (sermon.blocks[2] as SermonBlock.Scripture).reference
        assertEquals(43003016 to 43003017, verified.range)
        assertNull(verified.translation)
        assertNull((sermon.blocks[3] as SermonBlock.Scripture).reference.range)
        assertEquals(listOf(43003016 to 43003017), sermon.passages)
        assertNull(sermon.blanks[1].answer)
        assertEquals(SermonAnswers.REVEALED, sermon.answers)
        // As the server sends it: the fields beside "status".
        val flat = """{"status":"ok","id":"68de0630-e3b0-42a2-b059-94b484debcd3","slug":"6audf2zagi","group_id":"beba5c2f-8236-4897-90dc-052e6914069f","title":"Rest","blocks":[{"id":"p1","kind":"paragraph","text":"Come."}]}"""
        assertEquals("Rest", assertIs<ChurchSermonLookup.Found>(ChurchSermonWire.lookup(flat)).sermon.title)
        assertEquals(ChurchSermonLookup.MembersOnly, ChurchSermonWire.lookup("""{"status":"members_only"}"""))
        assertEquals(ChurchSermonLookup.NotFound, ChurchSermonWire.lookup("""{"status":"gone"}"""))
    }

    @Test
    fun schedulesListWeekdaysThenFutureDates() {
        val place = assertIs<ChurchSermonLookup.Found>(ChurchSermonWire.lookup(sample)).sermon.locations.single()
        val lines = place.scheduleLines("2026-11-27", Locale.US) { if (it == ChurchGathering.Weekday.SUN) "Sundays" else it.raw }
        assertEquals(1, lines.size)
        assertTrue(lines[0].startsWith("Sundays · 9:00"))
        assertTrue(lines[0].contains("(Spanish), 11:00"))
        assertEquals(listOf("1 Elm", "Dallas, TX 75146"), place.addressLines)
        assertEquals(listOf("Plain"), ChurchLocation(name = "X", address = "Plain").addressLines)
    }

    @Test
    fun blanksSplitOnlyKnownMarkers() {
        val known = setOf(1, 2)::contains
        val pieces = SermonBlanks.pieces("A [[1]] b [[9]] c [[2]]", known)
        assertEquals(4, pieces.size)
        assertEquals(listOf(1, 2), SermonBlanks.numbers("A [[1]] b [[9]] c [[2]]", known))
        assertEquals("A _____ b [[9]] c _____", SermonBlanks.filled("A [[1]] b [[9]] c [[2]]", known))
        assertEquals("[[1234]] x", SermonBlanks.filled("[[1234]] x", { true }))
    }

    @Test
    fun answersIgnoreCaseAccentsSpacingAndPunctuation() {
        assertTrue(SermonBlanks.isCorrect("  Gracia! ", "gracia"))
        assertTrue(SermonBlanks.isCorrect("God\u2019s   love", "god's love"))
        assertTrue(SermonBlanks.isCorrect("Fé", "fe"))
        assertFalse(SermonBlanks.isCorrect("", ""))
        assertFalse(SermonBlanks.isCorrect("hope", "faith"))
    }

    @Test
    fun linksOpenOnlyRealSlugs() {
        assertEquals("abcde12345", ChurchSermonLink.slug("https://versely.7twenty8studio.com/s/abcde12345"))
        assertEquals("abcde12345", ChurchSermonLink.slug("versely://sermon/abcde12345?x=1"))
        assertNull(ChurchSermonLink.slug("https://example.com/s/abcde12345"))
        assertNull(ChurchSermonLink.slug("https://versely.7twenty8studio.com/s/ABCDE12345"))
        assertNull(ChurchSermonLink.slug("versely://sermon/short"))
    }

    @Test
    fun copyKeepsTheChurchsWordsAndReferences() {
        val sermon = assertIs<ChurchSermonLookup.Found>(ChurchSermonWire.lookup(sample)).sermon
        val sections = SermonOutline.sections(sermon.blocks)
        assertEquals(1, sections.size)
        assertEquals("Our _____ hope\n\nGod is _____.\n\nJn 3:16 (NIV)\n\nBad", SermonOutline.copyText(sermon.blocks, sermon.blanks))
    }

    @Test
    fun savedHandoutsRoundTripAndKeepOtherRevisions() {
        val sermon = assertIs<ChurchSermonLookup.Found>(ChurchSermonWire.lookup(sample)).sermon
        val first = SavedHandouts.saving(emptyList(), sermon, mapOf(1 to "living"), now = 1_000)
        val older = first.single().copy(revision = 1)
        val saved = SavedHandouts.saving(listOf(older), sermon, mapOf(1 to "Living", 2 to "my words"), now = 2_000)
        assertEquals(2, saved.size)
        val raw = SavedHandouts.encode(saved)!!
        assertTrue(raw.contains("\"sermon_id\""))
        val back = SavedHandouts.decode(raw)
        assertEquals(listOf(1, 2), back.map { it.revision })
        assertEquals("my words", back[1].responses[2])
        assertTrue(back[1].hasKey)
        assertEquals(sermon.blocks, back[1].blocks.map { if (it is SermonBlock.Scripture) it.copy(reference = it.reference.copy(quoteWithheld = false)) else it })
    }
}
