package com.genesis.app.reader

import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.genesis.app.R
import com.genesis.core.bible.Chapter
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.ScriptureText

@Composable
fun ReaderRoute(viewModel: ReaderViewModel = viewModel()) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    ReaderScreen(
        state = state,
        onOpen = viewModel::open,
        onChooseBible = viewModel::choose,
        onNext = { viewModel.next() },
        onPrevious = { viewModel.previous() },
    )
}

/**
 * The first Android reader: one chapter, scrolling, verse numbers in the
 * theme's accent, the translation's headings, poetry line by line and the
 * licence under the chapter when it isn't public domain. Paged reading,
 * page turns, highlights and selection follow in phase 2.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderScreen(
    state: ReaderUiState,
    onOpen: (com.genesis.core.domain.bible.ChapterId) -> Unit,
    onChooseBible: (com.genesis.core.bible.BundledBible) -> Unit,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
) {
    var picking by rememberSaveable { mutableStateOf(false) }
    var bibleMenu by remember { mutableStateOf(false) }
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
                actions = {
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
            BottomAppBar(containerColor = colors.background) {
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
            when {
                state.chapter != null -> ChapterText(state.chapter)
                state.failed -> Text(
                    stringResource(R.string.chapter_load_failed),
                    color = colors.secondaryText,
                    modifier = Modifier.padding(24.dp),
                )
            }
        }
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

/** A run of verses shown together: a paragraph, a poetry block, or a heading. */
private sealed interface Block {
    data class Heading(val text: String) : Block
    data class Prose(val verses: List<com.genesis.core.bible.Verse>) : Block
}

private fun blocks(chapter: Chapter): List<Block> {
    val headings = chapter.headings.groupBy { it.beforeVerse }
    val result = mutableListOf<Block>()
    var current = mutableListOf<com.genesis.core.bible.Verse>()
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

@Composable
private fun ChapterText(chapter: Chapter) {
    val colors = LocalReaderColors.current
    val listState = rememberLazyListState()
    LaunchedEffect(chapter.id, chapter.translation.id) { listState.scrollToItem(0) }
    val blocks = remember(chapter) { blocks(chapter) }

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
                    style = ScriptureText.copy(fontWeight = FontWeight.SemiBold),
                    color = colors.text,
                    modifier = Modifier.padding(top = 12.dp, bottom = 6.dp).semantics { heading() },
                )
                is Block.Prose -> VerseParagraph(block.verses)
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
