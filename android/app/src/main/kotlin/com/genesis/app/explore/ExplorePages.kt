package com.genesis.app.explore

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.rememberFontFamily
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.study.BookMentions
import com.genesis.core.domain.study.Family
import com.genesis.core.domain.study.Person
import com.genesis.core.domain.study.PersonSummary
import com.genesis.core.domain.study.Place
import com.genesis.core.domain.study.PlaceCertainty
import com.genesis.core.domain.study.PlaceSummary
import com.genesis.core.domain.study.TimelineEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** One event: when, where, who, and the chapters that tell it. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun EventPage(id: Int, context: ExploreContext) {
    val study = context.study ?: return
    class Loaded(val event: TimelineEvent, val chapters: List<ChapterId>, val people: List<PersonSummary>, val places: List<PlaceSummary>, val era: String?)
    val loaded by produceState<Loaded?>(null, id) {
        value = withContext(Dispatchers.IO) {
            study.event(id)?.let { event ->
                Loaded(event, study.chapters(id), study.peopleInEvent(id), study.placesInEvent(id), study.eras().firstOrNull { it.id == event.eraId }?.title)
            }
        }
    }
    Page(loaded == null) {
        val page = loaded ?: return@Page
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Title(page.event.title)
            Text(listOfNotNull(page.era, yearLabel(page.event)).joinToString(" · "), style = MaterialTheme.typography.bodyMedium, color = LocalReaderColors.current.secondaryText)
        }
        if (page.chapters.isNotEmpty()) {
            Section(stringResource(R.string.read_action)) {
                Chips(page.chapters.map { it.description(context.bibleLanguage) }) { context.onRead(page.chapters[it].firstVerse) }
            }
        }
        if (page.people.isNotEmpty()) {
            Section(stringResource(R.string.people)) { Chips(page.people.map { it.name }) { context.open(ExploreRoute.PersonPage(page.people[it].id)) } }
        }
        if (page.places.isNotEmpty()) {
            Section(stringResource(R.string.places)) { Chips(page.places.map { it.name }) { context.open(ExploreRoute.PlacePage(page.places[it].id)) } }
        }
    }
}

/** One person: biography, family tree (Premium), timeline, places, books and verses. */
@Composable
internal fun PersonPage(id: Int, context: ExploreContext) {
    val study = context.study ?: return
    val colors = LocalReaderColors.current
    class Loaded(val person: Person, val family: Family, val events: List<TimelineEvent>, val books: List<BookMentions>, val verses: List<VerseId>, val places: List<PlaceSummary>)
    val loaded by produceState<Loaded?>(null, id) {
        value = withContext(Dispatchers.IO) {
            study.person(id)?.let { Loaded(it, study.family(id), study.eventsForPerson(id), study.books(id), study.versesForPerson(id), study.placesForPerson(id)) }
        }
    }
    Page(loaded == null) {
        val page = loaded ?: return@Page
        val person = page.person
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Title(person.name, large = true)
            listOfNotNull(
                person.summary.alsoCalled.takeIf { it.isNotEmpty() }?.let { stringResource(R.string.also_called, it) },
                groupTitle(person),
                lifespan(person),
            ).forEach { Text(it, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText) }
            person.firstVerse?.let { first ->
                Text(
                    stringResource(R.string.first_mentioned_in, ReferenceParser.describe(first.rawValue, language = context.bibleLanguage)),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = colors.accent,
                    modifier = Modifier.padding(top = 4.dp).clickable { context.onRead(first) },
                )
            }
        }
        if (person.biography.isNotEmpty()) Section(stringResource(R.string.biography)) { DictionaryText(person.biography, person.biographyIsTranslated) }
        if (!page.family.isEmpty) {
            Section(stringResource(R.string.family_tree)) {
                if (Entitlements.isPremium) {
                    FamilyTree(person.summary, page.family) { context.open(ExploreRoute.PersonPage(it)) }
                } else {
                    Teaser(stringResource(R.string.family_teaser, person.name))
                }
            }
        }
        if (page.events.isNotEmpty()) {
            Section(stringResource(R.string.journal_timeline)) {
                page.events.forEach { event ->
                    EventRow(event, context.bibleLanguage, Modifier.fillMaxWidth().clickable { context.open(ExploreRoute.Event(event.id)) }.padding(vertical = 6.dp))
                }
            }
        }
        if (page.places.isNotEmpty()) {
            Section(stringResource(R.string.places)) { Chips(page.places.map { it.name }) { context.open(ExploreRoute.PlacePage(page.places[it].id)) } }
        }
        if (page.books.isNotEmpty()) {
            Section(stringResource(R.string.books)) {
                Chips(page.books.map { "${BibleBooks.withNumber(it.book).name(context.bibleLanguage)} · ${it.count}" }) { context.onRead(page.books[it].firstVerse) }
            }
        }
        if (page.verses.isNotEmpty()) Section(stringResource(R.string.verses)) { VerseMentions(page.verses, context) }
        Attribution()
    }
}

