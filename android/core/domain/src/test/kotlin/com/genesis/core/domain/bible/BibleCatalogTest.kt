package com.genesis.core.domain.bible

import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BibleCatalogTest {
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = true }

    @Test fun decodesCatalogRows() {
        val file = json.decodeFromString(DownloadableBible.serializer(), """{"id":"RV1909","name":"Reina-Valera 1909","year":"1909","license":"Dominio público","summary":"x","file_url":"https://a/b","file_bytes":6,"database_bytes":12,"sha256":"ab","version":1,"language":"es","rights":"public_domain","popularity":1,"premium":false,"sort":20,"enabled":true}""")
        assertEquals("es", file.language)
        assertEquals(false, file.isYouVersion)
        val yvp = json.decodeFromString(DownloadableBible.serializer(), """{"id":"OL","yvp_id":1967,"name":"O Livro","language":"pt-PT","version":1,"publisher_url":null}""")
        assertTrue(yvp.isYouVersion)
        assertEquals("pt", yvp.baseLanguage)
    }

    private fun entry(id: String, language: String, popularity: Int?, installed: Boolean = false, sort: Int = 0) =
        ReadingLibrary.Entry(id, id, language, popularity, sort, installed)

    @Test fun groupsRegionsUnderTheirLanguageMostReadFirst() {
        val entries = listOf(entry("KJV", "en", 1, true), entry("NIV", "en", null), entry("BSB", "en", 2), entry("OL", "pt-PT", null), entry("BLIVRE", "pt", 3, true))
        val sections = ReadingLibrary.sections(entries, "pt", "en")
        assertEquals(listOf("BLIVRE", "OL"), sections.single().second.map { it.id })
        assertEquals(listOf("KJV", "BSB", "NIV"), ReadingLibrary.sections(entries, "en", "en").single().second.map { it.id })
        assertEquals(listOf("en", "pt"), ReadingLibrary.languages(entries, "en"))
        assertEquals("pt", ReadingLibrary.defaultLanguage("pt-PT", "en", entries))
        assertEquals("en", ReadingLibrary.defaultLanguage("de", "en", entries))
    }

    @Test fun quickMenuPutsTheCurrentLanguageFirst() {
        val entries = listOf(entry("KJV", "en", 1, true), entry("RV1909", "es", 1, true), entry("NIV", "en", null))
        assertEquals(listOf("es", "en"), ReadingLibrary.groups(entries, "es").map { it.first })
        assertEquals(listOf("KJV"), ReadingLibrary.groups(entries, "es")[1].second.map { it.id })
    }
}

class YouVersionTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test fun decodesABookFromTheFunction() {
        val book = json.decodeFromString(YouVersionBook.serializer(), """{"id":"NIV","book":"JHN","chapters":[{"chapter":1,"maxAge":3600,"verses":[{"verse":1,"text":"In the beginning","paragraph":true,"poetry":false},{"verse":2,"last":3,"text":"He was with God","paragraph":false,"poetry":false}],"headings":[{"beforeVerse":1,"text":"The Word Became Flesh"}],"notes":[{"verse":2,"offset":2,"text":"Or x"}]}]}""")
        assertEquals(3600, book.chapters[0].maxAge)
        assertTrue(book.chapters[0].joinsVerses)
        assertEquals(2, book.chapters[0].notes[0].offset)
    }

    @Test fun retryAfterIsBounded() {
        assertEquals(42.0, YouVersionBuild.retryAfter("""{"retryAfter":42}"""))
        assertEquals(30.0, YouVersionBuild.retryAfter("nope"))
        assertEquals(600.0, YouVersionBuild.retryAfter("""{"retryAfter":9000}"""))
    }

    @Test fun unchangedChaptersAreNotRewritten() {
        val a = YouVersionBook.Chapter(1, listOf(YouVersionBook.Verse(2, null, "b"), YouVersionBook.Verse(1, 1, "a"), YouVersionBook.Verse(3, null, "")), notes = listOf(YouVersionBook.Note(1, -3, "n")))
        val b = YouVersionBook.Chapter(1, listOf(YouVersionBook.Verse(1, null, "a"), YouVersionBook.Verse(2, null, "b")), notes = listOf(YouVersionBook.Note(1, 0, "n")), maxAge = 10)
        assertEquals(false, YouVersionBuild.differs(a, b))
        assertTrue(YouVersionBuild.differs(a, b.copy(verses = listOf(YouVersionBook.Verse(1, null, "A")))))
    }

    @Test fun freshnessFollowsMaxAge() {
        val f = YouVersionFreshness().setting(43, 3, fetchedAt = 1_000, maxAge = 10)
        assertEquals(false, f.isStale(43, 3, 10_999))
        assertTrue(f.isStale(43, 3, 11_000))
        assertTrue(f.isStale(43, 4, 0))
    }

    @Test fun searchFormJoinsHyphenatedNames() {
        assertEquals("Beth–lehem Bethlehem of Judah", BibleSearchForm.indexed("Beth–lehem of Judah"))
        assertEquals("plain", BibleSearchForm.indexed("plain"))
        assertEquals("a", BibleSearchForm.footnoteLabel(0))
        assertEquals("aa", BibleSearchForm.footnoteLabel(26))
    }
}
