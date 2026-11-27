package com.genesis.app.reader

import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.Column
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
import com.genesis.app.original.OriginalParallelScreen
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
import android.os.SystemClock
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.genesis.app.VerselyApplication
import com.genesis.app.audio.HeadphonesIcon
import com.genesis.app.audio.Listening
import com.genesis.app.audio.ListeningBar
import com.genesis.app.audio.ListeningState

@Composable
fun ReaderRoute(
    onChangeSettings: ((ReaderPreferences) -> ReaderPreferences) -> Unit,
    onSearchClick: () -> Unit,
    onMoreBibles: () -> Unit = {},
    viewModel: ReaderViewModel = viewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    LaunchedEffect(state.chapter?.id, state.focus) { viewModel.recordPosition() }
    ReadingTimer()
    val app = LocalContext.current.applicationContext as VerselyApplication
    val listening by app.listening.state.collectAsStateWithLifecycle()
    val listeningPreferences by app.listening.settings.state.collectAsStateWithLifecycle()
    val following = listeningPreferences.followsAlong && listening.isActive && listening.bible == state.bible
    // Follow Along: when listening moves on to the next chapter, the reader goes with it.
    var lastListened by remember { mutableStateOf<com.genesis.core.domain.bible.ChapterId?>(null) }
    LaunchedEffect(listening.chapter, following) {
        val now = listening.chapter
        val before = lastListened
        lastListened = now
        if (following && now != null && before != null && now != before && state.chapterId == before) viewModel.open(now)
    }
    var footnote by remember { mutableStateOf<com.genesis.core.bible.Footnote?>(null) }
    val uriHandler = androidx.compose.ui.platform.LocalUriHandler.current
    // A YouVersion chapter opened online after its Cache-Control lifetime is fetched again.
    LaunchedEffect(state.chapter?.id, state.bible) { viewModel.refreshIfStale() }
    // Once: a YouVersion Bible is free, isn't read aloud, and Premium tools use a free Bible beside it.
    val youVersionNote = remember { app.getSharedPreferences("reader", android.content.Context.MODE_PRIVATE) }
    var showsYouVersionNote by remember { mutableStateOf(false) }
    LaunchedEffect(state.chapter?.translation?.isYouVersion) {
        if (state.chapter?.translation?.isYouVersion == true && !youVersionNote.getBoolean("youVersion.noteShown", false)) showsYouVersionNote = true
    }
    androidx.compose.foundation.layout.Box(Modifier.fillMaxSize()) {
    ReaderScreen(
        state = state,
        viewModel = viewModel,
        listening = ReaderListening(
            state = listening,
            speed = listeningPreferences.speed,
            controls = app.listening,
            playing = listening.verse.takeIf { following && listening.chapter == state.chapterId },
        ),
        onSearchClick = onSearchClick,
        onMoreBibles = onMoreBibles,
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
            onNoteTap = { tag ->
                when {
                    tag.startsWith(FOOTNOTE_PREFIX) -> footnote = tag.removePrefix(FOOTNOTE_PREFIX).toIntOrNull()?.let { state.chapter?.footnotes?.getOrNull(it) }
                    tag.startsWith(PUBLISHER_PREFIX) -> uriHandler.openUri(tag.removePrefix(PUBLISHER_PREFIX))
                    else -> viewModel.openNote(tag)
                }
            },
            onCrossReferences = viewModel::openCrossReferences,
            onMemorise = viewModel::memoriseSelection,
            onWordStudy = viewModel::openWordStudy,
            onStudy = viewModel::openStudy,
        ),
    )
    footnote?.let { note ->
        FootnoteSheet(note, state.chapter?.translation) { footnote = null }
    }
    if (showsYouVersionNote) {
        val translation = state.chapter?.translation
        androidx.compose.material3.AlertDialog(
            onDismissRequest = {},
            title = { Text(stringResource(R.string.about_this_bible)) },
            text = { Text(stringResource(R.string.youversion_reader_note, translation?.abbreviation.orEmpty(), viewModel.premiumToolsBibleName())) },
            confirmButton = {
                TextButton(onClick = {
                    youVersionNote.edit().putBoolean("youVersion.noteShown", true).apply()
                    showsYouVersionNote = false
                }) { Text(stringResource(R.string.ok)) }
            },
        )
    }
    state.wordStudyVerse?.let { verse ->
        com.genesis.app.original.VerseStudyScreen(verse, viewModel, onDone = viewModel::closeWordStudy)
    }
    state.studyVerse?.let { verse ->
        com.genesis.app.studylibrary.StudyFlow(
            com.genesis.app.studylibrary.StudyPlace.VerseResources(verse),
            viewModel,
            onDone = viewModel::closeStudy,
            onOpenVerse = { viewModel.closeStudy(); viewModel.openVerse(it) },
        )
    }
    }
}



/** Listening, as the reader shows it: the bar, and the verse to mark and follow. */
data class ReaderListening(
    val state: ListeningState,
    val speed: Double,
    val controls: Listening,
    val playing: VerseId?,
)

