package com.genesis.app.reader

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.size
import androidx.compose.material3.IconButton
import androidx.compose.ui.graphics.Path
import com.genesis.core.domain.study.Note
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.BottomAppBar
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.genesis.app.R
import com.genesis.core.bible.Chapter
import com.genesis.core.design.LocalReaderColors
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.core.design.scriptureStyle
import com.genesis.core.domain.reader.ReaderPreferences
import com.genesis.core.domain.reader.ReadingMode
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.study.HighlightColor
import com.genesis.app.settings.LocalRecentColors

@Composable
fun ReaderRoute(
    onChangeSettings: ((ReaderPreferences) -> ReaderPreferences) -> Unit,
    onSearchClick: () -> Unit,
    viewModel: ReaderViewModel = viewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    LaunchedEffect(state.chapter?.id, state.focus) { viewModel.recordPosition() }
    ReaderScreen(
        state = state,
        onSearchClick = onSearchClick,
        onChangeSettings = onChangeSettings,
        onOpen = viewModel::open,
        onChooseBible = viewModel::choose,
        onNext = { viewModel.next() },
        onPrevious = { viewModel.previous() },
        onPreviousAtEnd = { viewModel.previous(atEnd = true) },
        selection = SelectionActions(
            onVerseTap = viewModel::toggle,
            onHighlight = viewModel::highlight,
            onRemoveHighlight = viewModel::removeHighlight,
            onDone = viewModel::clearSelection,
            onBookmark = viewModel::toggleBookmark,
            onNote = viewModel::openNoteForSelection,
            onNoteTap = viewModel::openNote,
        ),
    )
}



/** What the reader does with tapped verses. */
data class SelectionActions(
    val onVerseTap: (VerseId) -> Unit = {},
    val onHighlight: (HighlightColor) -> Unit = {},
    val onRemoveHighlight: () -> Unit = {},
    val onDone: () -> Unit = {},
    val onBookmark: () -> Unit = {},
    val onNote: () -> Unit = {},
    val onNoteTap: (String) -> Unit = {},
)

