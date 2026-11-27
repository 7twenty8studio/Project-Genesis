package com.genesis.app.reader

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ParagraphStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.style.TextIndent
import com.genesis.core.domain.bible.ScriptureDirection
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.em
import com.genesis.core.bible.Chapter
import com.genesis.core.bible.Verse
import com.genesis.core.design.ReaderColors
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.study.HighlightColor
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextDecoration

/**
 * Verses run on with small raised numbers, as in a printed Bible. The words
 * are exactly as stored: only their style changes. Each verse keeps its id as
 * an annotation, ready for taps, highlights and selection.
 */
internal fun AnnotatedString.Builder.appendVerses(verses: List<Verse>, colors: ReaderColors, marks: VerseMarks = VerseMarks()) {
    val poetry = verses.firstOrNull()?.isPoetry == true
    verses.forEachIndexed { index, verse ->
        if (index > 0) append(if (poetry) "\n" else " ")
        pushStringAnnotation(tag = VERSE_TAG, annotation = verse.id.rawValue.toString())
        withStyle(SpanStyle(color = colors.accent, fontSize = 0.6.em, fontWeight = FontWeight.Medium, baselineShift = BaselineShift(0.35f))) {
            append(verse.numberLabel)
        }
        append("\u00A0")
        val notes = marks.footnotes[verse.id].orEmpty()
        if (notes.isEmpty()) {
            withStyle(marks.style(verse.id, colors)) { append(verse.text) }
        } else {
            // Footnote markers, small letters in the accent colour, between the
            // verse's characters but never part of its text.
            var start = 0
            for (note in notes.sortedBy { it.offset }) {
                val at = note.offset.coerceIn(start, verse.text.length)
                withStyle(marks.style(verse.id, colors)) { append(verse.text.substring(start, at)) }
                pushStringAnnotation(tag = NOTE_TAG, annotation = FOOTNOTE_PREFIX + note.index)
                withStyle(SpanStyle(color = colors.accent, fontSize = 0.55.em, fontWeight = FontWeight.SemiBold, baselineShift = BaselineShift(0.38f))) { append(note.label) }
                pop()
                start = at
            }
            withStyle(marks.style(verse.id, colors)) { append(verse.text.substring(start)) }
        }
        pop()
        marks.notes[verse.id]?.let { noteId ->
            // The note's mark: apart from the verse, never part of its words.
            append("\u2009")
            pushStringAnnotation(tag = NOTE_TAG, annotation = noteId)
            withStyle(SpanStyle(color = colors.accent, fontSize = 0.75.em)) { append(NOTE_MARK) }
            pop()
        }
    }
}

internal const val NOTE_TAG = "note"

/** A footnote marker's annotation: the prefix, then the note's place in the chapter. */
internal const val FOOTNOTE_PREFIX = "footnote:"

/** One footnote marker in a verse. */
internal data class FootnoteMark(val offset: Int, val index: Int, val label: String)

/** The chapter's footnotes by verse, lettered a, b, c… through the chapter. */
internal fun footnoteMarks(chapter: Chapter?): Map<VerseId, List<FootnoteMark>> =
    chapter?.footnotes.orEmpty().mapIndexed { index, note -> note.verse to FootnoteMark(note.offset, index, com.genesis.core.domain.bible.BibleSearchForm.footnoteLabel(index)) }
        .groupBy({ it.first }, { it.second })
private const val NOTE_MARK = "\u270E"

