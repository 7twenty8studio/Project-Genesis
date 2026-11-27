package com.genesis.core.domain.sermons

import com.genesis.core.domain.sermons.SermonMarkdown.Edit
import com.genesis.core.domain.sermons.SermonMarkdown.Format

/**
 * The sermon notes editor shows the notes formatted while they're saved as
 * Markdown, as SermonRichText on iOS: the marks are hidden, bold and italic
 * are fonts, headings and quotes a line style, bullets "• ". Pure, so the
 * editor's view (a visual transformation over the Markdown) can be tested.
 */
object SermonEditing {
    enum class Style { BOLD, ITALIC, HEADING, QUOTE }

    data class StyleRange(val style: Style, val start: Int, val end: Int)

    /** What the editor shows for some Markdown, and how positions map both ways. */
    class Display(
        val text: String,
        /** For each Markdown position (0…length), the shown position. */
        val toShown: IntArray,
        /** For each shown position (0…length), the Markdown position. */
        val toMarkdown: IntArray,
        /** In shown positions. */
        val styles: List<StyleRange>,
    )

    fun display(markdown: String): Display {
        val n = markdown.length
        val hidden = BooleanArray(n)
        val shownChar = markdown.toCharArray()
        val bold = BooleanArray(n)
        val italic = BooleanArray(n)
        val line = arrayOfNulls<Style>(n)
        var lineStart = 0
        for (raw in markdown.split("\n")) {
            val parts = SermonMarkdown.lineParts(raw)
            val prefix = parts.prefixLength(raw)
            val lineStyle = when (parts.format) {
                Format.HEADING -> Style.HEADING
                Format.QUOTE -> Style.QUOTE
                else -> null
            }
            when (parts.format) {
                Format.HEADING, Format.QUOTE -> for (i in 0 until prefix) hidden[lineStart + i] = true
                Format.BULLET -> shownChar[lineStart] = '•'
                else -> Unit
            }
            val marks = SermonMarkdown.inlineMarks(parts.content)
            for (i in parts.content.indices) {
                val at = lineStart + prefix + i
                if (marks.hidden[i]) hidden[at] = true
                bold[at] = marks.bold[i]
                italic[at] = marks.italic[i]
                line[at] = lineStyle
            }
            lineStart += raw.length + 1
        }

        val shown = StringBuilder()
        val toShown = IntArray(n + 1)
        val toMarkdown = mutableListOf<Int>()
        for (i in 0 until n) {
            toShown[i] = shown.length
            if (!hidden[i]) {
                toMarkdown += i
                shown.append(shownChar[i])
            }
        }
        toShown[n] = shown.length
        // A shown position maps to just before its character, so a cursor after
        // "**bold**" lands after the closing marks and typing there is plain.
        val back = IntArray(shown.length + 1)
        for (t in 0 until shown.length) back[t] = toMarkdown[t]
        back[shown.length] = n

        val styles = mutableListOf<StyleRange>()
        fun collect(style: Style, on: (Int) -> Boolean) {
            var start = -1
            for (t in 0..shown.length) {
                val active = t < shown.length && on(toMarkdown[t])
                if (active && start < 0) start = t
                if (!active && start >= 0) {
                    styles += StyleRange(style, start, t)
                    start = -1
                }
            }
        }
        collect(Style.BOLD) { bold[it] }
        collect(Style.ITALIC) { italic[it] }
        collect(Style.HEADING) { line[it] == Style.HEADING }
        collect(Style.QUOTE) { line[it] == Style.QUOTE }
        return Display(shown.toString(), toShown, back, styles)
    }

    // MARK: Bold and italic

    /**
     * Bold or italic on the selection (or the word at the cursor), or off
     * where it's already marked. Marks hug the words, so spaces at either
     * end of the selection stay outside.
     */
    fun toggleInline(text: String, start: Int, end: Int, format: Format): Edit {
        val mark = if (format == Format.BOLD) "**" else "*"
        var s = minOf(start, end).coerceIn(0, text.length)
        var e = maxOf(start, end).coerceIn(0, text.length)
        val cursor = if (start == end) start else null
        if (s == e) {
            // The word around the cursor.
            while (s > 0 && text[s - 1].isLetterOrDigit()) s--
            while (e < text.length && text[e].isLetterOrDigit()) e++
            if (s == e) return Edit(text, start, end)
        }
        while (s < e && text[s].isWhitespace()) s++
        while (e > s && text[e - 1].isWhitespace()) e--
        if (s == e) return Edit(text, start, end)

        val before = run(text, s, backwards = true)
        val after = run(text, e, backwards = false)
        val marked = if (format == Format.BOLD) before >= 2 && after >= 2 else (before == 1 || before == 3) && (after == 1 || after == 3)
        if (marked) {
            val result = text.substring(0, s - mark.length) + text.substring(s, e) + text.substring(e + mark.length)
            val shift = mark.length
            return if (cursor != null) Edit(result, cursor - shift) else Edit(result, s - shift, e - shift)
        }
        val result = text.substring(0, s) + mark + text.substring(s, e) + mark + text.substring(e)
        return if (cursor != null) Edit(result, cursor + mark.length) else Edit(result, s + mark.length, e + mark.length)
    }