/** What the reader does with tapped verses. */
data class SelectionActions(
    val onVerseTap: (VerseId) -> Unit = {},
    val onHighlight: (HighlightColor) -> Unit = {},
    val onRemoveHighlight: () -> Unit = {},
    val onDone: () -> Unit = {},
    val onBookmark: () -> Unit = {},
    val onNote: () -> Unit = {},
    val onNoteTap: (String) -> Unit = {},
    val onCrossReferences: () -> Unit = {},
    val onMemorise: () -> Unit = {},
    val onWordStudy: () -> Unit = {},
    val onStudy: () -> Unit = {},
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
    onChooseBible: (com.genesis.core.bible.InstalledBible) -> Unit,
    onMoreBibles: () -> Unit = {},
    onNext: () -> Unit,
    onPrevious: () -> Unit,
    onPreviousAtEnd: () -> Unit = onPrevious,
    selection: SelectionActions = SelectionActions(),
    listening: ReaderListening? = null,
    viewModel: ReaderViewModel? = null,
) {
    var originalWord by remember { mutableStateOf<com.genesis.core.domain.original.OriginalWord?>(null) }
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
                    if (listening != null) {
                        val listen = stringResource(R.string.listen_to_chapter)
                        IconButton(
                            onClick = {
                                val current = listening.state
                                if (current.isActive && current.chapter == state.chapterId && current.bible == state.bible) {
                                    listening.controls.toggle()
                                } else {
                                    listening.controls.play(state.bible, state.chapterId)
                                }
                            },
                            modifier = Modifier.semantics { contentDescription = listen },
                        ) { HeadphonesIcon(colors.accent) }
                    }
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
                            val byLanguage = state.translations.sortedWith(compareBy({ it.second.language.substringBefore('-') != (state.chapter?.translation?.language ?: "en").substringBefore('-') }, { it.second.language }))
                            for ((bible, translation) in byLanguage) {
                                DropdownMenuItem(
                                    text = { Text("${translation.abbreviation} · ${translation.name}") },
                                    onClick = {
                                        bibleMenu = false
                                        onChooseBible(bible)
                                    },
                                )
                            }
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.more_bibles), color = colors.accent) },
                                onClick = {
                                    bibleMenu = false
                                    onMoreBibles()
                                },
                            )
                            if (viewModel != null) {
                                androidx.compose.material3.HorizontalDivider(color = colors.separator)
                                DropdownMenuItem(
                                    text = { Text((if (state.showsOriginal) "✓ " else "") + stringResource(R.string.original_hebrew_greek)) },
                                    onClick = {
                                        bibleMenu = false
                                        viewModel.setOriginal(!state.showsOriginal)
                                    },
                                )
                            }
                        }
                    }
                },
            )
        },
        bottomBar = {
          Column {
            if (listening != null && listening.state.isActive && state.selection.isEmpty()) {
                ListeningBar(
                    state = listening.state,
                    speed = listening.speed,
                    listening = listening.controls,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                )
            }
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
                    onCrossReferences = selection.onCrossReferences,
                    onMemorise = selection.onMemorise,
                    onWordStudy = selection.onWordStudy,
                    onStudy = selection.onStudy,
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
          }
        },
        containerColor = colors.background,
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
            val preferences = LocalReaderPreferences.current
            val notedVerses = state.notedVerses
            val playing = listening?.playing
            val marks = remember(state.highlights, state.selection, notedVerses, playing, state.chapter) { VerseMarks(state.highlights, state.selection, notedVerses, playing, footnoteMarks(state.chapter)) }
            val scripture = scriptureStyle(preferences, Entitlements.isPremium)
            // Forest, Ocean and Hearth: the scene behind clear pages.
            val scene = com.genesis.core.domain.theme.ThemeScene.of(preferences.theme)
                ?.takeIf { state.chapter != null && !state.showsOriginal }
            if (scene != null) key(scene) { com.genesis.app.reader.backdrop.ThemeSceneView(scene, animates = preferences.seasonalEffects) }
            when {
                state.showsOriginal && viewModel != null -> OriginalParallelScreen(
                    viewModel = viewModel,
                    chapter = state.chapterId,
                    bibleId = state.bible.id,
                    fontSize = preferences.fontSize,
                    onNext = onNext,
                    onWord = { originalWord = it },
                )
                state.chapter != null && preferences.readingMode == ReadingMode.PAGE -> key(state.chapter.id, state.chapter.translation.id) {
                    val text = remember(state.chapter, colors, marks) { chapterText(state.chapter, colors, marks) }
                    PagedChapter(
                        chapter = state.chapter,
                        text = text,
                        style = scripture,
                        runningHead = state.chapterId.description(language).uppercase(),
                        openAtEnd = state.openAtEnd,
                        focus = state.focus,
                        follow = playing,
                        onNextChapter = onNext,
                        onPreviousChapter = onPreviousAtEnd,
                        onVerseTap = selection.onVerseTap,
                        onNoteTap = selection.onNoteTap,
                        scene = scene,
                    )
                }
                state.chapter != null -> ChapterText(state.chapter, scripture, marks, state.focus, playing, selection.onVerseTap, selection.onNoteTap)
                state.failed -> Text(
                    stringResource(R.string.chapter_load_failed),
                    color = colors.secondaryText,
                    modifier = Modifier.padding(24.dp),
                )
            }
            // Starlight's sky lies over the page, in the margins and the band at the top only.
            val shownTheme = preferences.theme.resolved(androidx.compose.foundation.isSystemInDarkTheme())
            val season = shownTheme.season
            if (season != null && preferences.seasonalEffects && state.chapter != null && !state.showsOriginal) {
                key(season) { com.genesis.app.reader.backdrop.SeasonalEffect(season) }
            }
            if (shownTheme.hasStars && state.chapter != null && !state.showsOriginal) {
                val paged = preferences.readingMode == ReadingMode.PAGE
                com.genesis.app.reader.backdrop.StarlightSky(
                    textInsets = if (paged) com.genesis.app.reader.backdrop.TextInsets(28.dp, 28.dp, 28.dp, 28.dp)
                    else com.genesis.app.reader.backdrop.TextInsets(24.dp, 0.dp, 24.dp, 0.dp),
                    skyBand = if (paged) 28.dp else 0.dp,
                )
            }
        }
    }

    originalWord?.let { word ->
        if (viewModel != null) com.genesis.app.original.OriginalWordSheet(word, viewModel) { originalWord = null }
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
private fun ChapterText(chapter: Chapter, scripture: TextStyle, marks: VerseMarks, focus: ReaderFocus?, follow: VerseId?, onVerseTap: (VerseId) -> Unit, onNoteTap: (String) -> Unit) {
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
    // Follow Along: keep the verse being read on screen, moving only when it's about to leave.
    LaunchedEffect(follow) {
        val verse = follow?.takeIf { it.chapterId == chapter.id } ?: return@LaunchedEffect
        val block = blocks.indexOfFirst { it is Block.Prose && it.verses.any { v -> v.id == verse } }.takeIf { it >= 0 } ?: return@LaunchedEffect
        val item = block + 1
        val visible = listState.layoutInfo.visibleItemsInfo
        val shown = visible.firstOrNull { it.index == item }
        val bottom = listState.layoutInfo.viewportEndOffset
        if (shown == null || shown.offset + shown.size > bottom && shown.offset > bottom / 3) listState.animateScrollToItem(item)
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
                is Block.Prose -> VerseParagraph(
                    block.verses,
                    // Left to right even where a verse opens with a Hebrew letter (Psalm 119 in the KJV).
                    scripture.copy(textDirection = if (com.genesis.core.domain.bible.ScriptureDirection.isRightToLeft(chapter.translation.language)) androidx.compose.ui.text.style.TextDirection.Rtl else androidx.compose.ui.text.style.TextDirection.Ltr),
                    marks,
                    onVerseTap,
                    onNoteTap,
                )
            }
        }
        if (chapter.translation.showsLicenseUnderChapters) {
            item {
                // The publisher's licence asks for a one-step link to its site wherever its text is shown.
                val url = chapter.translation.publisherUrl
                val uriHandler = androidx.compose.ui.platform.LocalUriHandler.current
                Text(
                    chapter.translation.license,
                    style = MaterialTheme.typography.bodyMedium.copy(textDecoration = if (url != null) androidx.compose.ui.text.style.TextDecoration.Underline else null),
                    color = colors.secondaryText,
                    modifier = Modifier.padding(top = 24.dp).then(if (url != null) Modifier.clickable { uriHandler.openUri(url) } else Modifier),
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

/**
 * Counts the time the reader is on screen with the app in front, as iOS's
 * reading time: each session ends when the app leaves the foreground or the
 * reader closes, and adds at most 45 minutes.
 */
@Composable
private fun ReadingTimer() {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        var started: Long? = SystemClock.elapsedRealtime().takeIf { lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) }
        fun stop() {
            started?.let { app.progress.addReadingTime((SystemClock.elapsedRealtime() - it) / 1_000) }
            started = null
        }
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> if (started == null) started = SystemClock.elapsedRealtime()
                Lifecycle.Event.ON_PAUSE -> stop()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            stop()
        }
    }
}

/** A translation's footnote, as FootnoteSheet on iOS: the verse and Bible, then the note. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun FootnoteSheet(note: com.genesis.core.bible.Footnote, translation: com.genesis.core.bible.Translation?, onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    androidx.compose.material3.ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.background) {
        androidx.compose.foundation.layout.Column(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.footnote), style = MaterialTheme.typography.titleMedium, color = colors.text, modifier = Modifier.semantics { heading() })
            val language = translation?.language ?: "en"
            Text(
                com.genesis.core.domain.bible.ReferenceParser.describe(note.verse.rawValue, language = language) + (translation?.let { " · " + it.abbreviation } ?: ""),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = colors.accent,
            )
            androidx.compose.foundation.text.selection.SelectionContainer {
                Text(note.text, style = MaterialTheme.typography.bodyLarge, color = colors.text)
            }
        }
    }
}
