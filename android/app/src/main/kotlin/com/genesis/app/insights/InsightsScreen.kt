package com.genesis.app.insights

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalContext
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
import com.genesis.app.VerselyApplication
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.ReadingRecord
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.insights.ReadingStats
import com.genesis.core.domain.notifications.NotificationPlanner
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

/**
 * Reading statistics, as InsightsView on iOS: the streak, chapters and books
 * for everyone; with Premium (`.readingInsights`) also the longest streak,
 * highlights, notes, reading time, the last two weeks and favorite books.
 */
@Composable
fun InsightsScreen(language: String, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val app = LocalContext.current.applicationContext as VerselyApplication
    val record by app.progress.record.collectAsStateWithLifecycle()
    val highlights by app.userData.highlights.all.collectAsStateWithLifecycle()
    val notes by app.userData.notes.all.collectAsStateWithLifecycle()
    val premium = Entitlements.isPremium
    val today = LocalDate.now()
    BackHandler(onBack = onDone)

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.insights),
                style = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(20.dp).widthIn(max = 720.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            val stats = buildList {
                add(Stat("${(LocalContext.current.applicationContext as com.genesis.app.VerselyApplication).progress.streak(today, record.readingDays)}", stringResource(R.string.day_streak)))
                add(Stat(stringResource(R.string.count_of_total, record.chaptersRead.size, ReadingStats.totalChapters), stringResource(R.string.chapters_read)))
                add(Stat(stringResource(R.string.count_of_total, ReadingStats.booksCompleted(record.chaptersRead), 66), stringResource(R.string.books_finished)))
                if (premium) {
                    add(Stat("${ReadingStats.longestStreak(record.readingDays)}", stringResource(R.string.longest_streak)))
                    add(Stat("${highlights.size}", stringResource(R.string.verses_highlighted)))
                    add(Stat("${notes.count { it.title.isNotBlank() || it.body.isNotBlank() }}", stringResource(R.string.notes_written)))
                    add(Stat(duration(record.totalSeconds), stringResource(R.string.total_reading_time)))
                    val week = ReadingStats.dailyTime(record.readingSeconds, 7, today).sumOf { it.second.toLong() }
                    add(Stat(duration(week), stringResource(R.string.this_week_stat)))
                }
            }
            StatGrid(stats)
            if (premium) {
                ReadingTime(record, today)
                FavoriteBooks(record, language)
            } else {
                Text(stringResource(R.string.insights_locked), style = MaterialTheme.typography.bodyLarge, color = colors.secondaryText)
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}

private data class Stat(val value: String, val label: String)

/** Two columns on a phone, more where there's room (150 dp each, as iOS). */
@Composable
private fun StatGrid(stats: List<Stat>) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val columns = ((maxWidth + 12.dp) / (162.dp)).toInt().coerceIn(2, 4)
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            stats.chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { StatCard(it, Modifier.weight(1f)) }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
private fun StatCard(stat: Stat, modifier: Modifier) {
    val colors = LocalReaderColors.current
    Column(
        modifier
            .background(colors.surface, RoundedCornerShape(16.dp))
            .padding(14.dp)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            stat.value,
            style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
            color = colors.text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(stat.label, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    val colors = LocalReaderColors.current
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            title,
            style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
            color = colors.text,
            modifier = Modifier.semantics { heading() },
        )
        Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(18.dp)).padding(16.dp)) { content() }
    }
}

/** Minutes a day over the last two weeks, as bars; every other day labelled. */
@Composable
private fun ReadingTime(record: ReadingRecord, today: LocalDate) {
    val colors = LocalReaderColors.current
    val days = ReadingStats.dailyTime(record.readingSeconds, 14, today)
    val total = duration(days.sumOf { it.second.toLong() })
    val summary = stringResource(R.string.reading_time_summary, total)
    val most = (days.maxOf { it.second } / 60f).coerceAtLeast(10f)
    Section(stringResource(R.string.reading_time_two_weeks)) {
        Text(stringResource(R.string.minutes_axis), style = MaterialTheme.typography.labelSmall, color = colors.secondaryText)
        Canvas(Modifier.fillMaxWidth().height(140.dp).padding(top = 6.dp).semantics { contentDescription = summary }) {
            val slot = size.width / days.size
            val bar = slot * 0.6f
            drawLine(colors.separator, Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = 1.dp.toPx())
            days.forEachIndexed { index, (_, seconds) ->
                val height = size.height * (seconds / 60f) / most
                if (height > 0f) {
                    drawRoundRect(
                        colors.accent,
                        topLeft = Offset(index * slot + (slot - bar) / 2, size.height - height),
                        size = Size(bar, height),
                        cornerRadius = CornerRadius(3.dp.toPx()),
                    )
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 4.dp)) {
            days.forEachIndexed { index, (day, _) ->
                Text(
                    if (index % 2 == 1) day.dayOfWeek.getDisplayName(TextStyle.NARROW, Locale.getDefault()) else "",
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.secondaryText,
                    modifier = Modifier.weight(1f),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
            }
        }
    }
}

@Composable
private fun FavoriteBooks(record: ReadingRecord, language: String) {
    val colors = LocalReaderColors.current
    val books = ReadingStats.favoriteBooks(record.chaptersRead)
    if (books.isEmpty()) return
    Section(stringResource(R.string.favorite_books)) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            books.forEach { entry ->
                Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(entry.book.name(language), style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.weight(1f))
                        Text(
                            stringResource(R.string.chapters_of_book, entry.chapters, entry.book.chapterCount),
                            style = MaterialTheme.typography.bodySmall,
                            color = colors.secondaryText,
                        )
                    }
                    LinearProgressIndicator(
                        progress = { entry.chapters.toFloat() / entry.book.chapterCount },
                        color = colors.accent,
                        trackColor = colors.separator,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }
    }
}

/** "12 min" or "3 h 5 min", as iOS. */
@Composable
internal fun duration(seconds: Long): String {
    val (hours, minutes) = ReadingStats.hoursAndMinutes(seconds)
    return if (hours == 0) stringResource(R.string.duration_minutes, minutes) else stringResource(R.string.duration_hours_minutes, hours, minutes)
}
