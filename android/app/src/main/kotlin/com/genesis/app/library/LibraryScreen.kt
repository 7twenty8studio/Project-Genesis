package com.genesis.app.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.reader.Magnifier
import com.genesis.app.reader.ReaderUiState
import com.genesis.core.bible.Verse
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId

/** Library's shelves, as on iOS (Sermons joins with Sermon Notes). */
enum class LibraryShelf { HIGHLIGHTS, NOTES, BOOKMARKS }

/**
 * Everything the person has saved, as LibraryView on iOS: highlights (newest
 * first), notes and bookmarks. Verses are shown verbatim from the Bible being
 * read; a tap opens the reader there.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(
    state: ReaderUiState,
    shelf: LibraryShelf,
    onShelf: (LibraryShelf) -> Unit,
    verses: suspend (Collection<VerseId>) -> Map<VerseId, Verse>,
    onRead: (VerseId) -> Unit,
    onOpenNote: (String) -> Unit,
    onNewNote: () -> Unit,
    onSearch: () -> Unit,
    onSermons: () -> Unit = {},
    onStudyLibrary: () -> Unit = {},
    onBibles: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val colors = LocalReaderColors.current
    val language = state.chapter?.translation?.language ?: "en"
    Column(modifier.statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.tab_library),
                style = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onBibles) { Text(stringResource(R.string.bibles), color = colors.accent) }
            TextButton(onClick = onStudyLibrary) { Text(stringResource(R.string.study_library), color = colors.accent) }
            TextButton(onClick = onSermons) { Text(stringResource(R.string.sermons), color = colors.accent) }
            val search = stringResource(R.string.search)
            IconButton(onClick = onSearch, modifier = Modifier.semantics { contentDescription = search }) {
                Magnifier(colors.accent, iconSize = 24.dp)
            }
        }
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp)) {
            LibraryShelf.entries.forEachIndexed { index, item ->
                SegmentedButton(
                    selected = shelf == item,
                    onClick = { onShelf(item) },
                    shape = SegmentedButtonDefaults.itemShape(index, LibraryShelf.entries.size),
                    colors = SegmentedButtonDefaults.colors(
                        activeContainerColor = colors.accent.copy(alpha = 0.16f),
                        activeContentColor = colors.text,
                        inactiveContainerColor = colors.background,
                        inactiveContentColor = colors.secondaryText,
                        activeBorderColor = colors.separator,
                        inactiveBorderColor = colors.separator,
                    ),
                    icon = {},
                ) { Text(stringResource(item.title)) }
            }
        }
        when (shelf) {
            LibraryShelf.HIGHLIGHTS -> {
                val highlights = state.highlights.entries.toList()
                val ids = remember(highlights) { highlights.map { it.key } }
                val texts by rememberVerses(ids, state.bible, verses)
                if (highlights.isEmpty()) {
                    QuietEmptyState(stringResource(R.string.no_highlights_yet), stringResource(R.string.no_highlights_message))
                } else {
                    VerseList(highlights.map { it.key }) { verse ->
                        VerseSnippet(
                            ReferenceParser.describe(verse.rawValue, language = language),
                            texts[verse]?.plainText ?: "",
                            highlight = state.highlights[verse],
                            modifier = Modifier.fillMaxWidth().clickable { onRead(verse) }.padding(horizontal = 20.dp, vertical = 14.dp),
                        )
                    }
                }
            }
            LibraryShelf.NOTES -> {
                LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
                    if (state.notes.isEmpty()) {
                        item { QuietEmptyState(stringResource(R.string.no_notes_yet), stringResource(R.string.no_notes_message)) }
                    }
                    items(state.notes, key = { it.id }) { note ->
                        NoteRow(note, language, Modifier.fillMaxWidth().clickable { onOpenNote(note.id) }.padding(horizontal = 20.dp, vertical = 14.dp))
                        HorizontalDivider(Modifier.padding(start = 20.dp), color = colors.separator)
                    }
                    item {
                        TextButton(onClick = onNewNote, modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp)) {
                            Text("+  " + stringResource(R.string.new_note), color = colors.accent, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
            LibraryShelf.BOOKMARKS -> {
                val bookmarks = remember(state.bookmarks) { state.bookmarks.sorted() }
                val texts by rememberVerses(bookmarks, state.bible, verses)
                if (bookmarks.isEmpty()) {
                    QuietEmptyState(stringResource(R.string.no_bookmarks_yet), stringResource(R.string.no_bookmarks_message))
                } else {
                    VerseList(bookmarks) { verse ->
                        VerseSnippet(
                            ReferenceParser.describe(verse.rawValue, language = language),
                            texts[verse]?.plainText ?: "",
                            maxLines = 2,
                            modifier = Modifier.fillMaxWidth().clickable { onRead(verse) }.padding(horizontal = 20.dp, vertical = 14.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun VerseList(ids: List<VerseId>, row: @Composable (VerseId) -> Unit) {
    val colors = LocalReaderColors.current
    LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
        items(ids, key = { it.rawValue }) { verse ->
            row(verse)
            HorizontalDivider(Modifier.padding(start = 20.dp), color = colors.separator)
        }
    }
}

private val LibraryShelf.title: Int
    get() = when (this) {
        LibraryShelf.HIGHLIGHTS -> R.string.highlights
        LibraryShelf.NOTES -> R.string.notes
        LibraryShelf.BOOKMARKS -> R.string.bookmarks
    }