/** The highlights and the selection, drawn as styles over the verbatim words. */
internal data class VerseMarks(
    val highlights: Map<VerseId, HighlightColor> = emptyMap(),
    val selection: Set<VerseId> = emptySet(),
    /** Verses followed by a note's mark, with the note's id. */
    val notes: Map<VerseId, String> = emptyMap(),
    /** The verse being read aloud, while Follow Along is on. */
    val playing: VerseId? = null,
    /** The translation's footnote markers. */
    val footnotes: Map<VerseId, List<FootnoteMark>> = emptyMap(),
) {
    fun style(verse: VerseId, colors: ReaderColors): SpanStyle {
        val highlight = highlights[verse]
        val selected = verse in selection
        val background = when {
            verse == playing -> colors.accent.copy(alpha = 0.22f)
            highlight != null -> Color(0xFF000000 or highlight.hex.toLong()).copy(alpha = highlight.alpha(colors.isDark))
            selected -> colors.accent.copy(alpha = 0.14f)
            else -> Color.Unspecified
        }
        return SpanStyle(
            background = background,
            textDecoration = if (selected) TextDecoration.Underline else null,
        )
    }
}

internal const val VERSE_TAG = "verse"

/**
 * The whole chapter as one text for paged reading: headings in the
 * semibold face, poetry indented, and a short gap between paragraphs. Every
 * indent is the same on every line, so a page that starts mid-paragraph
 * looks the same as the page before it.
 */
internal fun chapterText(chapter: Chapter, colors: ReaderColors, marks: VerseMarks): AnnotatedString = buildAnnotatedString {
    val gap = ParagraphStyle(lineHeight = 0.6.em)
    appendChapter(chapter, colors, marks, gap)
    // A licensed Bible's notice, as its licence requires: small and apart from the text.
    if (chapter.translation.showsLicenseUnderChapters) {
        withStyle(gap) { append("\u200B") }
        withStyle(ParagraphStyle()) {
            val url = chapter.translation.publisherUrl
            val style = SpanStyle(color = colors.secondaryText, fontSize = 0.62.em, textDecoration = if (url != null) TextDecoration.Underline else null)
            if (url != null) pushStringAnnotation(NOTE_TAG, PUBLISHER_PREFIX + url)
            withStyle(style) { append(chapter.translation.license) }
            if (url != null) pop()
        }
    }
}

/** On a licensed Bible's notice: the publisher's site, opened by a tap. */
internal const val PUBLISHER_PREFIX = "publisher:"

private fun AnnotatedString.Builder.appendChapter(chapter: Chapter, colors: ReaderColors, marks: VerseMarks, gap: ParagraphStyle) {
    blocks(chapter).forEachIndexed { index, block ->
        if (index > 0) withStyle(gap) { append("​") }
        when (block) {
            is Block.Heading -> withStyle(ParagraphStyle()) {
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(block.text) }
            }
            is Block.Prose -> {
                val indent = if (block.verses.firstOrNull()?.isPoetry == true) 1.2.em else 0.em
                // Left to right even where a verse opens with a Hebrew letter (Psalm 119 in the KJV).
                val direction = if (ScriptureDirection.isRightToLeft(chapter.translation.language)) TextDirection.Rtl else TextDirection.Ltr
                withStyle(ParagraphStyle(textIndent = TextIndent(firstLine = indent, restLine = indent), textDirection = direction)) {
                    appendVerses(block.verses, colors, marks)
                }
            }
        }
    }
}

/** A run of verses shown together: a paragraph, a poetry block, or a heading. */
internal sealed interface Block {
    data class Heading(val text: String) : Block
    data class Prose(val verses: List<Verse>) : Block
}

internal fun blocks(chapter: Chapter): List<Block> {
    val headings = chapter.headings.groupBy { it.beforeVerse }
    val result = mutableListOf<Block>()
    var current = mutableListOf<Verse>()
    fun flush() {
        if (current.isNotEmpty()) result += Block.Prose(current)
        current = mutableListOf()
    }
    for (verse in chapter.verses) {
        val heading = headings[verse.number]
        if (heading != null) {
            flush()
            heading.forEach { result += Block.Heading(it.text) }
        }
        val previous = current.lastOrNull()
        if (verse.startsParagraph || verse.isPoetry || (previous != null && previous.isPoetry)) flush()
        current += verse
    }
    flush()
    return result
}
