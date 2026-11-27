package com.genesis.core.domain.sermons

/**
 * Sermon notes are stored as plain Markdown text, as SermonMarkdown.swift on
 * iOS: **bold**, *italic*, "## " headings, "- " bullets, "1. " numbered lists
 * and "> " quotes. The editor shows them formatted (`SermonEditing`).
 * Positions here are UTF-16 indices.
 */
object SermonMarkdown {
    enum class Format { BOLD, ITALIC, HEADING, BULLET, NUMBERED, QUOTE }

    /** The text after an edit, and what to select. */
    data class Edit(val text: String, val selectionStart: Int, val selectionEnd: Int = selectionStart)

    internal data class LineParts(val format: Format?, val content: String, val number: Int?) {
        /** Characters before the content (the mark). */
        fun prefixLength(line: String) = line.length - content.length
    }

    internal fun lineParts(line: String): LineParts {
        val hashes = line.takeWhile { it == '#' }.length
        if (hashes in 1..3 && line.drop(hashes).startsWith(" ")) return LineParts(Format.HEADING, line.drop(hashes + 1), null)
        if (line.startsWith("- ") || line.startsWith("* ") || line.startsWith("• ")) return LineParts(Format.BULLET, line.drop(2), null)
        val digits = line.takeWhile { it in '0'..'9' }
        if (digits.length in 1..3 && line.drop(digits.length).startsWith(". ")) return LineParts(Format.NUMBERED, line.drop(digits.length + 2), digits.toInt())
        if (line.startsWith("> ")) return LineParts(Format.QUOTE, line.drop(2), null)
        if (line == ">") return LineParts(Format.QUOTE, "", null)
        return LineParts(null, line, null)
    }

    fun lineFormat(line: String): Format? = lineParts(line).format

    fun stripLinePrefix(line: String): String = lineParts(line).content

    /** A list line's mark as typed ("- ", "• ", "3. "), or null. */
    fun listPrefix(line: String): String? {
        val parts = lineParts(line)
        if (parts.format != Format.BULLET && parts.format != Format.NUMBERED) return null
        return line.dropLast(parts.content.length)
    }

    /** Puts `snippet` (e.g. "John 3:16") at the cursor, spaced, or on a new line at the end when there's no cursor. */
    fun inserting(snippet: String, text: String, offset: Int?): Edit {
        if (offset == null) {
            val insertion = if (text.isNotEmpty() && !text.endsWith("\n")) "\n$snippet" else snippet
            val result = text + insertion
            return Edit(result, result.length)
        }
        val position = offset.coerceIn(0, text.length)
        var insertion = snippet
        if (position > 0 && !text[position - 1].isWhitespace()) insertion = " $insertion"
        if (position < text.length && !text[position].isWhitespace()) insertion += " "
        val result = text.substring(0, position) + insertion + text.substring(position)
        return Edit(result, position + insertion.length)
    }

    sealed interface BlockKind {
        data object Heading : BlockKind
        data object Bullet : BlockKind
        data class Numbered(val number: Int) : BlockKind
        data object Quote : BlockKind
        data object Paragraph : BlockKind
    }

    /** A line to show formatted; `text` still has its inline marks. */
    data class Block(val kind: BlockKind, val text: String)

    /** The notes as lines to show formatted. Blank lines are left out. */
    fun blocks(text: String): List<Block> = text.split("\n").mapNotNull { line ->
        if (line.isBlank()) return@mapNotNull null
        val parts = lineParts(line)
        val kind = when (parts.format) {
            Format.HEADING -> BlockKind.Heading
            Format.BULLET -> BlockKind.Bullet
            Format.NUMBERED -> BlockKind.Numbered(parts.number ?: 1)
            Format.QUOTE -> BlockKind.Quote
            else -> BlockKind.Paragraph
        }
        Block(kind, parts.content)
    }

    /** The notes without any marks, for search and previews. */
    fun plainText(text: String): String =
        text.split("\n").joinToString("\n") { stripLinePrefix(it) }
            .replace("\\*", "\u0001")
            .replace("**", "")
            .replace("*", "")
            .replace("__", "")
            .replace("\u0001", "*")

    /** A stretch of a line that is bold, italic, both or neither. */
    data class Span(val text: String, val bold: Boolean = false, val italic: Boolean = false)

    /** Where a line's inline marks are: each character hidden or shown, and its style. */
    internal class InlineMarks(val hidden: BooleanArray, val bold: BooleanArray, val italic: BooleanArray)

    /**
     * One line's characters read for bold and italic. A mark with no partner
     * is kept as typed, and "\*" is a plain asterisk (its backslash hidden).
     */
    internal fun inlineMarks(line: String): InlineMarks {
        val n = line.length
        val hidden = BooleanArray(n)
        val boldAt = BooleanArray(n)
        val italicAt = BooleanArray(n)
        var bold = false
        var italic = false
        var index = 0
        while (index < n) {
            val character = line[index]
            if (character == '\\' && index + 1 < n && line[index + 1] == '*') {
                hidden[index] = true
                boldAt[index + 1] = bold
                italicAt[index + 1] = italic
                index += 2
                continue
            }
            if (character != '*') {
                boldAt[index] = bold
                italicAt[index] = italic
                index++
                continue
            }
            var run = 0
            while (index + run < n && line[index + run] == '*') run++
            val width = minOf(run, 3)
            val togglesBold = width >= 2
            val togglesItalic = width != 2
            val closes = (!togglesBold || bold) && (!togglesItalic || italic) && index > 0 && !line[index - 1].isWhitespace()
            val opens = (!togglesBold || !bold) && (!togglesItalic || !italic) &&
                index + width < n && !line[index + width].isWhitespace() && hasCloser(line, index + width, width)
            if (closes || opens) {
                for (i in index until index + width) hidden[i] = true
                if (togglesBold) bold = !bold
                if (togglesItalic) italic = !italic
                index += width
            } else {
                for (i in index until index + run) {
                    boldAt[i] = bold
                    italicAt[i] = italic
                }
                index += run
            }
        }
        return InlineMarks(hidden, boldAt, italicAt)
    }

    private fun hasCloser(line: String, start: Int, width: Int): Boolean {
        var index = start
        while (index < line.length) {
            if (line[index] == '\\') {
                index += 2
                continue
            }
            if (line[index] != '*') {
                index++
                continue
            }
            var run = 0
            while (index + run < line.length && line[index + run] == '*') run++
            if (run >= width && index > start && !line[index - 1].isWhitespace()) return true
            index += run
        }
        return false
    }

    /** One line's text split where bold and italic start and end. */
    fun spans(line: String): List<Span> {
        val marks = inlineMarks(line)
        val spans = mutableListOf<Span>()
        val current = StringBuilder()
        var bold = false
        var italic = false
        for (i in line.indices) {
            if (marks.hidden[i]) continue
            if (current.isNotEmpty() && (marks.bold[i] != bold || marks.italic[i] != italic)) {
                spans += Span(current.toString(), bold, italic)
                current.clear()
            }
            bold = marks.bold[i]
            italic = marks.italic[i]
            current.append(line[i])
        }
        if (current.isNotEmpty()) spans += Span(current.toString(), bold, italic)
        return spans
    }
}
