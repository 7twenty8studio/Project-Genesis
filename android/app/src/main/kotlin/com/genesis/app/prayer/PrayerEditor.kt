package com.genesis.app.prayer

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.Footer
import com.genesis.app.settings.Group
import com.genesis.app.settings.Header
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.rememberFontFamily
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.prayer.Prayer
import com.genesis.core.domain.prayer.PrayerPassage
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId

/**
 * Writes or edits one prayer, as PrayerEditorView on iOS. Changes are kept
 * when it closes (Done or back); a prayer left empty is discarded.
 */
@Composable
internal fun PrayerEditor(
    original: Prayer,
    bible: JournalBible,
    onClose: (Prayer, Boolean) -> Unit,
    modifier: Modifier,
) {
    val colors = LocalReaderColors.current
    var draft by remember(original.id) { mutableStateOf(original) }
    var confirmDelete by remember { mutableStateOf(false) }
    val context = androidx.compose.ui.platform.LocalContext.current
    val exportScope = rememberCoroutineScope()
    fun close() = onClose(draft, false)
    BackHandler { close() }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding().imePadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(if (draft.isAnswered) R.string.answered_prayer else R.string.prayer),
                style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            com.genesis.app.journal.JournalExtrasMenu(
                sermon = false,
                onTemplate = { template -> draft = draft.copy(body = com.genesis.core.domain.journal.JournalTemplate.inserting(template, draft.body).text) },
                onExport = {
                    val snapshot = draft
                    exportScope.launch {
                        val export = com.genesis.app.journal.JournalExportBuilder(context, bible).export(snapshot)
                        com.genesis.app.journal.JournalPdf.share(context, export)
                    }
                },
            )
            TextButton(onClick = ::close) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp)) {
            OutlinedTextField(
                value = draft.title,
                onValueChange = { draft = draft.copy(title = it) },
                placeholder = { Text(stringResource(R.string.prayer_title_hint)) },
                textStyle = MaterialTheme.typography.titleMedium,
                colors = fieldColors(),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.size(10.dp))
            OutlinedTextField(
                value = draft.body,
                onValueChange = { draft = draft.copy(body = it) },
                placeholder = { Text(stringResource(R.string.prayer_body_hint)) },
                textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = rememberFontFamily(LocalReaderPreferences.current.font.available(Entitlements.isPremium)), fontSize = 17.sp),
                colors = fieldColors(),
                modifier = Modifier.fillMaxWidth().heightIn(min = 140.dp),
            )

            Header(stringResource(R.string.category))
            CategoryChips(draft.category, includeAll = false) { it?.let { category -> draft = draft.copy(category = category) } }

            Passages(draft.passages, bible, PrayerPassage.MAXIMUM_PER_PRAYER, stringResource(R.string.pray_with_scripture), onAttach = { draft = draft.attaching(it) }, onDetach = { draft = draft.detaching(it) })

            if (!draft.isAnswered) {
                Spacer(Modifier.size(24.dp))
                PrayerReminder(draft) { draft = it }
            }

            if (draft.isAnswered) Header(stringResource(R.string.answered)) else Spacer(Modifier.size(24.dp))
            Group {
                if (draft.isAnswered) {
                    OutlinedTextField(
                        value = draft.answerNote.orEmpty(),
                        onValueChange = { draft = draft.copy(answerNote = it) },
                        placeholder = { Text(stringResource(R.string.how_answered)) },
                        colors = fieldColors(),
                        modifier = Modifier.fillMaxWidth().padding(12.dp),
                    )
                    Action(stringResource(R.string.move_back_to_praying)) {
                        draft = draft.answered(false, null, System.currentTimeMillis())
                    }
                } else {
                    val today = LocalDate.now()
                    val prayedToday = draft.lastPrayedAt?.let {
                        java.time.Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()).toLocalDate() == today
                    } ?: false
                    Action(stringResource(if (prayedToday) R.string.prayed_today else R.string.i_prayed_for_this), enabled = !prayedToday) {
                        draft = draft.copy(lastPrayedAt = System.currentTimeMillis())
                    }
                    HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                    Action(stringResource(R.string.mark_as_answered)) {
                        draft = draft.answered(true, null, System.currentTimeMillis())
                    }
                }
            }
            if (draft.isAnswered) Footer(stringResource(R.string.answer_note_footer))

            Spacer(Modifier.size(24.dp))
            Group { Action(stringResource(R.string.delete_prayer), color = Destructive) { confirmDelete = true } }
            Spacer(Modifier.size(32.dp))
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.delete_prayer_question)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    onClose(draft, true)
                }) { Text(stringResource(R.string.delete), color = Destructive) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel), color = colors.accent) } },
            containerColor = colors.surface,
            titleContentColor = colors.text,
        )
    }
}

