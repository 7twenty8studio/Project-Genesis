package com.genesis.core.domain.bible

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The cases iOS (ReferenceParserTests.swift) and the web (references.test.ts)
 * already share, from supabase/functions/_shared/fixtures/references.json:
 * a reference means the same passage on every client.
 */
class ReferenceParserTest {
    private val fixtures: JsonObject = run {
        val text = javaClass.classLoader.getResourceAsStream("references.json")!!.use { it.readBytes().decodeToString() }
        Json.parseToJsonElement(text).jsonObject
    }

    private fun cases(key: String) = fixtures.getValue(key).jsonArray.map { it.jsonObject }
    private fun JsonObject.int(key: String): Int? = (get(key) as? JsonElement)?.takeIf { it !is JsonNull }?.jsonPrimitive?.intOrNull
    private fun JsonObject.string(key: String): String = getValue(key).jsonPrimitive.content

    @Test fun parsesEverySharedCase() {
        for (case in cases("parse")) {
            val input = case.string("input")
            val ref = assertNotNull(ReferenceParser.parse(input), input)
            assertEquals(case.int("book"), ref.book.id, input)
            assertEquals(case.int("chapter"), ref.chapter, input)
            assertEquals(case.int("verse"), ref.verseStart, input)
            assertEquals(case.int("end"), ref.verseEnd, input)
        }
    }

    @Test fun portugueseAbbreviationsWinInPortuguese() {
        for (case in cases("portugueseFirst")) {
            val input = case.string("input")
            assertEquals(case.int("book"), ReferenceParser.parse(input, portugueseFirst = true)?.book?.id, input)
        }
        assertEquals(33, ReferenceParser.parse("Mc 4")?.book?.id)
    }

    @Test fun rejectsWhatIsNotAReference() {
        for (input in fixtures.getValue("rejects").jsonArray.map { it.jsonPrimitive.content }) {
            assertNull(ReferenceParser.parse(input), input)
        }
    }

    @Test fun resolvesSermonReferences() {
        for (case in cases("resolve")) {
            val input = case.string("input")
            val resolved = ReferenceParser.resolve(input)
            assertEquals(case.string("status").uppercase(), resolved.status.name, input)
            assertEquals(case.int("start"), resolved.start, input)
            assertEquals(case.int("end"), resolved.end, input)
            assertEquals(input.trim(), resolved.raw)
        }
    }

    @Test fun namesPassagesAsTheAppDoes() {
        for (case in cases("describe")) {
            assertEquals(case.string("text"), ReferenceParser.describe(case.int("start")!!, case.int("end")!!, case.string("language")))
        }
    }

    @Test fun suggestsBooksWhileTyping() {
        assertTrue(ReferenceParser.booksMatching("phil").map { it.id }.contains(50))
        assertEquals(43, ReferenceParser.booksMatching("joh").firstOrNull()?.id)
        assertEquals(emptyList(), ReferenceParser.booksMatching("John 3"))
        assertEquals(listOf(66), ReferenceParser.booksMatching("Apoc").map { it.id })
    }

    @Test fun verseIdsFollowTheKjvNumbering() {
        assertTrue(ReferenceParser.isValidVerseId(19119176))
        assertTrue(!ReferenceParser.isValidVerseId(19119177))
        assertTrue(!ReferenceParser.isValidVerseId(43000001))
        assertTrue(!ReferenceParser.isValidVerseId(67001001))
        assertEquals(66, BibleBooks.all.size)
        assertEquals(1189, BibleBooks.all.sumOf { it.verses.size })
    }
}
