package com.genesis.app.prayer

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.core.bible.Verse
import com.genesis.core.data.UserDatabase
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.prayer.Prayer
import com.genesis.core.domain.prayer.PrayerCategory
import com.genesis.core.domain.prayer.PrayerSearch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

/** What the journal needs from the Bible being read, to show passages verbatim. */
class JournalBible(
    val key: Any,
    val language: String,
    val abbreviation: String,
    val verses: suspend (Collection<VerseId>) -> Map<VerseId, Verse>,
)

/**
 * The private prayer journal, as PrayerJournalView on iOS: requests and
 * answered prayers, categories, search, and attached passages shown verbatim
 * from the Bible being read. Free, with no limits; synced with the account.
 */
@Composable
fun PrayerJournalFlow(store: UserDatabase.PrayerStore, bible: JournalBible, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val prayers by store.all.collectAsStateWithLifecycle()
    var editingId by rememberSaveable { mutableStateOf<String?>(null) }
    var newCategory by rememberSaveable { mutableStateOf<String?>(null) }

    val editing = editingId
    if (editing != null) {
        val existing = prayers.firstOrNull { it.id == editing }
        val start = remember(editing) {
            existing ?: Prayer(id = editing, category = newCategory?.let(PrayerCategory::lenient) ?: PrayerCategory.PERSONAL)
        }
        PrayerEditor(
            original = start,
            bible = bible,
            onClose = { draft, deleted ->
                when {
                    deleted -> if (existing != null) store.delete(editing)
                    !draft.hasContent -> if (existing != null) store.delete(editing)
                    draft != existing -> store.save(draft)
                }
                editingId = null
            },
            modifier = modifier,
        )
        return
    }

    JournalList(
        prayers = prayers,
        onOpen = { editingId = it },
        onNew = { category ->
            newCategory = category?.id
            editingId = UUID.randomUUID().toString()
        },
        onDone = onDone,
        modifier = modifier,
    )
}

@Composable
private fun JournalList(
    prayers: List<Prayer>,
    onOpen: (String) -> Unit,
    onNew: (PrayerCategory?) -> Unit,
    onDone: () -> Unit,
    modifier: Modifier,
) {
    val colors = LocalReaderColors.current
    var timelineMode by rememberSaveable { mutableStateOf(false) }
    var answered by rememberSaveable { mutableStateOf(false) }
    var categoryId by rememberSaveable { mutableStateOf<String?>(null) }
    var query by rememberSaveable { mutableStateOf("") }
    val category = categoryId?.let(PrayerCategory::lenient)
    val searched = prayers.filter { it.hasContent && (category == null || it.category == category) && PrayerSearch.matches(it, query) }
    val visible = searched.filter { it.isAnswered == answered }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding().imePadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.prayer_journal),
                style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = { onNew(category) }) { Text("+ " + stringResource(R.string.new_prayer), color = colors.accent) }
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        LazyColumn(
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    placeholder = { Text(stringResource(R.string.search_prayers)) },
                    singleLine = true,
                    colors = fieldColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            if (query.isBlank()) item { PrayerLife(prayers) }
            item {
                Spacer(Modifier.size(8.dp))
                Segmented(
                    options = listOf(stringResource(R.string.journal_list), stringResource(R.string.journal_timeline)),
                    selected = if (timelineMode) 1 else 0,
                    onSelect = { timelineMode = it == 1 },
                )
            }
            if (!timelineMode) {
                item {
                    Segmented(
                        options = listOf(stringResource(R.string.praying), stringResource(R.string.answered)),
                        selected = if (answered) 1 else 0,
                        onSelect = { answered = it == 1 },
                    )
                }
            }
            item { CategoryChips(category, includeAll = true) { categoryId = it?.id } }
            if (timelineMode) {
                timeline(searched, onOpen)
            } else if (visible.isEmpty()) {
                item {
                    val (title, message) = when {
                        query.isNotBlank() -> R.string.no_matching_prayers to R.string.no_matching_prayers_message
                        answered -> R.string.no_answered_prayers to R.string.no_answered_prayers_message
                        else -> R.string.no_prayer_requests to R.string.no_prayer_requests_message
                    }
                    EmptyJournal(title, message)
                }
            }
            if (!timelineMode) items(visible, key = { it.id }) { prayer -> PrayerRow(prayer, Modifier.clickable { onOpen(prayer.id) }) }
        }
    }
}

