package com.genesis.app.explore

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.prayer.Segmented
import com.genesis.app.prayer.fieldColors
import com.genesis.core.bible.StudyRepository
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.study.Era
import com.genesis.core.domain.study.PersonSummary
import com.genesis.core.domain.study.TimelineEvent
import com.genesis.core.domain.study.yearRange
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/** Where Explore has gone: an event, a person or a place (e/p/q and its id), kept across rotation. */
internal sealed interface ExploreRoute {
    data class Event(val id: Int) : ExploreRoute
    data class PersonPage(val id: Int) : ExploreRoute
    data class PlacePage(val id: Int) : ExploreRoute

    val key: String
        get() = when (this) {
            is Event -> "e$id"
            is PersonPage -> "p$id"
            is PlacePage -> "q$id"
        }

    companion object {
        fun of(key: String): ExploreRoute? {
            val id = key.drop(1).toIntOrNull() ?: return null
            return when (key.first()) {
                'e' -> Event(id)
                'p' -> PersonPage(id)
                'q' -> PlacePage(id)
                else -> null
            }
        }
    }
}

/** What Explore's pages need from the rest of the app. */
internal class ExploreContext(
    val study: StudyRepository?,
    /** The language for references next to Scripture (the Bible's) and its abbreviation. */
    val bibleLanguage: String,
    val abbreviation: String,
    val verses: suspend (Collection<VerseId>) -> Map<VerseId, com.genesis.core.bible.Verse>,
    val onRead: (VerseId) -> Unit,
    val open: (ExploreRoute) -> Unit,
)

/**
 * The Explore tab, as ExploreView on iOS: the Bible timeline and people
 * (free), and the map and journeys (Premium; free accounts see a preview).
 * Events, people and places open as pages over it; back returns.
 */
@Composable
fun ExploreScreen(
    study: StudyRepository?,
    bibleLanguage: String,
    abbreviation: String,
    verses: suspend (Collection<VerseId>) -> Map<VerseId, com.genesis.core.bible.Verse>,
    onRead: (VerseId) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalReaderColors.current
    var section by rememberSaveable { mutableStateOf(0) }
    var stack by rememberSaveable { mutableStateOf(listOf<String>()) }
    val context = ExploreContext(study, bibleLanguage, abbreviation, verses, onRead) { stack = stack + it.key }
    BackHandler(enabled = stack.isNotEmpty()) { stack = stack.dropLast(1) }

    val top = stack.lastOrNull()?.let(ExploreRoute::of)
    if (top != null && study != null) {
        Column(modifier.background(colors.background)) {
            // A visible way back as well as the system's back gesture: one page at a time.
            TextButton(onClick = { stack = stack.dropLast(1) }, modifier = Modifier.padding(start = 4.dp, top = 8.dp)) {
                Text("‹ " + stringResource(if (stack.size > 1) R.string.back else R.string.tab_explore), color = colors.accent)
            }
            Box(Modifier.weight(1f)) {
                when (top) {
                    is ExploreRoute.Event -> EventPage(top.id, context)
                    is ExploreRoute.PersonPage -> PersonPage(top.id, context)
                    is ExploreRoute.PlacePage -> PlacePage(top.id, context)
                }
            }
        }
        return
    }

    Column(modifier.background(colors.background)) {
        Text(
            stringResource(R.string.tab_explore),
            style = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
            color = colors.text,
            modifier = Modifier.padding(start = 20.dp, top = 16.dp, end = 20.dp).semantics { heading() },
        )
        if (study == null) {
            Missing()
            return@Column
        }
        Box(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
            Segmented(
                options = listOf(stringResource(R.string.journal_timeline), stringResource(R.string.explore_map), stringResource(R.string.people)),
                selected = section,
                onSelect = { section = it },
            )
        }
        when (section) {
            0 -> TimelineBrowser(context)
            1 -> MapLocked(study)
            else -> PeopleBrowser(context)
        }
    }
}

@Composable
private fun TimelineBrowser(context: ExploreContext) {
    val colors = LocalReaderColors.current
    val study = context.study ?: return
    val loaded by produceState<Pair<List<Era>, Map<String, List<TimelineEvent>>>?>(null, study) {
        value = withContext(Dispatchers.IO) {
            val eras = study.eras()
            eras to eras.associate { it.id to study.eventsInEra(it.id) }
        }
    }
    var selectedEra by rememberSaveable { mutableStateOf<String?>(null) }
    val (eras, events) = loaded ?: return

    Column {
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Chip(stringResource(R.string.all), selectedEra == null) { selectedEra = null }
            eras.forEach { era -> Chip(era.title, selectedEra == era.id) { selectedEra = era.id } }
        }
        val shown = selectedEra?.let { id -> eras.filter { it.id == id } } ?: eras
        // A fresh list per era, so it opens at the top.
        androidx.compose.runtime.key(selectedEra) {
            LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                item {
                    Text(stringResource(R.string.chronology_note), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText, modifier = Modifier.padding(bottom = 12.dp))
                }
                for (era in shown) {
                    val eraEvents = events[era.id].orEmpty()
                    item(key = "era-${era.id}") { EraHeader(era, eraEvents, context) }
                    items(eraEvents, key = { "ev-${it.id}" }) { event ->
                        EventRow(event, context.bibleLanguage, Modifier.fillMaxWidth().background(colors.surface).clickable { context.open(ExploreRoute.Event(event.id)) }.padding(horizontal = 16.dp, vertical = 12.dp))
                    }
                    item(key = "gap-${era.id}") { Spacer(Modifier.size(20.dp)) }
                }
            }
        }
    }
}