/**
 * The reader: one chapter, page by page or scrolling, verse numbers in the
 * theme's accent, the translation's headings, poetry line by line and the
 * licence under the chapter when it isn't public domain. Tapping verses
 * selects them; the selection bar highlights, copies and shares.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderScreen(
    state: ReaderUiState,
    onSearchClick: () -> Unit = {},
    onChangeSettings: ((ReaderPreferences) -> ReaderPreferences) -> Unit,
    onOpen: (com.genesis.core.domain.bible.ChapterId) -> Unit,
    onChooseBible: (com.genesis.core.bible.BundledBible) -> Unit,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
    onPreviousAtEnd: () -> Unit = onPrevious,
    selection: SelectionActions = SelectionActions(),
) {
    var picking by rememberSaveable { mutableStateOf(false) }
    var bibleMenu by remember { mutableStateOf(false) }
    var settingsOpen by rememberSaveable { mutableStateOf(false) }
    val language = state.chapter?.translation?.language ?: "en"
    val colors = LocalReaderColors.current

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    TextButton(onClick = { picking = true }) {
                        Text(
                            state.chapterId.description(language),
                            style = MaterialTheme.typography.titleMedium,
                            color = colors.text,
                        )
                    }
                },
                navigationIcon = {
                    val readingSettings = stringResource(R.string.reading_settings)
                    TextButton(
                        onClick = { settingsOpen = true },
                        modifier = Modifier.semantics { contentDescription = readingSettings },
                    ) {
                        Text("Aa", color = colors.accent, style = MaterialTheme.typography.titleMedium)
                    }
                },
                actions = {
                    val searchLabel = stringResource(R.string.search)
                    IconButton(
                        onClick = onSearchClick,
                        modifier = Modifier.semantics { contentDescription = searchLabel },
                    ) { Magnifier(colors.accent) }
                    if (state.isChapterBookmarked) {
                        val removeBookmark = stringResource(R.string.remove_bookmark)
                        IconButton(
                            onClick = selection.onBookmark,
                            modifier = Modifier.semantics { contentDescription = removeBookmark },
                        ) { Ribbon(colors.accent) }
                    }
                    Box {
                        val chooseTranslation = stringResource(R.string.choose_translation)
                        TextButton(
                            onClick = { bibleMenu = true },
                            modifier = Modifier.semantics { contentDescription = chooseTranslation },
                        ) {
                            Text(state.chapter?.translation?.abbreviation ?: state.bible.id, color = colors.accent)
                        }
                        DropdownMenu(expanded = bibleMenu, onDismissRequest = { bibleMenu = false }) {
                            for ((bible, translation) in state.translations) {
                                DropdownMenuItem(
                                    text = { Text("${translation.abbreviation} · ${translation.name}") },
                                    onClick = {
                                        bibleMenu = false
                                        onChooseBible(bible)
                                    },
                                )
                            }
                        }
                    }
                },
            )
        },
        bottomBar = {
            if (state.selection.isNotEmpty()) {
                val recent by LocalRecentColors.current
                SelectionBar(
                    reference = state.selectionReference,
                    shareText = state.shareText,
                    colorsInOrder = (recent + HighlightColor.entries).distinct(),
                    anyHighlighted = state.selection.any { it in state.highlights },
                    isBookmarked = state.isChapterBookmarked,
                    onHighlight = selection.onHighlight,
                    onRemoveHighlight = selection.onRemoveHighlight,
                    onBookmark = selection.onBookmark,
                    onNote = selection.onNote,
                    onDone = selection.onDone,
                )
            } else BottomAppBar(containerColor = colors.background) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    TextButton(onClick = onPrevious, enabled = state.chapterId.previous != null) {
                        Text("‹  " + stringResource(R.string.previous_chapter))
                    }
                    TextButton(onClick = onNext, enabled = state.chapterId.next != null) {
                        Text(stringResource(R.string.next_chapter) + "  ›")
                    }
                }
            }
        },
        containerColor = colors.background,
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
            val preferences = LocalReaderPreferences.current
            val notedVerses = state.notedVerses
            val marks = remember(state.highlights, state.selection, notedVerses) { VerseMarks(state.highlights, state.selection, notedVerses) }
            val scripture = scriptureStyle(preferences, Entitlements.isPremium)
            when {
                state.chapter != null && preferences.readingMode == ReadingMode.PAGE -> key(state.chapter.id, state.chapter.translation.id) {
                    val text = remember(state.chapter, colors, marks) { chapterText(state.chapter, colors, marks) }
                    PagedChapter(
                        chapter = state.chapter,
                        text = text,
                        style = scripture,
                        runningHead = state.chapterId.description(language).uppercase(),
                        openAtEnd = state.openAtEnd,
                        focus = state.focus,
                        onNextChapter = onNext,
                        onPreviousChapter = onPreviousAtEnd,
                        onVerseTap = selection.onVerseTap,
                        onNoteTap = selection.onNoteTap,
                    )
                }
                state.chapter != null -> ChapterText(state.chapter, scripture, marks, state.focus, selection.onVerseTap, selection.onNoteTap)
                state.failed -> Text(
                    stringResource(R.string.chapter_load_failed),
                    color = colors.secondaryText,
                    modifier = Modifier.padding(24.dp),
                )
            }
        }
    }

    if (settingsOpen) {
        ReaderSettingsSheet(
            preferences = LocalReaderPreferences.current,
            onChange = onChangeSettings,
            onDismiss = { settingsOpen = false },
        )
    }

    if (picking) {
        BookPicker(
            language = language,
            current = state.chapterId,
            onPick = {
                picking = false
                onOpen(it)
            },
            onDismiss = { picking = false },
        )
    }
}

@Composable
private fun ChapterText(chapter: Chapter, scripture: TextStyle, marks: VerseMarks, focus: ReaderFocus?, onVerseTap: (VerseId) -> Unit, onNoteTap: (String) -> Unit) {
    val colors = LocalReaderColors.current
    val listState = rememberLazyListState()
    val blocks = remember(chapter) { blocks(chapter) }
    LaunchedEffect(chapter.id, chapter.translation.id, focus) {
        // The chapter's number is item 0; a verse from search scrolls to its block.
        val block = focus?.takeIf { it.verse.chapterId == chapter.id }?.let { focus ->
            blocks.indexOfFirst { it is Block.Prose && it.verses.any { verse -> verse.id == focus.verse } }
        }
        listState.scrollToItem(if (block != null && block >= 0) block + 1 else 0)
    }

    LazyColumn(
        state = listState,
        modifier = Modifier.widthIn(max = 680.dp).fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 24.dp, vertical = 16.dp),
    ) {
        item {
            Text(
                stringResource(R.string.chapter_number, chapter.id.chapter),
                style = MaterialTheme.typography.titleLarge,
                color = colors.secondaryText,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp).semantics { heading() },
            )
        }
        items(blocks) { block ->
            when (block) {
                is Block.Heading -> Text(
                    block.text,
                    style = scripture.copy(fontWeight = FontWeight.SemiBold),
                    color = colors.text,
                    modifier = Modifier.padding(top = 12.dp, bottom = 6.dp).semantics { heading() },
                )
                is Block.Prose -> VerseParagraph(block.verses, scripture, marks, onVerseTap, onNoteTap)
            }
        }
        if (chapter.translation.showsLicenseUnderChapters) {
            item {
                Text(
                    chapter.translation.license,
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.secondaryText,
                    modifier = Modifier.padding(top = 24.dp),
                )
            }
        }
    }
}

/** The bookmark ribbon shown while the chapter is bookmarked. */
@Composable
private fun Ribbon(color: androidx.compose.ui.graphics.Color) {
    Canvas(Modifier.size(width = 14.dp, height = 20.dp)) {
        val path = Path().apply {
            moveTo(0f, 0f)
            lineTo(size.width, 0f)
            lineTo(size.width, size.height)
            lineTo(size.width / 2, size.height * 0.72f)
            lineTo(0f, size.height)
            close()
        }
        drawPath(path, color)
    }
}

/** The search button's magnifying glass. */
@Composable
internal fun Magnifier(color: androidx.compose.ui.graphics.Color, iconSize: androidx.compose.ui.unit.Dp = 20.dp) {
    Canvas(Modifier.size(iconSize)) {
        val stroke = size.minDimension * 0.11f
        val radius = size.minDimension * 0.32f
        val center = androidx.compose.ui.geometry.Offset(size.width * 0.42f, size.height * 0.42f)
        drawCircle(color, radius, center, style = androidx.compose.ui.graphics.drawscope.Stroke(stroke))
        val start = androidx.compose.ui.geometry.Offset(center.x + radius * 0.72f, center.y + radius * 0.72f)
        drawLine(color, start, androidx.compose.ui.geometry.Offset(size.width * 0.92f, size.height * 0.92f), stroke, androidx.compose.ui.graphics.StrokeCap.Round)
    }
}
