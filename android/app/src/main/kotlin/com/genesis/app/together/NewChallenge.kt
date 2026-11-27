package com.genesis.app.together

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.prayer.JournalBible
import com.genesis.app.prayer.fieldColors
import com.genesis.core.cloud.community.ChallengeChapters
import com.genesis.core.cloud.community.ChallengeDraft
import com.genesis.core.cloud.community.ChallengeKind
import com.genesis.core.cloud.community.ChallengeRules
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Owners and moderators start a challenge (NewGroupChallengeView on iOS):
 * what kind, a suggested title, when and how long, and what to read or learn.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun NewChallengeDialog(bible: JournalBible, bibleId: String, onCreate: suspend (ChallengeDraft) -> Boolean, onCancel: () -> Unit) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val state by app.community.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    val today = LocalDate.now()
    var kind by rememberSaveable { mutableStateOf(ChallengeKind.READING) }
    var title by rememberSaveable { mutableStateOf("") }
    var details by rememberSaveable { mutableStateOf("") }
    var start by rememberSaveable { mutableStateOf(today.toString()) }
    var days by rememberSaveable { mutableStateOf(ChallengeKind.READING.defaultDays) }
    var book by rememberSaveable { mutableStateOf(41) }
    var first by rememberSaveable { mutableStateOf(1) }
    var last by rememberSaveable { mutableStateOf(BibleBooks.withNumber(41).chapterCount) }
    var passageText by rememberSaveable { mutableStateOf("") }
    var pickingDate by remember { mutableStateOf(false) }
    var pickingBook by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }

    val language = bible.language
    val count = BibleBooks.withNumber(book).chapterCount
    val chapters = ChallengeChapters.range(book, first, last, count)
    val bookName = BibleBooks.withNumber(book).name(language)
    val readingName = when {
        first <= 1 && last >= count -> bookName
        first == last -> "$bookName $first"
        else -> "$bookName $first–$last"
    }
    // A typed passage: one chapter, up to 15 verses.
    val passage = remember(passageText) {
        ReferenceParser.parse(passageText, portugueseFirst = language == "pt")?.let { reference ->
            val chapter = reference.chapter ?: return@let null
            val from = reference.verseStart ?: return@let null
            val to = maxOf(from, reference.verseEnd ?: from)
            if (to - from >= ChallengeRules.MAXIMUM_VERSES) null
            else Triple(reference.copy(verseEnd = to), VerseId(reference.book.id, chapter, from), VerseId(reference.book.id, chapter, to))
        }
    }
    val passageWords by produceState<String?>(null, passage, bible.key) {
        value = passage?.let { (_, from, to) ->
            val ids = (from.verse..to.verse).map { VerseId(from.book, from.chapter, it) }
            val verses = bible.verses(ids)
            ids.mapNotNull { verses[it]?.displayText }.joinToString(" ").ifBlank { null }
        }
    }
    val suggested = when (kind) {
        ChallengeKind.READING -> if (days == 1) stringResource(R.string.title_read_one, readingName) else stringResource(R.string.title_read_days, readingName, days)
        ChallengeKind.MEMORISE -> passage?.let { stringResource(R.string.title_learn, it.first.description(language)) } ?: stringResource(R.string.title_learn_passage)
        ChallengeKind.STREAK -> if (days == 1) stringResource(R.string.title_streak_one) else stringResource(R.string.title_streak, days)
        ChallengeKind.PRAYER -> if (days == 1) stringResource(R.string.title_pray_one) else stringResource(R.string.title_pray, days)
    }
    val draft = ChallengeDraft(
        kind = kind,
        title = title.ifBlank { suggested },
        details = details,
        start = LocalDate.parse(start),
        days = days,
        chapters = chapters,
        verseStart = passage?.second?.rawValue,
        verseEnd = passage?.third?.rawValue,
        translationId = bibleId,
    )

    @Composable
    fun Header(text: Int) = Text(stringResource(text).uppercase(), style = MaterialTheme.typography.labelMedium, color = colors.secondaryText, modifier = Modifier.padding(top = 8.dp))

    @Composable
    fun Stepper(label: String, onMinus: (() -> Unit)?, onPlus: (() -> Unit)?) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(label, color = colors.text, modifier = Modifier.weight(1f))
            TextButton(onClick = { onMinus?.invoke() }, enabled = onMinus != null) { Text("−", color = colors.accent, style = MaterialTheme.typography.titleLarge) }
            TextButton(onClick = { onPlus?.invoke() }, enabled = onPlus != null) { Text("+", color = colors.accent, style = MaterialTheme.typography.titleLarge) }
        }
    }

    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(stringResource(R.string.new_challenge)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Header(R.string.kind_of_challenge)
                ChallengeKind.entries.forEach { option ->
                    val selected = option == kind
                    Column(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                            .background(if (selected) colors.accent.copy(alpha = 0.14f) else colors.surface)
                            .clickable {
                                kind = option
                                days = option.defaultDays
                            }
                            .padding(10.dp),
                    ) {
                        Text("${option.symbol}  " + stringResource(option.title), fontWeight = FontWeight.SemiBold, color = if (selected) colors.accent else colors.text)
                        Text(stringResource(option.summary), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                    }
                }

                Header(R.string.about)
                OutlinedTextField(value = title, onValueChange = { title = it.take(80) }, placeholder = { Text(suggested) }, singleLine = true, colors = fieldColors(), modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = details, onValueChange = { details = it.take(ChallengeRules.DETAILS_LENGTH) }, placeholder = { Text(stringResource(R.string.details_optional)) }, minLines = 2, colors = fieldColors(), modifier = Modifier.fillMaxWidth())

                Header(R.string.`when`)
                Row(Modifier.fillMaxWidth().clickable { pickingDate = true }.padding(vertical = 8.dp)) {
                    Text(stringResource(R.string.starts), color = colors.text, modifier = Modifier.weight(1f))
                    Text(mediumDate(LocalDate.parse(start)), color = colors.accent)
                }
                Stepper(
                    if (days == 1) stringResource(R.string.one_day) else stringResource(R.string.n_days, days),
                    onMinus = if (days > ChallengeRules.dayRange.first) ({ days-- }) else null,
                    onPlus = if (days < ChallengeRules.dayRange.last) ({ days++ }) else null,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    kind.suggestedDays.forEach { option ->
                        Text(
                            stringResource(R.string.n_days, option),
                            style = MaterialTheme.typography.labelLarge,
                            color = if (days == option) colors.background else colors.text,
                            modifier = Modifier.clip(CircleShape).background(if (days == option) colors.accent else colors.surface).clickable { days = option }.padding(horizontal = 12.dp, vertical = 6.dp),
                        )
                    }
                }
                Text(stringResource(R.string.ends_on, mediumDate(LocalDate.parse(start).plusDays(days - 1L))), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)

                when (kind) {
                    ChallengeKind.READING -> {
                        Header(R.string.what_to_read)
                        Box {
                            Row(Modifier.fillMaxWidth().clickable { pickingBook = true }.padding(vertical = 8.dp)) {
                                Text(stringResource(R.string.book), color = colors.text, modifier = Modifier.weight(1f))
                                Text(bookName, color = colors.accent)
                            }
                            DropdownMenu(expanded = pickingBook, onDismissRequest = { pickingBook = false }) {
                                BibleBooks.all.forEach { option ->
                                    DropdownMenuItem(text = { Text(option.name(language)) }, onClick = {
                                        pickingBook = false
                                        book = option.id
                                        first = 1
                                        last = option.chapterCount
                                    })
                                }
                            }
                        }
                        if (count > 1) {
                            Stepper(stringResource(R.string.from_chapter, first), onMinus = if (first > 1) ({ first-- }) else null, onPlus = if (first < last) ({ first++ }) else null)
                            Stepper(stringResource(R.string.to_chapter, last), onMinus = if (last > first) ({ last-- }) else null, onPlus = if (last < count) ({ last++ }) else null)
                        }
                        Text(
                            if (chapters.size == 1) stringResource(R.string.one_chapter) else stringResource(R.string.n_chapters, chapters.size),
                            style = MaterialTheme.typography.bodySmall,
                            color = colors.secondaryText,
                        )
                    }
                    ChallengeKind.MEMORISE -> {
                        Header(R.string.passage)
                        OutlinedTextField(value = passageText, onValueChange = { passageText = it.take(40) }, placeholder = { Text(stringResource(R.string.passage_example)) }, singleLine = true, colors = fieldColors(), modifier = Modifier.fillMaxWidth())
                        when {
                            passageText.isBlank() -> Text(stringResource(R.string.passage_limit, ChallengeRules.MAXIMUM_VERSES), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                            passage == null -> Text(stringResource(R.string.passage_help), style = MaterialTheme.typography.bodySmall, color = colors.accent)
                            passageWords == null -> Text(stringResource(R.string.passage_not_in_bible), style = MaterialTheme.typography.bodySmall, color = colors.accent)
                            else -> Text(passageWords.orEmpty(), style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Serif), color = colors.text)
                        }
                    }
                    else -> Unit
                }
                state.error?.let { Text(stringResource(it.text()), style = MaterialTheme.typography.bodySmall, color = colors.accent) }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    saving = true
                    scope.launch {
                        if (!onCreate(draft)) saving = false
                    }
                },
                enabled = !saving && draft.isValid(today) && (kind != ChallengeKind.MEMORISE || passageWords != null),
            ) { Text(stringResource(R.string.start), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        },
        dismissButton = { TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel), color = colors.secondaryText) } },
    )

    if (pickingDate) {
        val picker = rememberDatePickerState(initialSelectedDateMillis = LocalDate.parse(start).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { pickingDate = false },
            confirmButton = {
                TextButton(onClick = {
                    picker.selectedDateMillis?.let { millis ->
                        val chosen = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                        start = chosen.coerceIn(today, today.plusDays(ChallengeRules.LATEST_START_DAYS.toLong())).toString()
                    }
                    pickingDate = false
                }) { Text(stringResource(R.string.ok), color = colors.accent) }
            },
            dismissButton = { TextButton(onClick = { pickingDate = false }) { Text(stringResource(R.string.cancel), color = colors.secondaryText) } },
        ) { DatePicker(state = picker) }
    }
}