@Composable
private fun EraHeader(era: Era, events: List<TimelineEvent>, context: ExploreContext) {
    val colors = LocalReaderColors.current
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(topStart = 14.dp, topEnd = 14.dp)).background(colors.surface).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                era.title,
                style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            yearRange(era, events)?.let { (first, last) ->
                val label = if (first == last) yearLabel(first) else "${yearLabel(first)} – ${yearLabel(last)}"
                Text(label, style = MaterialTheme.typography.labelSmall, color = colors.secondaryText)
            }
        }
        Text(era.summary, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
        Text(
            stringResource(R.string.read_chapter, era.firstVerse.chapterId.description(context.bibleLanguage)),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = colors.accent,
            modifier = Modifier.clickable { context.onRead(era.firstVerse) }.padding(vertical = 4.dp),
        )
    }
}

@Composable
internal fun EventRow(event: TimelineEvent, language: String, modifier: Modifier) {
    val colors = LocalReaderColors.current
    Row(modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.padding(top = 7.dp).size(7.dp).clip(CircleShape).background(colors.accent))
        Column {
            Text(event.title, style = MaterialTheme.typography.bodyLarge, color = colors.text)
            val details = listOfNotNull(yearLabel(event), event.firstVerse?.let { ReferenceParser.describe(it.rawValue, language = language) })
            if (details.isNotEmpty()) Text(details.joinToString("  "), style = MaterialTheme.typography.labelSmall, color = colors.secondaryText)
        }
    }
}

@Composable
private fun PeopleBrowser(context: ExploreContext) {
    val colors = LocalReaderColors.current
    val study = context.study ?: return
    var query by rememberSaveable { mutableStateOf("") }
    var people by androidx.compose.runtime.remember { mutableStateOf<List<PersonSummary>>(emptyList()) }
    LaunchedEffect(query) {
        // A short pause so typing doesn't query on every keystroke.
        if (query.isNotEmpty()) delay(150)
        people = withContext(Dispatchers.IO) { study.searchPeople(query, if (query.isEmpty()) 100 else 60) }
    }
    Column {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = { Text(stringResource(R.string.find_a_person)) },
            singleLine = true,
            colors = fieldColors(),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        )
        LazyColumn(contentPadding = PaddingValues(16.dp)) {
            items(people, key = { it.id }) { person ->
                PersonRow(person, Modifier.fillMaxWidth().background(colors.surface).clickable { context.open(ExploreRoute.PersonPage(person.id)) }.padding(horizontal = 16.dp, vertical = 12.dp))
            }
        }
    }
}

@Composable
private fun PersonRow(person: PersonSummary, modifier: Modifier) {
    val colors = LocalReaderColors.current
    Column(modifier.semantics(mergeDescendants = true) {}) {
        Text(person.name, style = MaterialTheme.typography.bodyLarge, color = colors.text)
        val count = if (person.verseCount == 1) stringResource(R.string.one_verse) else stringResource(R.string.verse_count, person.verseCount)
        val also = person.alsoCalled.takeIf { it.isNotEmpty() }?.let { stringResource(R.string.also_names, it) }
        Text(listOfNotNull(also, count).joinToString("  "), style = MaterialTheme.typography.labelSmall, color = colors.secondaryText, maxLines = 1)
    }
}

/** What free accounts see on the Map: the journeys and the way to unlock (with Premium, when billing arrives). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MapLocked(study: StudyRepository) {
    val colors = LocalReaderColors.current
    val journeys by produceState(emptyList<String>(), study) { value = withContext(Dispatchers.IO) { study.routes().map { it.title } } }
    Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp).widthIn(max = 620.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(
            stringResource(R.string.walk_the_lands),
            style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
            color = colors.text,
        )
        Text(stringResource(R.string.map_premium_message), style = MaterialTheme.typography.bodyLarge, color = colors.secondaryText)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            journeys.forEach { journey ->
                Text(journey, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, modifier = Modifier.clip(CircleShape).background(colors.surface).padding(horizontal = 12.dp, vertical = 7.dp))
            }
        }
    }
}

@Composable
internal fun Chip(title: String, selected: Boolean = false, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Text(
        title,
        style = MaterialTheme.typography.bodyMedium,
        fontWeight = FontWeight.Medium,
        color = if (selected) colors.background else colors.text,
        modifier = Modifier.clip(CircleShape).background(if (selected) colors.accent else colors.surface).clickable(onClick = onClick)
            .semantics { this.selected = selected }.padding(horizontal = 12.dp, vertical = 7.dp),
    )
}

@Composable
private fun Missing() {
    val colors = LocalReaderColors.current
    Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Text(stringResource(R.string.study_data_unavailable), style = MaterialTheme.typography.titleMedium, color = colors.text)
        Text(stringResource(R.string.study_data_reinstall), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
    }
}
