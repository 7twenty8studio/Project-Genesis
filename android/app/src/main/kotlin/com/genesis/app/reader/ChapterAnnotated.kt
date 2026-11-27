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

/**
 * Verses run on with small raised numbers, as in a printed Bible. The words
 * are exactly as stored: only their style changes. Each verse keeps its id as
 * an annotation, ready for taps, highlights and selection.
 */
internal fun AnnotatedString.Builder.appendVerses(verses: List<Verse>, colors: ReaderColors) {
    val poetry = verses.firstOrNull()?.isPoetry == true
    verses.forEachIndexed { index, verse ->
        if (index > 0) append(if (poetry) "\n" else " ")
        withStyle(SpanStyle(color = colors.accent, fontSize = 0.6.em, fontWeight = FontWeight.Medium, baselineShift = BaselineShift(0.35f))) {
            append(verse.number.toString())
        }
        append(" ")
        pushStringAnnotation(tag = VERSE_TAG, annotation = verse.id.rawValue.toString())
        append(verse.text)
        pop()
    }
}

internal const val VERSE_TAG = "verse"

/**
 * The whole chapter as one text for paged reading: headings in the
 * semibold face, poetry indented, and a short gap between paragraphs. Every
 * indent is the same on every line, so a page that starts mid-paragraph
 * looks the same as the page before it.
 */
internal fun chapterText(chapter: Chapter, colors: ReaderColors): AnnotatedString = buildAnnotatedString {
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
                    appendVerses(block.verses, colors)
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
