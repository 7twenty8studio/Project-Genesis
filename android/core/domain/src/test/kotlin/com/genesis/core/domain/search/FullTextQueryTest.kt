package com.genesis.core.domain.search

import com.genesis.core.domain.bible.Testament
import com.genesis.core.domain.bible.VerseId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The same cases as FullTextQueryTests on iOS. */
class FullTextQueryTest {
    @Test fun wordsAreQuotedAndLastIsPrefix() {
        val query = assertNotNull(FullTextQuery.of("faith hope"))
        assertEquals("\"faith\" \"hope\"*", query.matchExpression)
        assertEquals(listOf("faith", "hope"), query.terms)
    }

    @Test fun trailingSpaceEndsPrefix() {
        assertEquals("\"faith\" \"hope\"", FullTextQuery.of("faith hope ")?.matchExpression)
    }

    @Test fun quotedTextIsAPhrase() {
        val query = assertNotNull(FullTextQuery.of("“The Lord is my shepherd”"))
        assertTrue(query.isPhrase)
        assertEquals("\"the lord is my shepherd\"", query.matchExpression)
    }

    @Test fun accentsAndOtherScriptsStayLetters() {
        assertEquals(listOf("jehová", "es", "mi", "pastor"), FullTextQuery.of("Jehová es mi pastor")?.terms)
    }

    @Test fun operatorsAreNeutralised() {
        val query = assertNotNull(FullTextQuery.of("love OR NEAR(x) * -hate"))
        assertFalse(query.matchExpression.contains("OR "))
        assertTrue(query.matchExpression.contains("\"or\""))
        assertFalse(query.matchExpression.contains("("))
    }

    @Test fun emptyInputHasNoQuery() {
        assertNull(FullTextQuery.of("  "))
        assertNull(FullTextQuery.of("!!!"))
    }

    @Test fun highlighterMatchesWordStarts() {
        val text = "For God so loved the world"
        assertEquals(listOf("loved", "world"), SearchHighlighter.matchRanges(text, listOf("love", "world")).map { text.substring(it) })
    }

    @Test fun scopesCoverTheirBooks() {
        assertTrue(VerseId(39, 4, 6).rawValue in SearchScope.InTestament(Testament.OLD).idRange)
        assertFalse(VerseId(40, 1, 1).rawValue in SearchScope.InTestament(Testament.OLD).idRange)
        assertTrue(VerseId(43, 3, 16).rawValue in SearchScope.Book(43).idRange)
        assertTrue(VerseId(66, 22, 21).rawValue in SearchScope.WholeBible.idRange)
    }
}

class PassageReferenceTest {
    @Test fun describesWhatWasTyped() {
        val john = com.genesis.core.domain.bible.ReferenceParser.parse("jn 3:16-18")!!
        assertEquals("John 3:16–18", john.description("en"))
        assertEquals(VerseId(43, 3, 16), john.firstVerse)
        val psalm = com.genesis.core.domain.bible.ReferenceParser.parse("Ps 23")!!
        assertEquals("Salmos 23", psalm.description("es"))
        assertEquals(VerseId(19, 23, 1), psalm.firstVerse)
    }
}
