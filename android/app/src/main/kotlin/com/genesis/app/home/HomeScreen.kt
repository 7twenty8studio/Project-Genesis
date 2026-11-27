package com.genesis.app.home

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.core.domain.sermons.SermonSunday
import com.genesis.app.library.LibraryShelf
import com.genesis.app.plans.HomePlanCard
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.plans.PlanEnrollment
import com.genesis.app.library.NoteRow
import com.genesis.app.library.VerseSnippet
import com.genesis.app.library.card
import com.genesis.app.library.rememberVerses
import com.genesis.app.reader.Magnifier
import com.genesis.app.reader.ReaderUiState
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.core.bible.Verse
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.rememberFontFamily
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.home.DailyVerse
import com.genesis.core.domain.home.Greeting
import com.genesis.core.domain.home.progressThroughBook
import com.genesis.core.domain.insights.ReadingStats
import com.genesis.core.domain.notifications.NotificationPlanner
import com.genesis.app.settings.ReadingRecord
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * A calm starting place, as HomeView on iOS: continue reading, the verse of
 * the day, recent highlights and notes. Plans, prayer, Memorize, progress and
 * the Bibles on this device join as their features arrive.
 */
@Composable
fun HomeScreen(
    state: ReaderUiState,
    verses: suspend (Collection<VerseId>) -> Map<VerseId, Verse>,
    onRead: (VerseId) -> Unit,
    onContinue: () -> Unit,
    onSearch: () -> Unit,
    onSettings: () -> Unit,
    onOpenNote: (String) -> Unit,
    onSeeAll: (LibraryShelf) -> Unit,
    plans: List<PlanEnrollment>,
    onPlans: (String?) -> Unit,
    onReadChapter: (ChapterId) -> Unit,
    onMarkPlanDay: (PlanEnrollment, Int, Boolean) -> Unit,
    activePrayers: Int,
    onPrayerJournal: () -> Unit,
    memorise: Pair<Int, Int> = 0 to 0,
    onMemorise: () -> Unit = {},
    onSermons: () -> Unit = {},
    record: ReadingRecord,
    onInsights: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalReaderColors.current
    val language = state.chapter?.translation?.language ?: "en"
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    val daily = remember(today) { DailyVerse.verse(today, zone) }
    val recentHighlights = state.highlights.entries.take(10)
    val position = state.position ?: state.chapterId.firstVerse
    val ids = remember(daily, recentHighlights, position) { listOf(daily, position) + recentHighlights.map { it.key } }
    val texts by rememberVerses(ids, state.bible, verses)

    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(horizontal = 20.dp)
            .padding(bottom = 32.dp)
            .widthIn(max = 720.dp),
        verticalArrangement = Arrangement.spacedBy(28.dp),
    ) {
        // Greeting.
        Row(Modifier.padding(top = 24.dp), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                val pattern = android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "EEEEMMMMd")
                Text(DateTimeFormatter.ofPattern(pattern).format(today), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
                Text(
                    stringResource(Greeting.at(LocalTime.now().hour).title),
                    style = MaterialTheme.typography.displaySmall.copy(fontFamily = FontFamily.Serif),
                    color = colors.text,
                )
            }
            val search = stringResource(R.string.search)
            IconButton(onClick = onSearch, modifier = Modifier.semantics { contentDescription = search }) {
                Magnifier(colors.accent, iconSize = 24.dp)
            }
            val settings = stringResource(R.string.settings)
            IconButton(onClick = onSettings, modifier = Modifier.semantics { contentDescription = settings }) {
                Gear(colors.accent)
            }
        }

        // Continue reading.
        Column(
            Modifier.fillMaxWidth().clip18().clickable(onClick = onContinue).card(colors.surface),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                stringResource(if (state.hasStartedReading) R.string.continue_reading else R.string.begin_reading).uppercase(),
                style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 1.1.sp, fontWeight = FontWeight.SemiBold),
                color = colors.accent,
            )
            Text(
                position.chapterId.description(language),
                style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
            )
            texts[position]?.let {
                Text(
                    it.plainText,
                    fontFamily = scriptureFamily(),
                    fontSize = 16.sp,
                    color = colors.secondaryText,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            val book = position.chapterId.bibleBook.name(language)
            val progressLabel = stringResource(R.string.progress_through, book)
            LinearProgressIndicator(
                progress = { progressThroughBook(position).toFloat() },
                color = colors.accent,
                trackColor = colors.separator,
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = progressLabel },
            )
        }

        // Verse of the day.
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionHeader(stringResource(R.string.verse_of_the_day))
            Column(
                Modifier
                    .fillMaxWidth()
                    .clip18(24)
                    .background(Brush.linearGradient(listOf(colors.surface, colors.background)), RoundedCornerShape(24.dp))
                    .border(BorderStroke(1.dp, colors.accent.copy(alpha = 0.25f)), RoundedCornerShape(24.dp))
                    .clickable { onRead(daily) }
                    .padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Text(texts[daily]?.plainText ?: "", fontFamily = scriptureFamily(), fontSize = 21.sp, lineHeight = 30.sp, color = colors.text)
                val abbreviation = state.chapter?.translation?.abbreviation ?: state.bible.id
                Text(
                    "${ReferenceParser.describe(daily.rawValue, language = language)} · $abbreviation",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = colors.accent,
                )
            }
        }

        // Today's reading (reading plans).
        val active = plans.firstOrNull { it.isActive && it.plan != null }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (active != null) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        stringResource(R.string.todays_reading),
                        style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                        color = colors.text,
                        modifier = Modifier.weight(1f).semantics { heading() },
                    )
                    TextButton(onClick = { onPlans(null) }) { Text(stringResource(R.string.all_plans), color = colors.accent) }
                }
            }
            HomePlanCard(
                enrollment = active,
                onRead = onReadChapter,
                onMark = onMarkPlanDay,
                onOpen = { onPlans(it.id) },
                onPlans = { onPlans(null) },
            )
        }

        // Prayer journal.
        Row(
            Modifier.fillMaxWidth().clip18().clickable(onClick = onPrayerJournal).card(colors.surface),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.prayer_journal), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
                Text(
                    when (activePrayers) {
                        0 -> stringResource(R.string.prayer_card_message)
                        1 -> stringResource(R.string.one_prayer_holding)
                        else -> stringResource(R.string.prayers_holding, activePrayers)
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.secondaryText,
                )
            }
            Text("\u203A", style = MaterialTheme.typography.titleLarge, color = colors.secondaryText)
        }

        // Sunday mornings: a card for taking sermon notes.
        if (SermonSunday.isSundayMorning(today.dayOfWeek, LocalTime.now().hour)) {
            Row(
                Modifier.fillMaxWidth().clip18().clickable(onClick = onSermons).card(colors.surface),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(stringResource(R.string.sermon_notes), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
                    Text(stringResource(R.string.sermon_card_message), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
                }
                Text("\u203A", style = MaterialTheme.typography.titleLarge, color = colors.secondaryText)
            }
        }

        // Memorize Scripture (Premium): passages saved and how many are due.
        Row(
            Modifier.fillMaxWidth().clip18().clickable(onClick = onMemorise).card(colors.surface),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val unlocked = Entitlements.isPremium
            val (saved, due) = memorise
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.memorise_title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
                Text(
                    when {
                        !unlocked || saved == 0 -> stringResource(R.string.memorise_card_message)
                        due == 0 -> stringResource(R.string.memorise_caught_up_today)
                        else -> stringResource(R.string.memorise_due_today, due)
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.secondaryText,
                )
            }
            if (!unlocked) {
                Text(
                    stringResource(R.string.premium),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = colors.accent,
                    modifier = Modifier.padding(end = 8.dp),
                )
            }
            Text("\u203A", style = MaterialTheme.typography.titleLarge, color = colors.secondaryText)
        }

        // Progress, with Insights beside it.
        if (state.hasStartedReading) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        stringResource(R.string.progress),
                        style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                        color = colors.text,
                        modifier = Modifier.weight(1f).semantics { heading() },
                    )
                    TextButton(onClick = onInsights) { Text(stringResource(R.string.insights), color = colors.accent) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ProgressStat(NotificationPlanner.streak(record.readingDays, today), stringResource(R.string.day_streak), Modifier.weight(1f))
                    ProgressStat(record.chaptersRead.size, stringResource(R.string.chapters_read), Modifier.weight(1f))
                    ProgressStat(ReadingStats.booksCompleted(record.chaptersRead), stringResource(R.string.books_finished), Modifier.weight(1f))
                }
            }
        }

        // Recently highlighted.
        if (recentHighlights.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeader(stringResource(R.string.recently_highlighted)) { onSeeAll(LibraryShelf.HIGHLIGHTS) }
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp), contentPadding = PaddingValues(end = 20.dp)) {
                    items(recentHighlights, key = { it.key.rawValue }) { (verse, color) ->
                        VerseSnippet(
                            reference = ReferenceParser.describe(verse.rawValue, language = language),
                            text = texts[verse]?.plainText ?: "",
                            highlight = color,
                            maxLines = 4,
                            modifier = Modifier.width(240.dp).clip18().clickable { onRead(verse) }.card(colors.surface),
                        )
                    }
                }
            }
        }

        // Recent notes.
        val recentNotes = state.notes.take(3)
        if (recentNotes.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeader(stringResource(R.string.recent_notes)) { onSeeAll(LibraryShelf.NOTES) }
                Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(18.dp))) {
                    recentNotes.forEachIndexed { index, note ->
                        NoteRow(note, language, Modifier.fillMaxWidth().clickable { onOpenNote(note.id) }.padding(16.dp))
                        if (index < recentNotes.lastIndex) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                    }
                }
            }
        }
        Spacer(Modifier)
    }
}

