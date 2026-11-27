package com.genesis.app.reader

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.core.bible.Chapter
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.reader.PageSpread
import com.genesis.core.domain.reader.PageTurnStyle
import com.genesis.core.domain.reader.Pagination
import com.genesis.core.domain.reader.ReaderTap
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

/**
 * Page-by-page reading, the iOS default: the chapter is laid out once at the
 * page's width, cut into pages of whole lines (`Pagination`), and turned with
 * Page Curl or Slide. Past the last page the next chapter opens; past the
 * first, the previous chapter on its last page. A running head names the
 * chapter and each page shows its number. On a wide screen held sideways
 * two pages show side by side like an open book (`PageSpread`), and a
 * chapter starts on a left page.
 */
@Composable
internal fun PagedChapter(
    chapter: Chapter,
    text: AnnotatedString,
    style: TextStyle,
    runningHead: String,
    openAtEnd: Boolean,
    focus: ReaderFocus?,
    follow: VerseId? = null,
    onNextChapter: () -> Unit,
    onPreviousChapter: () -> Unit,
    onVerseTap: (VerseId) -> Unit,
    onNoteTap: (String) -> Unit = {},
    /** Forest, Ocean or Hearth behind the pages: clear pages, and room kept above its swells or glow. */
    scene: com.genesis.core.domain.theme.ThemeScene? = null,
    isSelecting: Boolean = false,
    /** The controls are out: the running head and page number make way for them. */
    hidesPageChrome: Boolean = false,
    onClearSelection: () -> Unit = {},
    onToggleControls: () -> Unit = {},
    margin: Dp = 28.dp,
    pageTurn: PageTurnStyle = PageTurnStyle.CURL,
    spreadEnabled: Boolean = false,
    leftHanded: Boolean = false,
    /** Each time a page turns (sound and haptic). */
    onPageTurned: () -> Unit = {},
    sidePanelShown: Boolean = false,
) {
    val colors = LocalReaderColors.current
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val spread = PageSpread.shows(spreadEnabled, maxWidth.value, maxHeight.value, sidePanelShown)
        val pageWidth = if (spread) maxWidth / 2 else maxWidth
        val head = 28.dp
        val foot = 28.dp
        val footRoom = scene?.let { com.genesis.app.reader.backdrop.sceneFootRoom(it, maxWidth.value, maxHeight.value, foot.value).dp } ?: 0.dp
        val widthPx = with(density) { (pageWidth - margin * 2).roundToPx() }.coerceAtLeast(1)
        val heightPx = with(density) { (maxHeight - head - foot - footRoom).toPx() }.coerceAtLeast(1f)

        val pages = remember(text, style, widthPx, heightPx, density, direction) {
            val layout = measurer.measure(text, style, constraints = Constraints(maxWidth = widthPx), density = density, layoutDirection = direction)
            val lines = 0 until layout.lineCount
            Pagination.pages(lines.map { layout.getLineTop(it) }, lines.map { layout.getLineBottom(it) }, heightPx).map { range ->
                val start = layout.getLineStart(range.first)
                val end = layout.getLineEnd(range.last)
                text.subSequence(start, end).trimmedForPage()
            }
        }
        // A sheet is one page, or two side by side; one blank sheet at each end stands for the chapters either side.
        val perSheet = if (spread) 2 else 1
        val sheets = (pages.size + perSheet - 1) / perSheet
        val count = sheets + 2
        fun sheetOf(focus: ReaderFocus?): Int? {
            val id = focus?.verse?.rawValue?.toString() ?: return null
            val index = pages.indexOfFirst { page -> page.getStringAnnotations(VERSE_TAG, 0, page.length).any { it.item == id } }
            return if (index >= 0) index / perSheet + 1 else null
        }
        val initial = sheetOf(focus) ?: if (openAtEnd) sheets else 1
        val scope = rememberCoroutineScope()
        // Page Curl needs opaque pages: over a scene the pages slide.
        val curls = pageTurn == PageTurnStyle.CURL && scene == null

        val totalWidth = with(density) { maxWidth.toPx() }
        val marginPx = with(density) { margin.toPx() }

        @Composable
        fun Sheet(index: Int, turn: (Boolean) -> Unit) {
            val background = if (scene != null) Color.Transparent else colors.background
            Box(
                Modifier
                    .fillMaxSize()
                    .background(background)
                    .pointerInput(isSelecting, totalWidth, leftHanded) { detectTapGestures { tap(it.x, null, totalWidth, marginPx, isSelecting, leftHanded, turn, onVerseTap, onClearSelection, onToggleControls) } },
            ) {
                if (index !in 1..sheets) return@Box
                Row(Modifier.fillMaxSize()) {
                    for (slot in 0 until perSheet) {
                        val pageIndex = (index - 1) * perSheet + slot
                        val offset = with(density) { (pageWidth * slot).toPx() }
                        Box(Modifier.width(pageWidth).fillMaxHeight()) {
                            pages.getOrNull(pageIndex)?.let { page ->
                                Page(
                                    page = page,
                                    number = pageIndex + 1,
                                    style = style,
                                    runningHead = runningHead,
                                    margin = margin,
                                    head = head,
                                    foot = foot,
                                    footRoom = footRoom,
                                    hidesPageChrome = hidesPageChrome,
                                    onVerseTap = onVerseTap,
                                    onNoteTap = onNoteTap,
                                    onTap = { verse, x -> tap(x + marginPx + offset, verse, totalWidth, marginPx, isSelecting, leftHanded, turn, onVerseTap, onClearSelection, onToggleControls) },
                                )
                            }
                        }
                        // The spine between the two pages.
                        if (spread && slot == 0) VerticalDivider(color = colors.separator.copy(alpha = 0.5f))
                    }
                }
            }
        }

        if (curls) {
            val curl = remember(pages.size, spread) { PageCurlState(initial) { count } }
            LaunchedEffect(focus) { sheetOf(focus)?.let { if (it != curl.current) curl.snapTo(it) } }
            LaunchedEffect(follow) {
                val sheet = follow?.let { sheetOf(ReaderFocus(it)) } ?: return@LaunchedEffect
                if (sheet != curl.current && !curl.isTurning) curl.turn(sheet > curl.current)
            }
            LaunchedEffect(curl) {
                snapshotFlow { curl.current }.distinctUntilChanged().drop(1).collect { sheet ->
                    when (sheet) {
                        0 -> if (chapter.id.previous != null) onPreviousChapter() else curl.snapTo(1)
                        count - 1 -> if (chapter.id.next != null) onNextChapter() else curl.snapTo(sheets)
                        else -> onPageTurned()
                    }
                }
            }
            val turn: (Boolean) -> Unit = { forward -> scope.launch { curl.turn(forward) } }
            PageCurl(curl, count, backColor = colors.surface) { index -> Sheet(index, turn) }
        } else {
            val pager = rememberPagerState(initialPage = initial) { count }
            LaunchedEffect(focus) { sheetOf(focus)?.let { if (it != pager.currentPage) pager.scrollToPage(it) } }
            // Follow Along: turn to the page with the verse being read aloud.
            LaunchedEffect(follow) {
                val sheet = follow?.let { sheetOf(ReaderFocus(it)) } ?: return@LaunchedEffect
                if (sheet != pager.currentPage && !pager.isScrollInProgress) pager.animateScrollToPage(sheet)
            }
            LaunchedEffect(pager, pages.size) {
                snapshotFlow { pager.settledPage }.distinctUntilChanged().drop(1).collect { sheet ->
                    when (sheet) {
                        0 -> if (chapter.id.previous != null) onPreviousChapter() else pager.scrollToPage(1)
                        count - 1 -> if (chapter.id.next != null) onNextChapter() else pager.scrollToPage(sheets)
                        else -> onPageTurned()
                    }
                }
            }
            val turn: (Boolean) -> Unit = { forward ->
                scope.launch { pager.animateScrollToPage((pager.currentPage + if (forward) 1 else -1).coerceIn(0, count - 1)) }
            }
            HorizontalPager(state = pager, modifier = Modifier.fillMaxSize(), key = { it }, reverseLayout = false) { index -> Sheet(index, turn) }
        }
    }
}

