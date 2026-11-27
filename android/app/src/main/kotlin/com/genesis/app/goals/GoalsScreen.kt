package com.genesis.app.goals

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.Footer
import com.genesis.app.settings.Group
import com.genesis.app.settings.Header
import com.genesis.app.settings.SettingSwitch
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.goals.GoalProgress
import com.genesis.core.domain.goals.Milestone
import com.genesis.core.domain.goals.Milestones
import com.genesis.core.domain.goals.ReadingGoal
import com.genesis.core.domain.goals.ReadingStreak
import com.genesis.core.domain.insights.ReadingStats

/** Today's numbers for milestones: reading, answered prayers and (with Premium) passages by heart. */
@Composable
internal fun rememberMilestoneStats(): Milestones.Stats {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val record by app.progress.record.collectAsStateWithLifecycle()
    val prayers by app.userData.prayers.all.collectAsStateWithLifecycle()
    val memory by app.userData.memory.all.collectAsStateWithLifecycle()
    return Milestones.Stats(
        longestStreak = maxOf(ReadingStreak.longest(record.readingDays), app.progress.streak(days = record.readingDays)),
        chapters = record.chaptersRead.size,
        books = ReadingStats.booksCompleted(record.chaptersRead),
        answeredPrayers = prayers.count { it.isAnswered },
        memorised = if (Entitlements.isPremium) memory.count { it.mastery == com.genesis.core.domain.memorise.MemoryMastery.MEMORISED } else 0,
    )
}

/** Today's progress toward the daily goal, followed as reading goes on. */
@Composable
internal fun rememberGoalToday(goal: ReadingGoal): GoalProgress? {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val record by app.progress.record.collectAsStateWithLifecycle()
    return remember(goal, record) { goal.progress(app.progress.chaptersRead(), app.progress.secondsRead()) }
}

@Composable
internal fun ReadingGoal.title(): String = when (this) {
    ReadingGoal.NONE -> stringResource(R.string.goal_none)
    ReadingGoal.ONE_CHAPTER -> stringResource(R.string.goal_one_chapter)
    ReadingGoal.THREE_CHAPTERS -> stringResource(R.string.goal_three_chapters)
    ReadingGoal.FIVE_MINUTES -> stringResource(R.string.goal_five_minutes)
    ReadingGoal.TEN_MINUTES -> stringResource(R.string.goal_ten_minutes)
    ReadingGoal.TWENTY_MINUTES -> stringResource(R.string.goal_twenty_minutes)
}

/** "1 of 3 chapters", "4 of 10 minutes". */
@Composable
internal fun GoalProgress.label(): String =
    if (goal.unit == ReadingGoal.Unit.CHAPTERS) stringResource(R.string.goal_chapters_progress, done, target)
    else stringResource(R.string.goal_minutes_progress, done, target)

@Composable
internal fun Milestone.title(): String = when (kind) {
    Milestone.Kind.STREAK -> stringResource(R.string.milestone_streak, count)
    Milestone.Kind.CHAPTERS -> if (count == Milestones.WHOLE_BIBLE_CHAPTERS) stringResource(R.string.milestone_every_chapter) else stringResource(R.string.milestone_chapters, count)
    Milestone.Kind.BOOKS -> when (count) {
        1 -> stringResource(R.string.milestone_first_book)
        66 -> stringResource(R.string.milestone_all_books)
        else -> stringResource(R.string.milestone_books, count)
    }
    Milestone.Kind.PRAYERS -> if (count == 1) stringResource(R.string.milestone_first_prayer) else stringResource(R.string.milestone_prayers, count)
    Milestone.Kind.MEMORISED -> if (count == 1) stringResource(R.string.milestone_first_memorised) else stringResource(R.string.milestone_memorised, count)
}

@Composable
internal fun Milestone.detail(): String = stringResource(
    when (kind) {
        Milestone.Kind.STREAK -> R.string.milestone_streak_detail
        Milestone.Kind.CHAPTERS -> R.string.milestone_chapters_detail
        Milestone.Kind.BOOKS -> R.string.milestone_books_detail
        Milestone.Kind.PRAYERS -> R.string.milestone_prayers_detail
        Milestone.Kind.MEMORISED -> R.string.milestone_memorised_detail
    },
)

internal val Milestone.symbol: String
    get() = when (kind) {
        Milestone.Kind.STREAK -> "🔥"
        Milestone.Kind.CHAPTERS -> "📖"
        Milestone.Kind.BOOKS -> "📚"
        Milestone.Kind.PRAYERS -> "🙏"
        Milestone.Kind.MEMORISED -> "💡"
    }

/**
 * Goals & Streaks, as GoalSettingsView on iOS: the daily goal, the streak
 * shield, and the milestones reached and still ahead. From Settings and
 * from the goal card on Home.
 */