@Composable
private fun PrayerRow(prayer: Prayer, modifier: Modifier) {
    val colors = LocalReaderColors.current
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).then(modifier).background(colors.surface).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            val details = buildList {
                add(stringResource(prayer.category.title))
                if (prayer.passages.isNotEmpty()) add("†")
            }.joinToString("  ")
            Text(details, style = MaterialTheme.typography.labelMedium, color = colors.secondaryText, modifier = Modifier.weight(1f))
            val date = if (prayer.isAnswered && prayer.answeredAt != null) {
                stringResource(R.string.answered_on, shortDate(prayer.answeredAt!!))
            } else {
                shortDate(prayer.createdAt)
            }
            Text(date, style = MaterialTheme.typography.labelMedium, color = colors.secondaryText)
        }
        Text(
            prayer.displayTitle ?: stringResource(R.string.prayer),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = colors.text,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        val note = prayer.answerNote
        if (prayer.isAnswered && !note.isNullOrBlank()) {
            Text(note, style = MaterialTheme.typography.bodyMedium, fontStyle = FontStyle.Italic, color = colors.secondaryText, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
internal fun EmptyJournal(title: Int, message: Int) {
    val colors = LocalReaderColors.current
    Column(Modifier.fillMaxWidth().padding(vertical = 40.dp, horizontal = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(stringResource(title), style = MaterialTheme.typography.titleMedium, color = colors.text, textAlign = TextAlign.Center)
        Spacer(Modifier.size(6.dp))
        Text(stringResource(message), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, textAlign = TextAlign.Center)
    }
}

internal fun shortDate(millis: Long): String {
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "MMMd")
    return DateTimeFormatter.ofPattern(pattern).format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))
}

internal val PrayerCategory.title: Int
    get() = when (this) {
        PrayerCategory.FAMILY -> R.string.category_family
        PrayerCategory.CHURCH -> R.string.category_church
        PrayerCategory.WORK -> R.string.category_work
        PrayerCategory.HEALTH -> R.string.category_health
        PrayerCategory.PERSONAL -> R.string.category_personal
        PrayerCategory.FRIENDS -> R.string.category_friends
    }

/** "All" (when asked for) and one chip per category. */
@Composable
internal fun CategoryChips(selection: PrayerCategory?, includeAll: Boolean, onSelect: (PrayerCategory?) -> Unit) {
    val colors = LocalReaderColors.current
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        @Composable
        fun chip(title: String, selected: Boolean, onClick: () -> Unit) {
            Text(
                title,
                style = MaterialTheme.typography.bodyMedium,
                color = if (selected) colors.background else colors.text,
                modifier = Modifier.clip(CircleShape).clickable(onClick = onClick)
                    .background(if (selected) colors.accent else colors.surface)
                    .padding(horizontal = 14.dp, vertical = 7.dp),
            )
        }
        if (includeAll) chip(stringResource(R.string.all), selection == null) { onSelect(null) }
        PrayerCategory.entries.forEach { item ->
            chip(stringResource(item.title), selection == item) { onSelect(if (includeAll && selection == item) null else item) }
        }
    }
}

/** Two or three options in a row, as a segmented picker on iOS. */
@Composable
internal fun Segmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    val colors = LocalReaderColors.current
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(colors.surface).padding(3.dp)) {
        options.forEachIndexed { index, title ->
            Text(
                title,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = if (index == selected) FontWeight.SemiBold else FontWeight.Normal,
                color = if (index == selected) colors.text else colors.secondaryText,
                textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f).clip(RoundedCornerShape(8.dp))
                    .background(if (index == selected) colors.background else colors.surface)
                    .clickable { onSelect(index) }
                    .padding(vertical = 8.dp),
            )
        }
    }
}

@Composable
internal fun fieldColors(): TextFieldColors {
    val colors = LocalReaderColors.current
    return OutlinedTextFieldDefaults.colors(
        focusedTextColor = colors.text,
        unfocusedTextColor = colors.text,
        focusedBorderColor = colors.accent,
        unfocusedBorderColor = colors.separator,
        cursorColor = colors.accent,
        focusedContainerColor = colors.surface,
        unfocusedContainerColor = colors.surface,
        focusedPlaceholderColor = colors.secondaryText,
        unfocusedPlaceholderColor = colors.secondaryText,
    )
}
