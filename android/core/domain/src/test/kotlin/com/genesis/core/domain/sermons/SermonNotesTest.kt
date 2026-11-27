package com.genesis.core.domain.sermons

import com.genesis.core.domain.sermons.SermonMarkdown.Format
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SermonNotesTest {
    @Test fun linesAndPlainText() {
        assertEquals(Format.HEADING, SermonMarkdown.lineFormat("## Grace"))
        assertEquals(Format.NUMBERED, SermonMarkdown.lineFormat("12. Point"))
        assertEquals("- ", SermonMarkdown.listPrefix("- item"))
        assertNull(SermonMarkdown.lineFormat("#nope"))
        assertEquals("Grace\nis *free*\nloved", SermonMarkdown.plainText("## Grace\n- is \\*free\\*\n> **loved**"))
    }

    @Test fun spans() {
        assertEquals(
            listOf(SermonMarkdown.Span("a "), SermonMarkdown.Span("b", bold = true), SermonMarkdown.Span(" "), SermonMarkdown.Span("c", italic = true)),
            SermonMarkdown.spans("a **b** *c*"),
        )
        assertEquals(listOf(SermonMarkdown.Span("2 * 3 = 6")), SermonMarkdown.spans("2 * 3 = 6"))
        assertEquals(listOf(SermonMarkdown.Span("x", bold = true, italic = true)), SermonMarkdown.spans("***x***"))
    }

    @Test fun displayHidesMarks() {
        val display = SermonEditing.display("## Title\n- one **two**\n> said")
        assertEquals("Title\n• one two\nsaid", display.text)
        assertTrue(SermonEditing.StyleRange(SermonEditing.Style.HEADING, 0, 5) in display.styles)
        assertTrue(SermonEditing.StyleRange(SermonEditing.Style.BOLD, 12, 15) in display.styles)
        // The start of the heading's words, and after the closing marks.
        assertEquals(3, display.toMarkdown[0])
        assertEquals(display.toMarkdown.size - 1, display.text.length)
        assertEquals(14, display.toShown[19])
        assertEquals(22, display.toMarkdown[15])
    }

    @Test fun boldOnAndOff() {
        val on = SermonEditing.toggleInline("grace alone", 0, 5, Format.BOLD)
        assertEquals("**grace** alone", on.text)
        assertEquals(2 to 7, on.selectionStart to on.selectionEnd)
        val off = SermonEditing.toggleInline(on.text, on.selectionStart, on.selectionEnd, Format.BOLD)
        assertEquals("grace alone", off.text)
        // The word at the cursor.
        assertEquals("grace *alone*", SermonEditing.toggleInline("grace alone", 8, 8, Format.ITALIC).text)
    }

    @Test fun lineFormats() {
        val bullets = SermonEditing.toggleLine("one\ntwo", 0, 7, Format.BULLET)
        assertEquals("- one\n- two", bullets.text)
        assertEquals("1. one\n2. two", SermonEditing.toggleLine(bullets.text, 0, bullets.text.length, Format.NUMBERED).text)
        assertEquals("one\ntwo", SermonEditing.toggleLine(bullets.text, 0, bullets.text.length, Format.BULLET).text)
        val heading = SermonEditing.toggleLine("Title", 2, 2, Format.HEADING)
        assertEquals("## Title", heading.text)
        assertEquals(5, heading.selectionStart)
    }

    @Test fun returnCarriesListsOn() {
        val next = SermonEditing.afterReturn("1. first", "1. first\n", 9)!!
        assertEquals("1. first\n2. ", next.text)
        assertEquals(12, next.selectionStart)
        val ended = SermonEditing.afterReturn("- a\n- ", "- a\n- \n", 7)!!
        assertEquals("- a\n", ended.text)
        assertNull(SermonEditing.afterReturn("plain", "plain\n", 6))
    }

    @Test fun inserting() {
        assertEquals(SermonMarkdown.Edit("read John 3:16 now", 15), SermonMarkdown.inserting("John 3:16", "read now", 5))
        assertEquals("notes\nJohn 3:16", SermonMarkdown.inserting("John 3:16", "notes", null).text)
        assertEquals("read John", SermonMarkdown.inserting("John", "read", 4).text)
    }

    private fun sermon(id: String, day: LocalDate, church: String = "", title: String = "t") =
        Sermon(id = id, title = title, church = church, preachedAt = day.atStartOfDay(ZoneId.of("UTC")).toInstant().toEpochMilli(), createdAt = 0, updatedAt = 0)

    @Test fun grouping() {
        val today = LocalDate.of(2026, 11, 27) // a Friday
        val sermons = listOf(
            sermon("a", LocalDate.of(2026, 11, 22), "Grace Church"),
            sermon("b", LocalDate.of(2026, 10, 4), "grace  church"),
            sermon("c", LocalDate.of(2026, 9, 6)),
        )
        val byDate = SermonGrouping.byDate(sermons, today, ZoneId.of("UTC"), Locale.US)
        assertEquals(listOf("a"), byDate.first().sermons.map { it.id })
        assertEquals(SermonGrouping.Kind.ThisWeek, byDate.first().kind)
        assertEquals(3, byDate.size)
        val byChurch = SermonGrouping.byChurch(sermons)
        assertEquals(SermonGrouping.Kind.Church("Grace Church"), byChurch.first().kind)
        assertEquals(SermonGrouping.Kind.NoChurch, byChurch.last().kind)
        assertEquals(listOf("Grace Church"), SermonGrouping.churchSuggestions(sermons, "gra"))
        assertTrue(SermonSearch.matches(sermons[0], "GRACE"))
    }
}
