package com.genesis.app.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.core.bible.Chapter
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.reader.Pagination
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop

/**
 * Page-by-page reading, the iOS default: the chapter is laid out once at the
 * page's width, cut into pages of whole lines (`Pagination`), and turned with
 * a swipe. Swiping past the last page opens the next chapter; past the first,
 * the previous chapter on its last page. A running head names the chapter
 * and each page shows its number. Page Curl and the two-page spread follow.
 */
@Composable
internal fun PagedChapter(
    chapter: Chapter,
    text: AnnotatedString,
    style: TextStyle,
    runningHead: String,
    openAtEnd: Boolean,
    focus: ReaderFocus?,
    follow: com.genesis.core.domain.bible.VerseId? = null,
    onNextChapter: () -> Unit,
    onPreviousChapter: () -> Unit,
    onVerseTap: (com.genesis.core.domain.bible.VerseId) -> Unit,
    onNoteTap: (String) -> Unit = {},
) {
    val colors = LocalReaderColors.current
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val horizontal = 28.dp
        val head = 28.dp
        val foot = 28.dp
        val widthPx = with(density) { (maxWidth - horizontal * 2).roundToPx() }.coerceAtLeast(1)
        val heightPx = with(density) { (maxHeight - head - foot).toPx() }.coerceAtLeast(1f)

        val pages = remember(text, style, widthPx, heightPx, density, direction) {
            val layout = measurer.measure(text, style, constraints = Constraints(maxWidth = widthPx), density = density, layoutDirection = direction)
            val lines = 0 until layout.lineCount
            Pagination.pages(lines.map { layout.getLineTop(it) }, lines.map { layout.getLineBottom(it) }, heightPx).map { range ->
                val start = layout.getLineStart(range.first)
                val end = layout.getLineEnd(range.last)
                text.subSequence(start, end).trimmedForPage()
            }
        }

        // One blank page at each end stands for the chapters either side.
        val pageCount = pages.size + 2
        fun pageOf(focus: ReaderFocus?): Int? {
            val id = focus?.verse?.rawValue?.toString() ?: return null
            val index = pages.indexOfFirst { page -> page.getStringAnnotations(VERSE_TAG, 0, page.length).any { it.item == id } }
            return if (index >= 0) index + 1 else null
        }
        val pager = rememberPagerState(initialPage = pageOf(focus) ?: if (openAtEnd) pages.size else 1) { pageCount }
        // A verse found by search in the chapter already open.
        LaunchedEffect(focus) { pageOf(focus)?.let { if (it != pager.currentPage) pager.scrollToPage(it) } }
        // Follow Along: turn to the page with the verse being read aloud.
        LaunchedEffect(follow) {
            val page = follow?.let { pageOf(ReaderFocus(it)) } ?: return@LaunchedEffect
            if (page != pager.currentPage && !pager.isScrollInProgress) pager.animateScrollToPage(page)
        }

        LaunchedEffect(pager, pages.size) {
            snapshotFlow { pager.settledPage }.distinctUntilChanged().drop(1).collect { page ->
                when (page) {
                    0 -> if (chapter.id.previous != null) onPreviousChapter() else pager.scrollToPage(1)
                    pageCount - 1 -> if (chapter.id.next != null) onNextChapter() else pager.scrollToPage(pages.size)
                }
            }
        }

        HorizontalPager(state = pager, modifier = Modifier.fillMaxSize(), key = { it }) { index ->
            Box(Modifier.fillMaxSize().background(colors.background)) {
                val page = pages.getOrNull(index - 1) ?: return@Box
                Column(Modifier.fillMaxSize().padding(horizontal = horizontal)) {
                    Text(
                        runningHead,
                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 12.sp, letterSpacing = 0.6.sp),
                        color = colors.secondaryText,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().height(head).padding(top = 6.dp),
                    )
                    VerseText(page, style = style, color = colors.text, onVerseTap = onVerseTap, onNoteTap = onNoteTap, modifier = Modifier.weight(1f).fillMaxWidth())
                    Box(Modifier.fillMaxWidth().height(foot), contentAlignment = Alignment.Center) {
                        Text("$index", style = MaterialTheme.typography.bodyMedium.copy(fontSize = 12.sp), color = colors.secondaryText)
                    }
                }
            }
        }
    }
}

/**
 * A page never starts with the small gap between paragraphs, and a page that
 * ends at a paragraph break doesn't show the break as an empty line.
 */
private fun AnnotatedString.trimmedForPage(): AnnotatedString {
    var start = 0
    var end = length
    // Paragraph styles break lines by themselves, so the gap is just its mark.
    while (start < end && (this[start] == '\u200B' || this[start] == '\n')) start++
    while (end > start && this[end - 1] == '\n') end--
    return subSequence(start, end)
}
