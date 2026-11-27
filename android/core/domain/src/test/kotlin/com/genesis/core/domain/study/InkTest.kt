package com.genesis.core.domain.study

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The cases iOS shares (NoteInkTests.swift), from supabase/functions/_shared/fixtures/ink.json. */
class InkTest {
    private val fixtures: JsonObject = run {
        val text = javaClass.classLoader.getResourceAsStream("ink.json")!!.use { it.readBytes().decodeToString() }
        Json.parseToJsonElement(text).jsonObject
    }
    private val expect = fixtures.getValue("expect").jsonObject

    private fun page() = assertNotNull(InkFormat.decode(fixtures.getValue("page").toString()))

    @Test fun readsTheSharedPage() {
        val page = page()
        assertEquals(expect.getValue("strokes").jsonPrimitive.int, page.strokes.size)
        assertEquals(expect.getValue("inks").jsonArray.map { it.jsonPrimitive.content }, page.strokes.map { it.ink.id })
        assertEquals(expect.getValue("colors").jsonArray.map { it.jsonPrimitive.content }, page.strokes.map { InkFormat.hex(it.color) })
        assertEquals(expect.getValue("points").jsonArray.map { it.jsonPrimitive.int }, page.strokes.map { it.points.size })
        assertEquals(expect.getValue("defaultSize").jsonPrimitive.double, page.strokes[2].points[0].size)
        assertEquals(expect.getValue("bottom").jsonPrimitive.double, page.bottom, 0.001)
    }

    @Test fun writesWhatItReads() {
        val page = page()
        val again = assertNotNull(InkFormat.decode(InkFormat.encode(page)))
        assertEquals(page, again)
    }

    @Test fun anEmptyPageIsNoPage() {
        assertNull(InkFormat.encode(InkPage()))
    }

    @Test fun refusesWhatIsntVerselyInk() {
        for (text in fixtures.getValue("rejected").jsonArray.map { it.jsonPrimitive.content }) assertNull(InkFormat.decode(text), text)
    }

    @Test fun followsTheSharedSpline() {
        val spline = fixtures.getValue("spline").jsonObject
        val c = spline.getValue("controls").jsonArray.map { p ->
            val v = p.jsonArray.map { it.jsonPrimitive.double }
            InkPoint(v[0], v[1], v[2], v[3])
        }
        for (case in spline.getValue("at").jsonArray.map { it.jsonObject }) {
            val t = case.getValue("t").jsonPrimitive.double
            val want = case.getValue("point").jsonArray.map { it.jsonPrimitive.double }
            val got = InkSpline.at(c[0], c[1], c[2], c[3], t)
            assertEquals(want[0], got.x, 0.001)
            assertEquals(want[1], got.y, 0.001)
            assertEquals(want[2], got.size, 0.001)
            assertEquals(want[3], got.opacity, 0.001)
        }
    }

    @Test fun capturedStrokesReachBothEnds() {
        val stroke = assertNotNull(InkCapture.stroke(InkType.PEN, 0x000000FF, listOf(InkPoint(0.0, 0.0, 2.0), InkPoint(0.1, 0.0, 2.0), InkPoint(50.0, 0.0, 2.0))))
        val sampled = InkSpline.sample(stroke.points)
        assertEquals(0.0, sampled.first().x, 0.001)
        assertEquals(50.0, sampled.last().x, 0.001)
        // The point a tenth of a point away was dropped.
        assertEquals(2 + 2 + 2, stroke.points.size)
    }

    @Test fun aTapIsADot() {
        val stroke = assertNotNull(InkCapture.stroke(InkType.PEN, 0x000000FF, listOf(InkPoint(5.0, 5.0, 3.0))))
        assertEquals(1, stroke.points.size)
    }

    @Test fun theEraserTakesWholeStrokes() {
        val page = page()
        val erased = InkEraser.erase(page, 100.0, 200.0, 4.0)
        assertEquals(2, erased.strokes.size)
        assertTrue(erased.strokes.none { it.ink == InkType.MARKER })
        assertEquals(page, InkEraser.erase(page, 700.0, 700.0, 4.0))
    }

    @Test fun pagesOverTheLimitStayOnTheDevice() {
        assertTrue(InkFormat.fitsSync(null))
        assertTrue(!InkFormat.fitsSync("x".repeat(InkFormat.MAX_SYNCED_BYTES + 1)))
    }
}
