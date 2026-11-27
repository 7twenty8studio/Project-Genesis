package com.genesis.app.prayer

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.edit
import com.genesis.app.R
import com.genesis.app.settings.Header
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.prayer.Prayer
import com.genesis.core.domain.prayer.PrayerStatistics
import com.genesis.core.domain.prayer.PrayerStreak
import com.genesis.core.domain.prayer.PrayerTimeline
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private const val LOG_KEY = "prayer.prayedDays"

/**
 * "Your Prayer Life", as PrayerLifeSection on iOS: a gentle streak with
 * "I Prayed Today" (kept on this device, as on iPhone) and a few numbers.
 * No guilt: a missed day simply starts again.
 */
@Composable
internal fun PrayerLife(prayers: List<Prayer>) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("prayer", Context.MODE_PRIVATE) }
    var log by remember { mutableStateOf(prefs.getString(LOG_KEY, "").orEmpty()) }
    var details by rememberSaveable { mutableStateOf(false) }
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    val days = PrayerStreak.days(PrayerStreak.decodeLog(log), prayers, zone)
    val streak = PrayerStreak.length(days, today)
    val prayedToday = today in days
    val stats = PrayerStatistics.of(prayers)

    Header(stringResource(R.string.your_prayer_life))
    Column(
        Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(14.dp)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                when {
                    streak >= 2 -> stringResource(R.string.prayer_streak, streak)
                    prayedToday || streak == 1 -> stringResource(R.string.prayed_today_fresh)
                    else -> stringResource(R.string.quiet_moment)
                },
                style = MaterialTheme.typography.bodyMedium,
                color = colors.text,
                modifier = Modifier.weight(1f).padding(end = 8.dp),
            )
            OutlinedButton(
                onClick = {
                    log = PrayerStreak.recording(today, log)
                    prefs.edit { putString(LOG_KEY, log) }
                },
                enabled = !prayedToday,
            ) {
                Text(stringResource(if (prayedToday) R.string.prayed else R.string.i_prayed_today), color = if (prayedToday) colors.secondaryText else colors.accent)
            }
        }
        if (stats.total > 0) {
            Row(Modifier.semantics(mergeDescendants = true) {}) {
                Number("${stats.total}", stringResource(R.string.stat_requests))
                Number("${stats.answered}", stringResource(R.string.stat_answered))
                Number("${stats.answeredPercent}%", stringResource(R.string.stat_answered_share))
                Number("${stats.active}", stringResource(R.string.stat_still_praying))
            }
            Text(
                stringResource(R.string.more_about_prayers) + if (details) "  ▴" else "  ▾",
                style = MaterialTheme.typography.bodyMedium,
                color = colors.accent,
                modifier = Modifier.clickable { details = !details },
            )
            if (details) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    stats.byCategory.forEach { (category, count) ->
                        Row {
                            Text(stringResource(category.title), style = MaterialTheme.typography.bodyMedium, color = colors.text, modifier = Modifier.weight(1f))
                            Text("$count", style = MaterialTheme.typography.bodyMedium, color = colors.text)
                        }
                    }
                    Text(
                        when (val wait = stats.averageAnswerDays) {
                            null -> stringResource(R.string.answer_wait_none)
                            0 -> stringResource(R.string.answer_wait_day)
                            1 -> stringResource(R.string.answer_wait_one)
                            else -> stringResource(R.string.answer_wait_days, wait)
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.secondaryText,
                    )
                }
            }
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.Number(value: String, label: String) {
    val colors = LocalReaderColors.current
    Column(Modifier.weight(1f)) {
        Text(value, style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold), color = colors.text)
        Text(label, style = MaterialTheme.typography.labelSmall, color = colors.secondaryText, maxLines = 2)
    }
}

/** The journal by month, as PrayerTimelineSections on iOS: each prayer asked and, once answered, its answer. */
internal fun androidx.compose.foundation.lazy.LazyListScope.timeline(prayers: List<Prayer>, onOpen: (String) -> Unit) {
    val months = PrayerTimeline.months(prayers, ZoneId.systemDefault())
    if (months.isEmpty()) {
        item { EmptyJournal(R.string.story_with_god, R.string.story_with_god_message) }
        return
    }
    for (month in months) {
        item(key = "m-${month.month}") {
            val pattern = android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "MMMMyyyy")
            Header(DateTimeFormatter.ofPattern(pattern).format(month.month))
        }
        for (entry in month.entries) {
            item(key = "${entry.prayer.id}-${entry.kind}") { TimelineRow(entry) { onOpen(entry.prayer.id) } }
        }
    }
}

@Composable
private fun TimelineRow(entry: PrayerTimeline.Entry, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    val prayer = entry.prayer
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable(onClick = onClick).background(colors.surface).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(if (entry.kind == PrayerTimeline.Kind.ANSWERED) "✓" else "•", color = colors.accent, style = MaterialTheme.typography.titleMedium)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            val asked = shortDate(prayer.createdAt)
            Text(
                if (entry.kind == PrayerTimeline.Kind.ANSWERED) {
                    stringResource(R.string.answered_asked, shortDate(entry.date), asked)
                } else {
                    stringResource(R.string.asked_category, asked, stringResource(prayer.category.title))
                },
                style = MaterialTheme.typography.labelMedium,
                color = colors.secondaryText,
            )
            Text(
                prayer.displayTitle ?: stringResource(R.string.prayer),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = colors.text,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            val note = prayer.answerNote
            if (entry.kind == PrayerTimeline.Kind.ANSWERED && !note.isNullOrBlank()) {
                Text(note, style = MaterialTheme.typography.bodyMedium, fontStyle = FontStyle.Italic, color = colors.secondaryText, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}