/** One place: how sure we are where it was, Easton's description, events there and the verses. */
@Composable
internal fun PlacePage(id: Int, context: ExploreContext) {
    val study = context.study ?: return
    val colors = LocalReaderColors.current
    class Loaded(val place: Place, val events: List<TimelineEvent>, val verses: List<VerseId>)
    val loaded by produceState<Loaded?>(null, id) {
        value = withContext(Dispatchers.IO) { study.place(id)?.let { Loaded(it, study.eventsAtPlace(id), study.versesForPlace(id)) } }
    }
    Page(loaded == null) {
        val page = loaded ?: return@Page
        val place = page.place
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Title(place.name)
            Text(
                listOfNotNull(kindTitle(place.summary.kind), place.aliases.takeIf { it.isNotEmpty() }?.let { stringResource(R.string.also_names, it) }).joinToString(" · "),
                style = MaterialTheme.typography.bodyMedium,
                color = colors.secondaryText,
            )
        }
        if (place.summary.isMapped) {
            val certainty = place.summary.certainty
            Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    stringResource(certainty.title),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = if (certainty == PlaceCertainty.UNCERTAIN) colors.secondaryText else colors.accent,
                )
                Text(stringResource(certainty.explanation), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                if (!place.isPrecise && certainty != PlaceCertainty.UNCERTAIN) {
                    Text(stringResource(R.string.pin_general_area), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                }
            }
        }
        if (place.description.isNotEmpty()) Section(stringResource(R.string.about)) { DictionaryText(place.description, place.descriptionIsTranslated) }
        if (page.events.isNotEmpty()) {
            Section(stringResource(R.string.events_here)) {
                page.events.forEach { event ->
                    EventRow(event, context.bibleLanguage, Modifier.fillMaxWidth().clickable { context.open(ExploreRoute.Event(event.id)) }.padding(vertical = 6.dp))
                }
            }
        }
        if (page.verses.isNotEmpty()) Section(stringResource(R.string.mentioned_in)) { VerseMentions(page.verses, context) }
        Attribution()
    }
}

