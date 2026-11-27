package com.genesis.app.reader

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.library.NoteRow
import com.genesis.app.plans.PlansFlow
import com.genesis.app.prayer.JournalBible
import com.genesis.app.prayer.PrayerJournalFlow
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.features.OptionalFeature
import com.genesis.core.domain.study.NoteAnchor

/** What the study panel shows, as CompanionPanel.Mode on iOS (the study assistant and Context aside). */
enum class CompanionMode { NOTES, RELATED, SEARCH, PLAN, PRAYER }

/**
 * The second column on a tablet or an open foldable, as CompanionPanel.swift:
 * notes, related passages, search, the reading plan or the prayer journal
 * beside the text, so study never covers Scripture. A menu above it picks
 * which; only switched-on features are offered.
 */
@Composable
internal fun CompanionPanel(
    state: ReaderUiState,
    viewModel: ReaderViewModel,
    scripture: TextStyle,
    shows: (OptionalFeature) -> Boolean,
    modifier: Modifier = Modifier,
) {
    val colors = LocalReaderColors.current
    val app = LocalContext.current.applicationContext as VerselyApplication
    val modes = CompanionMode.entries.filter {
        when (it) {
            CompanionMode.PLAN -> shows(OptionalFeature.PLANS)
            CompanionMode.PRAYER -> shows(OptionalFeature.PRAYER)
            else -> true
        }
    }
    val mode = state.companionMode.takeIf { it in modes } ?: CompanionMode.NOTES
    val bottom = TAB_BAR_HEIGHT + 16.dp
    Column(modifier.background(colors.surface).statusBarsPadding()) {
        ModePicker(mode, modes, viewModel::setCompanionMode)
        HorizontalDivider(color = colors.separator)
        Box(Modifier.fillMaxSize().background(colors.background)) {
            when (mode) {
                CompanionMode.NOTES -> ChapterNotes(state, viewModel, bottom)
                CompanionMode.RELATED -> {
                    val verse = state.selection.minByOrNull { it.rawValue } ?: state.focus?.verse ?: state.chapterId.firstVerse
                    LaunchedEffect(state.crossReferences == null, state.chapterId) {
                        if (state.crossReferences == null) viewModel.openCrossReferences(verse)
                    }
                    state.crossReferences?.let { CrossReferencesContent(it, scripture, onOpen = viewModel::openCrossReference, bottomPadding = bottom) }
                }
                CompanionMode.SEARCH -> {
                    val search by viewModel.search.collectAsStateWithLifecycle()
                    SearchContent(search, scripture, viewModel::search, onOpen = viewModel::openVerse, modifier = Modifier.fillMaxSize().padding(top = 12.dp))
                }
                CompanionMode.PLAN -> PlansFlow(
                    store = app.userData.plans,
                    openPlanId = null,
                    onRead = { viewModel.openVerse(it.firstVerse) },
                    onDone = {},
                    modifier = Modifier.fillMaxSize().navigationBarsPadding(),
                )
                CompanionMode.PRAYER -> {
                    val translation = state.chapter?.translation
                    PrayerJournalFlow(
                        store = app.userData.prayers,
                        bible = JournalBible(
                            key = state.bible,
                            language = translation?.language ?: "en",
                            abbreviation = translation?.abbreviation ?: state.bible.id,
                            verses = viewModel::verses,
                            export = viewModel::exportSource,
                        ),
                        onDone = {},
                        modifier = Modifier.fillMaxSize().navigationBarsPadding(),
                    )
                }
            }
        }
    }
}

/** A solid button that opens a menu of the panels (seven don't fit a segmented control). */
@Composable
private fun ModePicker(mode: CompanionMode, modes: List<CompanionMode>, onPick: (CompanionMode) -> Unit) {
    val colors = LocalReaderColors.current
    var open by remember { mutableStateOf(false) }
    val title = stringResource(mode.title)
    val label = stringResource(R.string.panel) + ", " + title
    Box(Modifier.fillMaxWidth().padding(12.dp)) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 44.dp)
                .background(colors.background, RoundedCornerShape(12.dp))
                .border(BorderStroke(1.dp, colors.separator), RoundedCornerShape(12.dp))
                .clickable(role = Role.Button) { open = true }
                .semantics { contentDescription = label }
                .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = colors.text, modifier = Modifier.weight(1f))
            Text("⌃⌄", color = colors.secondaryText, style = MaterialTheme.typography.labelSmall)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for (item in modes) {
                DropdownMenuItem(
                    text = { Text((if (item == mode) "✓ " else "") + stringResource(item.title)) },
                    onClick = { open = false; onPick(item) },
                )
            }
        }
    }
}

private val CompanionMode.title: Int
    get() = when (this) {
        CompanionMode.NOTES -> R.string.notes
        CompanionMode.RELATED -> R.string.related
        CompanionMode.SEARCH -> R.string.search
        CompanionMode.PLAN -> R.string.reminder_reading_plan
        CompanionMode.PRAYER -> R.string.prayer_journal
    }

/** The chapter's notes (on its verses or on the whole chapter), with Note on John 15 underneath. */
@Composable
private fun ChapterNotes(state: ReaderUiState, viewModel: ReaderViewModel, bottom: androidx.compose.ui.unit.Dp) {
    val colors = LocalReaderColors.current
    val language = state.chapter?.translation?.language ?: "en"
    val chapter = state.chapterId
    val notes = state.notes.filter { note ->
        when (val anchor = note.anchor) {
            is NoteAnchor.Chapter -> anchor.chapter == chapter
            is NoteAnchor.Verses -> anchor.start.chapterId == chapter || anchor.end.chapterId == chapter
            else -> false
        }
    }.sortedBy { it.createdAt }
    val name = chapter.description(language)
    Column(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(vertical = 8.dp)) {
            if (notes.isEmpty()) {
                item {
                    Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(stringResource(R.string.no_notes_in, name), style = MaterialTheme.typography.titleSmall, color = colors.text)
                        Text(stringResource(R.string.no_notes_in_detail), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, modifier = Modifier.padding(top = 6.dp))
                    }
                }
            }
            items(notes, key = { it.id }) { note ->
                NoteRow(note, language, Modifier.fillMaxWidth().clickable { viewModel.openNote(note.id) }.padding(horizontal = 16.dp, vertical = 10.dp))
                HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator.copy(alpha = 0.6f))
            }
        }
        OutlinedButton(
            onClick = viewModel::newChapterNote,
            modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = bottom).navigationBarsPadding(),
        ) { Text(stringResource(R.string.note_on, name), color = colors.accent) }
    }
}

