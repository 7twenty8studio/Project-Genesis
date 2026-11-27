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