/** ReaderTap: the edges turn the page, verses select, anything else shows or hides the controls. */
private fun tap(
    x: Float,
    verse: VerseId?,
    width: Float,
    margin: Float,
    isSelecting: Boolean,
    leftHanded: Boolean,
    turn: (Boolean) -> Unit,
    onVerseTap: (VerseId) -> Unit,
    onClearSelection: () -> Unit,
    onToggleControls: () -> Unit,
) {
    when (val action = ReaderTap.action(x, width, margin, margin, verse, isSelecting, turnsPages = true, leftHanded = leftHanded)) {
        is ReaderTap.Action.TurnPage -> turn(action.forward)
        is ReaderTap.Action.ToggleSelection -> onVerseTap(action.verse)
        ReaderTap.Action.ClearSelection -> onClearSelection()
        ReaderTap.Action.ToggleControls -> onToggleControls()
    }
}

/** One page: the running head, the words, and the page number. */
@Composable
private fun Page(
    page: AnnotatedString,
    number: Int,
    style: TextStyle,
    runningHead: String,
    margin: Dp,
    head: Dp,
    foot: Dp,
    footRoom: Dp,
    hidesPageChrome: Boolean,
    onVerseTap: (VerseId) -> Unit,
    onNoteTap: (String) -> Unit,
    onTap: (VerseId?, Float) -> Unit,
) {
    val colors = LocalReaderColors.current
    val chromeAlpha by animateFloatAsState(if (hidesPageChrome) 0f else 1f, label = "pageChrome")
    Column(Modifier.fillMaxSize().padding(horizontal = margin)) {
        Text(
            runningHead,
            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 12.sp, letterSpacing = 0.6.sp),
            color = colors.secondaryText,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().height(head).padding(top = 6.dp).graphicsLayer { alpha = chromeAlpha },
        )
        VerseText(
            page,
            style = style,
            color = colors.text,
            onVerseTap = onVerseTap,
            onNoteTap = onNoteTap,
            onTap = onTap,
            modifier = Modifier.weight(1f).fillMaxWidth(),
        )
        if (footRoom > 0.dp) Spacer(Modifier.height(footRoom))
        Box(Modifier.fillMaxWidth().height(foot), contentAlignment = Alignment.Center) {
            Text("$number", style = MaterialTheme.typography.bodyMedium.copy(fontSize = 12.sp), color = colors.secondaryText, modifier = Modifier.graphicsLayer { alpha = chromeAlpha })
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
    while (start < end && (this[start] == '​' || this[start] == '\n')) start++
    while (end > start && this[end - 1] == '\n') end--
    return subSequence(start, end)
}