/** Parents above, the person and spouses in the middle, children below, siblings alongside. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FamilyTree(person: PersonSummary, family: Family, onOpen: (Int) -> Unit) {
    val colors = LocalReaderColors.current
    @Composable
    fun generation(title: String, people: List<PersonSummary>) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = colors.secondaryText)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                people.forEach { relative ->
                    Text(
                        relative.name,
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.text,
                        maxLines = 1,
                        modifier = Modifier.clip(CircleShape).background(colors.background).border(1.dp, colors.separator, CircleShape)
                            .clickable { onOpen(relative.id) }.padding(horizontal = 12.dp, vertical = 7.dp),
                    )
                }
            }
        }
    }
    @Composable
    fun connector() = Box(Modifier.width(1.5.dp).height(18.dp).background(colors.separator))

    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.surface).padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (family.parents.isNotEmpty()) {
            generation(stringResource(R.string.parents), family.parents)
            connector()
        }
        Text(
            person.name,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = colors.background,
            maxLines = 1,
            modifier = Modifier.clip(CircleShape).background(colors.accent).padding(horizontal = 14.dp, vertical = 8.dp),
        )
        if (family.partners.isNotEmpty()) Box(Modifier.padding(top = 10.dp)) { generation(stringResource(R.string.spouses), family.partners) }
        if (family.children.isNotEmpty()) {
            connector()
            generation(stringResource(R.string.children), family.children)
        }
        if (family.siblings.isNotEmpty()) Box(Modifier.padding(top = 18.dp)) { generation(stringResource(R.string.siblings), family.siblings) }
    }
}

/** Verses that mention someone or somewhere, verbatim from the Bible being read; a tap opens the reader there. */
@Composable
private fun VerseMentions(verses: List<VerseId>, context: ExploreContext, limit: Int = 12) {
    val colors = LocalReaderColors.current
    var showsAll by rememberSaveable { mutableStateOf(false) }
    val shown = if (showsAll) verses else verses.take(limit)
    val texts by produceState(emptyMap<VerseId, com.genesis.core.bible.Verse>(), shown, context.abbreviation) { value = context.verses(shown) }
    val family = rememberFontFamily(LocalReaderPreferences.current.font.available(Entitlements.isPremium))
    Column {
        shown.forEach { verse ->
            Column(Modifier.fillMaxWidth().clickable { context.onRead(verse) }.padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(ReferenceParser.describe(verse.rawValue, language = context.bibleLanguage), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = colors.accent)
                texts[verse]?.displayText?.let { Text(it, fontFamily = family, style = MaterialTheme.typography.bodyMedium, color = colors.text, maxLines = 2, overflow = TextOverflow.Ellipsis) }
            }
            HorizontalDivider(color = colors.separator)
        }
        if (verses.size > shown.size) {
            Text(
                stringResource(R.string.show_all_count, verses.size),
                style = MaterialTheme.typography.bodyMedium,
                color = colors.accent,
                modifier = Modifier.padding(top = 10.dp).clickable { showsAll = true },
            )
        }
        Text(stringResource(R.string.scripture_abbreviation, context.abbreviation), style = MaterialTheme.typography.labelSmall, color = colors.secondaryText, modifier = Modifier.padding(top = 8.dp))
    }
}

/** Dictionary text, labelled so it's never mistaken for Scripture. */
@Composable
private fun DictionaryText(text: String, isTranslated: Boolean) {
    val colors = LocalReaderColors.current
    var expanded by rememberSaveable { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(text, style = MaterialTheme.typography.bodyLarge, color = colors.text, maxLines = if (expanded) Int.MAX_VALUE else 6, overflow = TextOverflow.Ellipsis)
        if (text.length > 400) {
            Text(stringResource(if (expanded) R.string.show_less else R.string.read_more), style = MaterialTheme.typography.bodyMedium, color = colors.accent, modifier = Modifier.clickable { expanded = !expanded })
        }
        Text(stringResource(if (isTranslated) R.string.eastons_translated else R.string.eastons), style = MaterialTheme.typography.labelSmall, color = colors.secondaryText)
    }
}

/** A Premium part of a free page: what it offers; tapping it opens the Premium screen. */
@Composable
private fun Teaser(message: String) {
    val colors = LocalReaderColors.current
    Text(
        message,
        style = MaterialTheme.typography.bodyMedium,
        color = colors.secondaryText,
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.surface)
            .clickable { com.genesis.app.premium.Paywall.open() }.padding(16.dp),
    )
}

@Composable
private fun Attribution() {
    Text(stringResource(R.string.study_attribution), style = MaterialTheme.typography.labelSmall, color = LocalReaderColors.current.secondaryText)
}

@Composable
private fun Page(loading: Boolean, content: @Composable ColumnScope.() -> Unit) {
    if (loading) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = LocalReaderColors.current.accent) }
        return
    }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
        content = content,
    )
}

@Composable
private fun Title(text: String, large: Boolean = false) {
    Text(
        text,
        style = (if (large) MaterialTheme.typography.headlineLarge else MaterialTheme.typography.headlineSmall).copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
        color = LocalReaderColors.current.text,
        modifier = Modifier.semantics { heading() },
    )
}

@Composable
private fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title.uppercase(), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = LocalReaderColors.current.secondaryText, modifier = Modifier.semantics { heading() })
        content()
    }
}

/** A wrapping row of tappable chips; the tap gives the chip's index. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Chips(titles: List<String>, onTap: (Int) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        titles.forEachIndexed { index, title -> Chip(title) { onTap(index) } }
    }
}