@Composable
private fun ProgressStat(value: Int, label: String, modifier: Modifier) {
    val colors = LocalReaderColors.current
    Column(
        modifier.background(colors.surface, RoundedCornerShape(16.dp)).padding(14.dp).semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text("$value", style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold), color = colors.text)
        Text(label, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText, maxLines = 2)
    }
}

@Composable
private fun SectionHeader(title: String, onSeeAll: (() -> Unit)? = null) {
    val colors = LocalReaderColors.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            title,
            style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
            color = colors.text,
            modifier = Modifier.weight(1f).semantics { heading() },
        )
        if (onSeeAll != null) {
            TextButton(onClick = onSeeAll) { Text(stringResource(R.string.see_all), color = colors.accent) }
        }
    }
}

@Composable
private fun scriptureFamily() = rememberFontFamily(LocalReaderPreferences.current.font.available(Entitlements.isPremium))

private fun Modifier.clip18(radius: Int = 18) = this.then(Modifier.clip(RoundedCornerShape(radius.dp)))

private val Greeting.title: Int
    get() = when (this) {
        Greeting.MORNING -> R.string.good_morning
        Greeting.AFTERNOON -> R.string.good_afternoon
        Greeting.EVENING -> R.string.good_evening
    }

/** Settings' gear, drawn so the app needs no icon library. */
@Composable
private fun Gear(color: androidx.compose.ui.graphics.Color) {
    androidx.compose.foundation.Canvas(Modifier.size(24.dp)) {
        val center = this.center
        val stroke = size.minDimension * 0.08f
        val outer = size.minDimension * 0.42f
        val ring = size.minDimension * 0.3f
        for (i in 0 until 8) {
            val angle = Math.toRadians(i * 45.0)
            val from = androidx.compose.ui.geometry.Offset(center.x + (ring * kotlin.math.cos(angle)).toFloat(), center.y + (ring * kotlin.math.sin(angle)).toFloat())
            val to = androidx.compose.ui.geometry.Offset(center.x + (outer * kotlin.math.cos(angle)).toFloat(), center.y + (outer * kotlin.math.sin(angle)).toFloat())
            drawLine(color, from, to, stroke * 1.6f, androidx.compose.ui.graphics.StrokeCap.Round)
        }
        drawCircle(color, ring, center, style = androidx.compose.ui.graphics.drawscope.Stroke(stroke))
        drawCircle(color, size.minDimension * 0.11f, center, style = androidx.compose.ui.graphics.drawscope.Stroke(stroke))
    }
}
