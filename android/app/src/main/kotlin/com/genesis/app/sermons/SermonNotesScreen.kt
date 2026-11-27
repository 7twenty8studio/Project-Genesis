package com.genesis.app.sermons

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.prayer.EmptyJournal
import com.genesis.app.prayer.JournalBible
import com.genesis.app.prayer.Segmented
import com.genesis.app.prayer.fieldColors
import com.genesis.core.data.UserDatabase
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.sermons.Sermon
import com.genesis.core.domain.sermons.SermonGrouping
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

/**
 * Sermon Notes, as SermonListView on iOS: notes grouped by week and month or
 * by church, favourites, search, and the editor. Free, with no limits;
 * synced with the account.
 */
@Composable
fun SermonNotesFlow(
    store: UserDatabase.SermonStore,
    bible: JournalBible,
    startNew: Boolean,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
    /** Opens these notes straight away (a church sermon's Take Notes); Done goes back. */
    openId: String? = null,
    church: com.genesis.app.churchsermons.ChurchSermonContext? = null,
) {
    val sermons by store.all.collectAsStateWithLifecycle()
    var editingId by rememberSaveable { mutableStateOf(openId ?: if (startNew) UUID.randomUUID().toString() else null) }

    val editing = editingId
    if (editing != null) {
        val existing = sermons.firstOrNull { it.id == editing }
        val start = remember(editing) {
            existing ?: System.currentTimeMillis().let { now -> Sermon(id = editing, preachedAt = now, createdAt = 0, updatedAt = 0) }
        }
        SermonEditor(
            original = start,
            bible = bible,
            churchSuggestions = { typed -> SermonGrouping.churchSuggestions(sermons.filter { it.id != editing }, typed) },
            onClose = { draft, deleted ->
                when {
                    deleted || !draft.hasContent -> if (existing != null) store.delete(editing)
                    draft != existing -> store.save(draft)
                }
                editingId = null
                if (openId != null) onDone()
            },
            modifier = modifier,
            church = church,
        )
        return
    }

    SermonList(
        sermons = sermons,
        onOpen = { editingId = it },
        onNew = { editingId = UUID.randomUUID().toString() },
        onFavourite = { store.save(it.copy(isFavourite = !it.isFavourite)) },
        onDone = onDone,
        modifier = modifier,
    )
}

@Composable
private fun SermonList(
    sermons: List<Sermon>,
    onOpen: (String) -> Unit,
    onNew: () -> Unit,
    onFavourite: (Sermon) -> Unit,
    onDone: () -> Unit,
    modifier: Modifier,
) {
    val colors = LocalReaderColors.current
    var query by rememberSaveable { mutableStateOf("") }
    var byChurch by rememberSaveable { mutableStateOf(false) }
    var favouritesOnly by rememberSaveable { mutableStateOf(false) }
    val saved = sermons.filter { it.hasContent }
    val visible = SermonGrouping.visible(saved, query, favouritesOnly)
    val sections = remember(visible, byChurch) {
        SermonGrouping.sections(visible, if (byChurch) SermonGrouping.Mode.CHURCH else SermonGrouping.Mode.DATE)
    }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding().imePadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.sermon_notes),
                style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onNew) { Text("+ " + stringResource(R.string.new_short), color = colors.accent) }
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        LazyColumn(
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (saved.isNotEmpty()) {
                item {
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it },
                        placeholder = { Text(stringResource(R.string.sermons_search)) },
                        singleLine = true,
                        colors = fieldColors(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                item {
                    Segmented(
                        listOf(stringResource(R.string.sermons_by_date), stringResource(R.string.sermons_by_church)),
                        selected = if (byChurch) 1 else 0,
                    ) { byChurch = it == 1 }
                }
                item {
                    Text(
                        "★ " + stringResource(R.string.favorites),
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (favouritesOnly) colors.background else colors.text,
                        modifier = Modifier.clip(CircleShape).clickable { favouritesOnly = !favouritesOnly }
                            .background(if (favouritesOnly) colors.accent else colors.surface)
                            .padding(horizontal = 14.dp, vertical = 7.dp),
                    )
                }
            }
            when {
                saved.isEmpty() -> item { EmptyJournal(R.string.sermons_empty, R.string.sermons_empty_message) }
                visible.isEmpty() && query.isNotBlank() -> item { EmptyJournal(R.string.sermons_no_match, R.string.sermons_no_match_message) }
                visible.isEmpty() -> item { EmptyJournal(R.string.sermons_no_favorites, R.string.sermons_no_favorites_message) }
            }
            sections.forEach { section ->
                item(key = "header-${section.kind}") {
                    Text(
                        section.kind.title(),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = colors.secondaryText,
                        modifier = Modifier.padding(top = 10.dp),
                    )
                }
                items(section.sermons, key = { "${section.kind}-${it.id}" }) { sermon ->
                    SermonRow(sermon, onClick = { onOpen(sermon.id) }, onFavourite = { onFavourite(sermon) })
                }
            }
        }
    }
}

@Composable
private fun SermonGrouping.Kind.title(): String = when (this) {
    SermonGrouping.Kind.ThisWeek -> stringResource(R.string.sermons_this_week)
    SermonGrouping.Kind.NoChurch -> stringResource(R.string.sermons_no_church)
    is SermonGrouping.Kind.Church -> name
    is SermonGrouping.Kind.Month -> {
        val pattern = android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "MMMMyyyy")
        DateTimeFormatter.ofPattern(pattern).format(month)
    }
}

@Composable
private fun SermonRow(sermon: Sermon, onClick: () -> Unit, onFavourite: () -> Unit) {
    val colors = LocalReaderColors.current
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(colors.surface).clickable(onClick = onClick)
            .padding(start = 16.dp, top = 12.dp, bottom = 12.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                sermon.displayTitle ?: stringResource(R.string.untitled_sermon),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = colors.text,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            val details = listOf(sermon.preacher.trim(), sermon.churchName, sermonDate(sermon.preachedAt)).filter { it.isNotEmpty() }
            Text(details.joinToString(" · "), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            sermon.series?.trim()?.takeIf { it.isNotEmpty() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = colors.accent, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        val label = stringResource(if (sermon.isFavourite) R.string.remove_favorite else R.string.favorite)
        TextButton(onClick = onFavourite, modifier = Modifier.semantics { contentDescription = label }) {
            Text(if (sermon.isFavourite) "★" else "☆", style = MaterialTheme.typography.titleLarge, color = if (sermon.isFavourite) colors.accent else colors.secondaryText)
        }
    }
}

internal fun sermonDate(millis: Long): String {
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "yMMMd")
    return DateTimeFormatter.ofPattern(pattern).format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))
}