@Composable
fun GoalsScreen(onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val app = LocalContext.current.applicationContext as VerselyApplication
    val goals by app.goals.state.collectAsStateWithLifecycle()
    val today = rememberGoalToday(goals.goal)
    val stats = rememberMilestoneStats()

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.goals_and_streaks),
                style = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp).widthIn(max = 720.dp)) {
            Header(stringResource(R.string.daily_goal))
            Group {
                ReadingGoal.entries.forEachIndexed { index, goal ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .selectable(selected = goals.goal == goal, role = Role.RadioButton) { app.goals.setGoal(goal) }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(goal.title(), style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.weight(1f))
                        if (goals.goal == goal) Text("✓", color = colors.accent, fontWeight = FontWeight.SemiBold)
                    }
                    HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                }
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp)) {
                    Text(stringResource(R.string.group_today), style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.weight(1f))
                    Text(
                        when {
                            today == null -> "–"
                            today.isMet -> stringResource(R.string.goal_reached)
                            else -> today.label()
                        },
                        color = if (today?.isMet == true) colors.accent else colors.secondaryText,
                    )
                }
            }
            Footer(stringResource(R.string.goal_footer))

            Header(stringResource(R.string.streak_shield))
            Group {
                SettingSwitch(stringResource(R.string.streak_shield), goals.usesStreakShields, app.goals::setStreakShields)
                if (goals.usesStreakShields) {
                    HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                    val record by app.progress.record.collectAsStateWithLifecycle()
                    val ready = remember(record, goals) { app.progress.streakShieldReady() }
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp)) {
                        Text(stringResource(R.string.this_week), style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.weight(1f))
                        Text(stringResource(if (ready) R.string.shield_ready else R.string.shield_used), color = colors.secondaryText)
                    }
                }
            }
            Footer(stringResource(R.string.streak_shield_footer))

            val next = Milestones.next(stats).filter { it.kind != Milestone.Kind.MEMORISED || Entitlements.isPremium }
            if (next.isNotEmpty()) {
                Header(stringResource(R.string.next_milestones))
                Group { MilestoneRows(next, earned = false) }
            }
            Header(stringResource(R.string.milestones_reached))
            val earned = Milestones.earned(stats).reversed()
            Group {
                if (earned.isEmpty()) {
                    Text(stringResource(R.string.first_milestone_hint), color = colors.secondaryText, modifier = Modifier.padding(16.dp))
                } else {
                    MilestoneRows(earned, earned = true)
                }
            }
            Spacer(Modifier.size(32.dp))
        }
    }
}

@Composable
private fun MilestoneRows(milestones: List<Milestone>, earned: Boolean) {
    val colors = LocalReaderColors.current
    milestones.forEachIndexed { index, milestone ->
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(milestone.symbol, modifier = Modifier.clearAndSetSemantics {}, color = colors.text.copy(alpha = if (earned) 1f else 0.45f))
            Text(milestone.title(), style = MaterialTheme.typography.bodyLarge, color = if (earned) colors.text else colors.secondaryText)
        }
        if (index < milestones.lastIndex) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
    }
}

/** Home: today's progress toward the goal and the streak shield, or an invitation to set a goal. Opens Goals & Streaks. */
@Composable
fun GoalHomeCard(onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val app = LocalContext.current.applicationContext as VerselyApplication
    val goals by app.goals.state.collectAsStateWithLifecycle()
    val today = rememberGoalToday(goals.goal)
    val record by app.progress.record.collectAsStateWithLifecycle()
    val shieldReady = remember(record, goals) { app.progress.streakShieldReady() }
    val title = when {
        today == null -> stringResource(R.string.set_daily_goal)
        today.isMet -> stringResource(R.string.todays_goal_reached)
        else -> stringResource(R.string.todays_goal)
    }
    val detail = if (today == null) stringResource(R.string.set_daily_goal_detail) else {
        val line = if (today.isMet) goals.goal.title() else today.label()
        if (!goals.usesStreakShields) line
        else stringResource(R.string.goal_and_shield, line, stringResource(if (shieldReady) R.string.streak_shield_ready else R.string.streak_shield_used_week))
    }
    Row(
        modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(18.dp)).clickable(onClick = onOpen).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        val fraction = today?.fraction?.toFloat() ?: 0f
        val track = colors.secondaryText.copy(alpha = 0.2f)
        val accent = colors.accent
        Box(Modifier.size(40.dp).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
            Canvas(Modifier.size(40.dp)) {
                val stroke = 5.dp.toPx()
                val inset = stroke / 2
                val arc = Size(size.width - stroke, size.height - stroke)
                drawArc(track, 0f, 360f, false, Offset(inset, inset), arc, style = Stroke(stroke))
                if (fraction > 0f) drawArc(accent, -90f, 360f * fraction, false, Offset(inset, inset), arc, style = Stroke(stroke, cap = StrokeCap.Round))
            }
            Text(if (today?.isMet == true) "✓" else "◎", color = colors.accent, fontWeight = FontWeight.SemiBold)
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
            Text(detail, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
        }
        Text("›", style = MaterialTheme.typography.titleLarge, color = colors.secondaryText)
    }
}

/**
 * Home: a milestone just reached, shown once ("30 days in a row"). The
 * first look marks what was already reached quietly; after that, one at a
 * time, the next after each is dismissed.
 */
@Composable
fun MilestoneBanner(modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val app = LocalContext.current.applicationContext as VerselyApplication
    val goals by app.goals.state.collectAsStateWithLifecycle()
    val stats = rememberMilestoneStats()
    var showing by remember { mutableStateOf<Milestone?>(null) }
    LaunchedEffect(stats, goals.celebrated, showing) {
        val result = Milestones.toCelebrate(stats, goals.celebrated, goals.hasCelebratedAny)
        if (!goals.hasCelebratedAny || result.markQuietly.isNotEmpty()) app.goals.markCelebrated(result.markQuietly)
        if (showing == null) showing = result.show
    }
    val milestone = showing ?: return
    Row(
        modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(18.dp)).padding(start = 16.dp, top = 16.dp, bottom = 16.dp, end = 4.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(milestone.symbol, style = MaterialTheme.typography.headlineSmall, modifier = Modifier.clearAndSetSemantics {})
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(stringResource(R.string.milestone).uppercase(), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.accent)
            Text(milestone.title(), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
            Text(milestone.detail(), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
        }
        val dismiss = stringResource(R.string.dismiss)
        TextButton(
            onClick = {
                app.goals.markCelebrated(listOf(milestone.id))
                showing = null
            },
            modifier = Modifier.semantics { contentDescription = dismiss },
        ) { Text("✕", color = colors.secondaryText) }
    }
}