private val Destructive = Color(0xFFC0392B)

@Composable
private fun Action(title: String, enabled: Boolean = true, color: Color? = null, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Text(
        title,
        style = MaterialTheme.typography.bodyLarge,
        color = when {
            !enabled -> colors.secondaryText
            color != null -> color
            else -> colors.accent
        },
        modifier = Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick).padding(16.dp),
    )
}

/** The passages a prayer or sermon holds, verbatim from the Bible being read, and a field to add another. */
@Composable
internal fun Passages(
    passages: List<PrayerPassage>,
    bible: JournalBible,
    maximum: Int,
    footer: String,
    onAttach: (PrayerPassage) -> Unit,
    onDetach: (PrayerPassage) -> Unit,
) {
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf("") }
    var problem by remember { mutableStateOf<Int?>(null) }
    val family = rememberFontFamily(LocalReaderPreferences.current.font.available(Entitlements.isPremium))

    Header(stringResource(R.string.bible_passages))
    Group {
        passages.forEach { passage ->
            val ids = remember(passage.id) { (passage.start.verse..passage.end.verse).map { VerseId(passage.start.book, passage.start.chapter, it) } }
            val verses by produceState(emptyMap(), passage.id, bible.key) { value = bible.verses(ids) }
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, top = 12.dp, bottom = 12.dp), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        "${passage.reference(bible.language)} · ${bible.abbreviation}",
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = colors.accent,
                    )
                    val words = ids.mapNotNull { verses[it]?.plainText }
                    Text(
                        if (words.isEmpty()) stringResource(R.string.passage_missing) else words.joinToString(" "),
                        fontFamily = if (words.isEmpty()) null else family,
                        fontSize = 16.sp,
                        color = if (words.isEmpty()) colors.secondaryText else colors.text,
                    )
                }
                TextButton(onClick = { onDetach(passage) }) { Text(stringResource(R.string.remove), color = colors.secondaryText) }
            }
            HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
        }
        if (passages.size < maximum) {
            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = text,
                    onValueChange = {
                        text = it
                        problem = null
                    },
                    placeholder = { Text(stringResource(R.string.passage_hint)) },
                    singleLine = true,
                    colors = fieldColors(),
                    modifier = Modifier.weight(1f),
                )
                TextButton(
                    enabled = text.isNotBlank(),
                    onClick = {
                        val passage = PrayerPassage.parse(text, portugueseFirst = bible.language.startsWith("pt")) { chapter ->
                            BibleBooks.withNumber(chapter.book).verses.getOrNull(chapter.chapter - 1)
                        }
                        if (passage == null) {
                            problem = R.string.passage_unreadable
                        } else {
                            scope.launch {
                                if (bible.verses(listOf(passage.start)).isEmpty()) {
                                    problem = R.string.passage_not_in_bible
                                } else {
                                    onAttach(passage)
                                    text = ""
                                }
                            }
                        }
                    },
                ) { Text(stringResource(R.string.add), color = if (text.isBlank()) colors.secondaryText else colors.accent) }
            }
        }
    }
    val message = problem
    if (message != null) {
        Text(stringResource(message), style = MaterialTheme.typography.bodySmall, color = Destructive, modifier = Modifier.padding(start = 16.dp, top = 8.dp))
    } else {
        Footer(footer)
    }
}