    private fun run(text: String, from: Int, backwards: Boolean): Int {
        var count = 0
        if (backwards) {
            while (from - count - 1 >= 0 && text[from - count - 1] == '*') count++
        } else {
            while (from + count < text.length && text[from + count] == '*') count++
        }
        return count
    }

    // MARK: Line formats

    /**
     * A heading, list or quote on every line the selection touches, or back
     * to plain text when they all have it already. The cursor keeps its place
     * in the words.
     */
    fun toggleLine(text: String, start: Int, end: Int, format: Format): Edit {
        val lines = text.split("\n").toMutableList()
        val s = minOf(start, end).coerceIn(0, text.length)
        val e = maxOf(start, end).coerceIn(0, text.length)
        val firstLine = text.substring(0, s).count { it == '\n' }
        val lastLine = text.substring(0, e).count { it == '\n' }
        val touched = firstLine..lastLine
        val allHave = touched.all { SermonMarkdown.lineFormat(lines[it]) == format }
        // Each line's new prefix length minus its old one, for moving the selection.
        val deltas = IntArray(lines.size)
        var number = 1
        for (i in touched) {
            val parts = SermonMarkdown.lineParts(lines[i])
            val oldPrefix = parts.prefixLength(lines[i])
            val prefix = if (allHave) "" else when (format) {
                Format.HEADING -> "## "
                Format.BULLET -> "- "
                Format.NUMBERED -> "${number++}. "
                Format.QUOTE -> "> "
                else -> lines[i].substring(0, oldPrefix)
            }
            lines[i] = prefix + parts.content
            deltas[i] = prefix.length - oldPrefix
        }
        fun moved(position: Int): Int {
            var lineIndex = 0
            var lineStart = 0
            for ((i, line) in text.split("\n").withIndex()) {
                if (position <= lineStart + line.length) {
                    lineIndex = i
                    break
                }
                lineStart += line.length + 1
            }
            val oldPrefix = text.split("\n")[lineIndex].let { SermonMarkdown.lineParts(it).prefixLength(it) }
            val inContent = maxOf(0, position - lineStart - oldPrefix)
            var newStart = 0
            for (i in 0 until lineIndex) newStart += lines[i].length + 1
            val newPrefix = lines[lineIndex].let { SermonMarkdown.lineParts(it).prefixLength(it) }
            return newStart + newPrefix + inContent
        }
        val result = lines.joinToString("\n")
        return Edit(result, moved(start).coerceIn(0, result.length), moved(end).coerceIn(0, result.length))
    }

    /** The format of the line the cursor is on (for the toolbar). */
    fun lineFormat(text: String, cursor: Int): Format? {
        val position = cursor.coerceIn(0, text.length)
        val lineStart = text.lastIndexOf('\n', position - 1) + 1
        val lineEnd = text.indexOf('\n', position).let { if (it < 0) text.length else it }
        return SermonMarkdown.lineFormat(text.substring(lineStart, lineEnd))
    }

    // MARK: Return

    /**
     * After Return: a list or quote carries on to the new line ("- ", the
     * next number, "> "); Return on an empty item ends it. Null when the
     * change wasn't a Return after such a line.
     */
    fun afterReturn(old: String, new: String, cursor: Int): Edit? {
        if (new.length != old.length + 1 || cursor < 1 || cursor > new.length || new[cursor - 1] != '\n') return null
        if (new.substring(0, cursor - 1) + new.substring(cursor) != old) return null
        val lineStart = new.lastIndexOf('\n', cursor - 2) + 1
        val ended = new.substring(lineStart, cursor - 1)
        val parts = SermonMarkdown.lineParts(ended)
        val continuation = when (parts.format) {
            Format.BULLET -> if (ended.startsWith("* ")) "* " else "- "
            Format.NUMBERED -> "${(parts.number ?: 0) + 1}. "
            Format.QUOTE -> "> "
            else -> return null
        }
        if (parts.content.isBlank()) {
            // An empty item ends the list: the mark and the new line go.
            val result = new.substring(0, lineStart) + new.substring(cursor)
            return Edit(result, lineStart)
        }
        val result = new.substring(0, cursor) + continuation + new.substring(cursor)
        return Edit(result, cursor + continuation.length)
    }
}
