package com.genesis.core.domain.original

import com.genesis.core.domain.bible.OriginalVersification
import com.genesis.core.domain.bible.VerseId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OriginalTest {
    private fun word(verse: VerseId, position: Int, text: String, edition: GreekEdition? = null, found: Int = 0) =
        OriginalWord(verse, position, text, "", null, "gloss", "", edition = edition, foundIn = found)

    @Test fun glossKeysMatchTheBuildScript() {
        assertEquals(4_483_138_548_866_997_674L, GlossKey.of("H0430G", "HNcmpa", "God"))
        assertEquals(610_775_443_798_759_267L, GlossKey.of("", "", ""))
    }

    @Test fun strongsNumbers() {
        assertEquals("H0430", StrongsNumber.normalized("h430"))
        assertEquals("H1254A", StrongsNumber.normalized("H1254a"))
        assertEquals("G2316", StrongsNumber.normalized(" G2316 "))
        assertNull(StrongsNumber.normalized("X12"))
        assertNull(StrongsNumber.normalized("H12AB"))
        assertNull(StrongsNumber.normalized("H"))
        assertEquals("H1254", StrongsNumber.base("H1254A"))
        assertEquals("G2316", StrongsNumber.base("G2316"))
    }

    @Test fun verseDeltas() {
        assertEquals(listOf(1001001, 1001003, 1002001), decodeVerseDeltas("1001001,2,998"))
    }

    @Test fun greekSources() {
        assertEquals(GreekEdition.TEXTUS_RECEPTUS, OriginalSource.greek("KJV")?.edition)
        assertEquals(true, OriginalSource.greek("WEB")?.isExact)
        assertEquals(GreekEdition.WESTCOTT_HORT, OriginalSource.greek("ASV")?.edition)
        val other = OriginalSource.parallelGreek("BLIVRE")
        assertEquals(GreekEdition.NESTLE_ALAND, other.edition)
        assertFalse(other.isKnownSource)
    }

    @Test fun dottedWordsAreThoseTheComparedEditionLacks() {
        val verse = VerseId(42, 2, 14)
        assertTrue(word(verse, 1, "x", GreekEdition.TEXTUS_RECEPTUS, found = 4).isNotInComparison)
        assertFalse(word(verse, 1, "x", GreekEdition.TEXTUS_RECEPTUS, found = 5).isNotInComparison)
        assertTrue(word(verse, 1, "x", GreekEdition.NESTLE_ALAND, found = 1).isNotInComparison)
        assertFalse(word(VerseId(1, 1, 1), 1, "x").isNotInComparison)
    }

    @Test fun glossLanguageFollowsTheBible() {
        assertEquals("es", GlossLanguage.code(GlossLanguageChoice.BIBLE, "es"))
        assertEquals("pt", GlossLanguage.code(GlossLanguageChoice.BIBLE, "pt-PT"))
        assertEquals("en", GlossLanguage.code(GlossLanguageChoice.BIBLE, "fr"))
        assertEquals("pt", GlossLanguage.code(GlossLanguageChoice.PORTUGUESE, "en"))
        assertEquals(GlossLanguageChoice.BIBLE, GlossLanguageChoice.of(null))
    }

    @Test fun maqafJoinsAndPaseqStandsApart() {
        val words = listOf("כָּל־", "הַ", "אֵל׀", "x")
        assertEquals("כָּל־הַ אֵל ׀ x", OriginalText.joined(words))
        assertEquals("", OriginalText.joined(emptyList()))
        assertEquals("a b", OriginalText.joined(listOf("a", "", "b")))
    }

    @Test fun parallelRowsGroupVersesAndPreview() {
        val words = (1..3).associate { VerseId(45, 16, it) to listOf(word(VerseId(45, 16, it), 1, "w$it")) }
        val verses = (1..3).map { ParallelVerse(VerseId(45, 16, it), "v$it") }
        val rows = OriginalParallel.rows(verses, OriginalVersification.parallelMap("KJV"), words, limit = 2)
        assertEquals(listOf(1, 1, 0), rows.map { it.words.size })
        assertTrue(rows.none { it.isContinuation })
        assertNull(rows[0].covers)
    }

    @Test fun pronunciation() {
        assertEquals(
            "בְּרֵאשִׁית",
            PronunciationText.spoken("בְּרֵאשִׁ֖ית", OriginalLanguage.HEBREW),
        )
        assertEquals("הָאָרֶץ", PronunciationText.spoken("הָֽאָרֶץ׃", OriginalLanguage.HEBREW))
        assertEquals("כָּל הַ", PronunciationText.spoken("כָּל־הַ", OriginalLanguage.HEBREW))
        assertEquals("אֵל", PronunciationText.spoken("אֵל ׀", OriginalLanguage.HEBREW))
        assertEquals("Εν", PronunciationText.spoken("Ἐν", OriginalLanguage.GREEK))
        assertEquals("αρχή", PronunciationText.spoken("ἀρχῇ", OriginalLanguage.GREEK))
        assertEquals("θεόν", PronunciationText.spoken("θεὸν,", OriginalLanguage.GREEK))
        assertEquals("ήν", PronunciationText.spoken("ἦν·", OriginalLanguage.GREEK))
        assertEquals("Ιησούς", PronunciationText.spoken("Ἰησοῦς", OriginalLanguage.GREEK))
        assertEquals("δι", PronunciationText.spoken("δι’", OriginalLanguage.GREEK))
        assertEquals("", PronunciationText.spoken("·", OriginalLanguage.GREEK))
    }

    @Test fun greekMorphology() {
        val verb = Morphology("V-AAI-3S", OriginalLanguage.GREEK)
        assertEquals(PartOfSpeech.VERB, verb.partOfSpeech)
        assertEquals(Morphology.Tense.AORIST, verb.tense)
        assertEquals(Morphology.Voice.ACTIVE, verb.voice)
        assertEquals(Morphology.Mood.INDICATIVE, verb.mood)
        assertEquals(3, verb.person)
        assertEquals(Morphology.Number.SINGULAR, verb.number)
        val participle = Morphology("V-PAP-NSM", OriginalLanguage.GREEK)
        assertEquals(Morphology.Case.NOMINATIVE, participle.grammaticalCase)
        assertEquals(Morphology.Gender.MASCULINE, participle.gender)
        val noun = Morphology("N-GSF", OriginalLanguage.GREEK)
        assertEquals(PartOfSpeech.NOUN, noun.partOfSpeech)
        assertEquals(Morphology.Case.GENITIVE, noun.grammaticalCase)
        assertEquals(PartOfSpeech.CONJUNCTION, Morphology("CONJ", OriginalLanguage.GREEK).partOfSpeech)
        val pronoun = Morphology("P-1GS", OriginalLanguage.GREEK)
        assertEquals(1, pronoun.person)
        assertEquals(Morphology.Case.GENITIVE, pronoun.grammaticalCase)
        val possessive = Morphology("S-1SNSM", OriginalLanguage.GREEK)
        assertEquals(1, possessive.person)
        assertEquals(Morphology.Case.NOMINATIVE, possessive.grammaticalCase)
        assertEquals(Morphology.Gender.MASCULINE, possessive.gender)
    }

    @Test fun hebrewMorphology() {
        val verb = Morphology("HC/Vqw3ms", OriginalLanguage.HEBREW)
        assertEquals(PartOfSpeech.VERB, verb.partOfSpeech)
        assertEquals("Qal", verb.stem)
        assertEquals(Morphology.VerbForm.SEQUENTIAL_IMPERFECT, verb.verbForm)
        assertEquals(3, verb.person)
        assertEquals(listOf(Morphology.Prefix.CONJUNCTION), verb.prefixes)
        val noun = Morphology("HNcmpc/Sp2ms", OriginalLanguage.HEBREW)
        assertEquals(PartOfSpeech.NOUN, noun.partOfSpeech)
        assertEquals(Morphology.State.CONSTRUCT, noun.state)
        assertEquals(Morphology.Suffix(2, Morphology.Gender.MASCULINE, Morphology.Number.SINGULAR), noun.suffix)
        assertEquals(PartOfSpeech.PROPER_NOUN, Morphology("HNpm", OriginalLanguage.HEBREW).partOfSpeech)
        val aramaic = Morphology("AVqp3ms", OriginalLanguage.HEBREW)
        assertTrue(aramaic.isAramaic)
        assertEquals("Peal", aramaic.stem)
        assertTrue(noun.details.any { it is Morphology.Detail.PronounSuffix })
    }
}
