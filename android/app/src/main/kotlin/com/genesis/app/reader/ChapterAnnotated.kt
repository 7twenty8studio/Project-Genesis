package com.genesis.app.reader

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ParagraphStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextIndent
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
            append(verse.number.toString())
        }
        append("\u00A0")
        withStyle(marks.style(verse.id, colors)) { append(verse.text) }
        pop()
    }
}

/** The highlights and the selection, drawn as styles over the verbatim words. */
internal data class VerseMarks(
    val highlights: Map<VerseId, HighlightColor> = emptyMap(),
    val selection: Set<VerseId> = emptySet(),
) {
    fun style(verse: VerseId, colors: ReaderColors): SpanStyle {
        val highlight = highlights[verse]
        val selected = verse in selection
        val background = when {
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
    blocks(chapter).forEachIndexed { index, block ->
        if (index > 0) withStyle(gap) { append("​") }
        when (block) {
            is Block.Heading -> withStyle(ParagraphStyle()) {
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(block.text) }
            }
            is Block.Prose -> {
                val indent = if (block.verses.firstOrNull()?.isPoetry == true) 1.2.em else 0.em
                withStyle(ParagraphStyle(textIndent = TextIndent(firstLine = indent, restLine = indent))) {
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
