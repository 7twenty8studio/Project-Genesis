package com.genesis.app.together

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.prayer.JournalBible
import com.genesis.core.cloud.community.ChallengeKind
import com.genesis.core.cloud.community.ChallengeProgress
import com.genesis.core.cloud.community.ChallengeRules
import com.genesis.core.cloud.community.ChallengeStatus
import com.genesis.core.cloud.community.ChallengeStreak
import com.genesis.core.cloud.community.ChallengeSummary
import com.genesis.core.cloud.community.GroupChallenge
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.VerseId
import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

// Group challenges, as GroupChallengesSection, GroupChallengeDetailView and
// ChallengeKindSections on iOS. No rankings: how the group is doing
// together, and how you are.

/** A group's challenges and everyone's progress in them. */
internal data class ChallengeContent(
    val challenges: List<GroupChallenge> = emptyList(),
    val progress: Map<String, List<ChallengeProgress>> = emptyMap(),
    val loaded: Boolean = false,
) {
    fun current(today: LocalDate): List<GroupChallenge> =
        challenges.filter { it.status(today) == ChallengeStatus.RUNNING } +
            challenges.filter { it.status(today) == ChallengeStatus.UPCOMING }.sortedBy { it.start }

    fun finished(today: LocalDate): List<GroupChallenge> = challenges.filter { it.status(today) == ChallengeStatus.FINISHED }
}

internal val ChallengeKind.title: Int
    get() = when (this) {
        ChallengeKind.READING -> R.string.challenge_reading
        ChallengeKind.MEMORISE -> R.string.challenge_memorise
        ChallengeKind.STREAK -> R.string.challenge_streak
        ChallengeKind.PRAYER -> R.string.challenge_prayer
    }

internal val ChallengeKind.summary: Int
    get() = when (this) {
        ChallengeKind.READING -> R.string.challenge_reading_summary
        ChallengeKind.MEMORISE -> R.string.challenge_memorise_summary
        ChallengeKind.STREAK -> R.string.challenge_streak_summary
        ChallengeKind.PRAYER -> R.string.challenge_prayer_summary
    }

internal val ChallengeKind.symbol: String
    get() = when (this) {
        ChallengeKind.READING -> "📖"
        ChallengeKind.MEMORISE -> "💭"
        ChallengeKind.STREAK -> "🔥"
        ChallengeKind.PRAYER -> "🙏"
    }

internal fun mediumDate(date: LocalDate): String = date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))

@Composable
private fun statusText(challenge: GroupChallenge, today: LocalDate): String = when (challenge.status(today)) {
    ChallengeStatus.UPCOMING -> stringResource(R.string.starts_on, mediumDate(challenge.start))
    ChallengeStatus.RUNNING -> stringResource(R.string.day_of_days, challenge.currentDay(today), challenge.days)
    ChallengeStatus.FINISHED -> challenge.endedAt?.let { ended ->
        val day = runCatching { LocalDate.parse(ended.take(10)) }.getOrNull()
        stringResource(R.string.ended_early, day?.let(::mediumDate).orEmpty())
    } ?: stringResource(R.string.finished_on, mediumDate(challenge.end))
}

@Composable
private fun stillGoing(summary: ChallengeSummary): String =
    if (summary.memberCount == 1) stringResource(R.string.still_going_one, summary.stillGoing) else stringResource(R.string.still_going, summary.stillGoing, summary.memberCount)

@Composable
private fun rowProgress(challenge: GroupChallenge, summary: ChallengeSummary): String = when (challenge.kind) {
    ChallengeKind.READING -> stringResource(R.string.read_chapters_progress, summary.myDone, summary.itemCount)
    ChallengeKind.MEMORISE -> stringResource(if (summary.myDone > 0) R.string.learned_it_you else R.string.still_learning)
    ChallengeKind.STREAK, ChallengeKind.PRAYER -> stillGoing(summary)
}

@Composable
private fun Bar(fraction: Float) {
    val colors = LocalReaderColors.current
    LinearProgressIndicator(
        progress = { fraction },
        color = colors.accent,
        trackColor = colors.separator,
        drawStopIndicator = {},
        modifier = Modifier.fillMaxWidth().height(5.dp).clip(CircleShape),
    )
}

/** The Today tab's Challenges card: what's running or about to start, finished ones, and a new one for leaders. */
@Composable
internal fun ChallengesCard(
    content: ChallengeContent,
    me: String?,
    canManage: Boolean,
    onOpen: (String) -> Unit,
    onFinished: () -> Unit,
    onNew: () -> Unit,
) {
    val colors = LocalReaderColors.current
    val today = LocalDate.now()
    val current = content.current(today)
    Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(14.dp)).padding(vertical = 12.dp)) {
        Text(stringResource(R.string.challenges).uppercase(), style = MaterialTheme.typography.labelMedium, color = colors.secondaryText, modifier = Modifier.padding(horizontal = 16.dp))
        if (current.isEmpty() && content.loaded) {
            Text(
                stringResource(if (canManage) R.string.start_challenge_prompt else R.string.no_challenges),
                style = MaterialTheme.typography.bodyMedium,
                color = colors.secondaryText,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
        current.forEach { challenge ->
            val summary = ChallengeSummary.of(challenge, content.progress[challenge.id].orEmpty(), me, today)
            Row(Modifier.fillMaxWidth().clickable { onOpen(challenge.id) }.padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(challenge.kind.symbol)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(challenge.title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = colors.text)
                    Text(statusText(challenge, today), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                    if (challenge.status(today) == ChallengeStatus.RUNNING) {
                        Text(rowProgress(challenge, summary), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                        if (challenge.kind == ChallengeKind.READING) Bar(summary.myFraction)
                    }
                }
            }
        }
        if (content.finished(today).isNotEmpty()) {
            TextButton(onClick = onFinished, modifier = Modifier.padding(horizontal = 4.dp)) { Text(stringResource(R.string.finished_challenges), color = colors.accent) }
        }
        if (canManage) {
            val canStart = current.size < ChallengeRules.MAXIMUM_RUNNING
            TextButton(onClick = onNew, enabled = canStart, modifier = Modifier.padding(horizontal = 4.dp)) {
                Text("+ " + stringResource(R.string.new_challenge), color = if (canStart) colors.accent else colors.secondaryText, fontWeight = FontWeight.SemiBold)
            }
            if (!canStart) Text(stringResource(R.string.five_challenges), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText, modifier = Modifier.padding(horizontal = 16.dp))
        }
    }
}

/** Finished challenges, newest first. */
@Composable
internal fun FinishedChallenges(content: ChallengeContent, onOpen: (String) -> Unit) {
    val colors = LocalReaderColors.current
    val today = LocalDate.now()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        Text(stringResource(R.string.finished_challenges), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text, modifier = Modifier.padding(bottom = 8.dp))
        content.finished(today).forEach { challenge ->
            Row(Modifier.fillMaxWidth().clickable { onOpen(challenge.id) }.padding(vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(challenge.kind.symbol)
                Column {
                    Text(challenge.title, style = MaterialTheme.typography.bodyLarge, color = colors.text)
                    Text(statusText(challenge, today), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                }
            }
            HorizontalDivider(color = colors.separator)
        }
    }
}

@Composable
private fun Section(header: String?, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    val colors = LocalReaderColors.current
    Column(Modifier.fillMaxWidth().padding(bottom = 14.dp)) {
        header?.let { Text(it.uppercase(), style = MaterialTheme.typography.labelMedium, color = colors.secondaryText, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp)) }
        Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(14.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
        footer?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp)) }
    }
}

/** A tick that reads as a button: filled when done. */
@Composable
private fun Tick(title: String, done: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Text(
        (if (done) "✓ " else "") + title,
        style = MaterialTheme.typography.labelLarge,
        color = when {
            done -> colors.background
            enabled -> colors.accent
            else -> colors.secondaryText
        },
        modifier = Modifier.clip(CircleShape)
            .background(if (done) colors.accent else colors.accent.copy(alpha = 0.12f))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
    )
}

/**
 * One challenge: what it asks, your progress and the group's, members, and
 * (for owners and moderators) a way to end it.
 */
@Composable
internal fun ChallengeScreen(
    challenge: GroupChallenge?,
    rows: List<ChallengeProgress>,
    me: String?,
    canManage: Boolean,
    bible: JournalBible,
    onTick: (Boolean, Int) -> Unit,
    onRead: (ChapterId) -> Unit,
    onPrayers: () -> Unit,
    onEnd: () -> Unit,
) {
    val colors = LocalReaderColors.current
    if (challenge == null) {
        Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(stringResource(R.string.challenge_ended), style = MaterialTheme.typography.titleMedium, color = colors.text)
            Text(stringResource(R.string.this_challenge_ended), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, textAlign = TextAlign.Center)
        }
        return
    }
    val today = LocalDate.now()
    val status = challenge.status(today)
    val summary = ChallengeSummary.of(challenge, rows, me, today)
    var confirmsEnd by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        Section(header = null) {
            Text("${challenge.kind.symbol}  " + stringResource(challenge.kind.title), style = MaterialTheme.typography.labelLarge, color = colors.accent)
            Text(challenge.title, style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold), color = colors.text, modifier = Modifier.semantics { heading() })
            if (challenge.details.isNotBlank()) Text(challenge.details, style = MaterialTheme.typography.bodyMedium, color = colors.text)
            val dates = if (challenge.days == 1) mediumDate(challenge.start) else "${mediumDate(challenge.start)} – ${mediumDate(challenge.end)}"
            Text("$dates · ${statusText(challenge, today)}", style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
            if (status == ChallengeStatus.FINISHED) {
                Text(finishedSummary(challenge, summary), style = MaterialTheme.typography.bodyMedium, color = colors.text)
            } else if (summary.memberCount > 0) {
                Bar(summary.groupFraction)
                val percent = NumberFormat.getPercentInstance().format(summary.groupFraction.toDouble())
                Text(stringResource(R.string.group_percent, percent), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
            }
            if (canManage && status != ChallengeStatus.FINISHED) {
                TextButton(onClick = { confirmsEnd = true }) { Text(stringResource(R.string.end_challenge), color = colors.accent) }
            }
        }
        when (challenge.kind) {
            ChallengeKind.READING -> ReadingSections(challenge, summary, bible.language, today, onTick, onRead)
            ChallengeKind.MEMORISE -> MemoriseSections(challenge, summary, bible, today, onTick)
            ChallengeKind.STREAK, ChallengeKind.PRAYER -> DailySections(challenge, summary, status, today, onTick, onPrayers)
        }
        MembersSection(challenge, rows, me, summary)
    }
    if (confirmsEnd) {
        Confirm(
            title = stringResource(R.string.end_challenge_question),
            message = stringResource(R.string.end_challenge_message),
            action = stringResource(R.string.end_challenge),
            onConfirm = onEnd,
            onDismiss = { confirmsEnd = false },
        )
    }
}

@Composable
private fun finishedSummary(challenge: GroupChallenge, summary: ChallengeSummary): String = when (challenge.kind) {
    ChallengeKind.READING -> stringResource(R.string.finished_reading, summary.myDone, summary.itemCount)
    ChallengeKind.MEMORISE -> stringResource(if (summary.myDone > 0) R.string.finished_memorise_yes else R.string.finished_memorise_no)
    ChallengeKind.STREAK -> stringResource(R.string.finished_streak, summary.myDone, summary.itemCount)
    ChallengeKind.PRAYER -> stringResource(R.string.finished_prayer, summary.myDone, summary.itemCount)
}

@Composable
private fun ReadingSections(challenge: GroupChallenge, summary: ChallengeSummary, language: String, today: LocalDate, onTick: (Boolean, Int) -> Unit, onRead: (ChapterId) -> Unit) {
    val colors = LocalReaderColors.current
    Section(header = stringResource(R.string.your_progress)) {
        Bar(summary.myFraction)
        Text(rowProgress(challenge, summary), style = MaterialTheme.typography.bodyMedium, color = colors.text)
    }
    Section(header = stringResource(R.string.chapters_header), footer = stringResource(R.string.tick_chapters)) {
        challenge.chapters.forEach { raw ->
            val chapter = ChapterId(raw / 1_000, raw % 1_000)
            val ticked = raw in summary.myItems
            val enabled = challenge.canTick(raw, today)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(26.dp).clip(CircleShape)
                        .background(if (ticked) colors.accent else colors.background)
                        .border(1.5.dp, if (ticked) colors.accent else colors.separator, CircleShape)
                        .clickable(enabled = enabled) { onTick(!ticked, raw) },
                    contentAlignment = Alignment.Center,
                ) { if (ticked) Text("✓", color = colors.background, style = MaterialTheme.typography.labelMedium) }
                Spacer(Modifier.size(12.dp))
                Text(
                    chapter.description(language),
                    style = MaterialTheme.typography.bodyLarge,
                    color = colors.text,
                    textDecoration = if (ticked) TextDecoration.LineThrough else null,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = { onRead(chapter) }) { Text(stringResource(R.string.read_action), color = colors.accent) }
            }
        }
    }
}

@Composable
private fun MemoriseSections(challenge: GroupChallenge, summary: ChallengeSummary, bible: JournalBible, today: LocalDate, onTick: (Boolean, Int) -> Unit) {
    val colors = LocalReaderColors.current
    val start = challenge.verseStart?.let(::VerseId)
    val end = (challenge.verseEnd ?: challenge.verseStart)?.let(::VerseId)
    // The passage's words, exactly as the Bible being read has them.
    val text by produceState<String?>(null, start, end, bible.key) {
        if (start == null || end == null || start.book != end.book || start.chapter != end.chapter) return@produceState
        val ids = (start.verse..end.verse).map { VerseId(start.book, start.chapter, it) }
        val verses = bible.verses(ids)
        value = ids.mapNotNull { verses[it]?.plainText }.joinToString(" ").ifBlank { null }
    }
    Section(header = stringResource(R.string.the_passage)) {
        if (start != null && end != null) {
            val reference = if (start == end) "${ChapterId(start.book, start.chapter).description(bible.language)}:${start.verse}"
            else "${ChapterId(start.book, start.chapter).description(bible.language)}:${start.verse}–${end.verse}"
            Text(reference, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
        }
        val words = text
        if (words != null) {
            Text(words, style = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Serif), color = colors.text)
            Text(bible.abbreviation, style = MaterialTheme.typography.labelMedium, color = colors.secondaryText)
        } else {
            Text(stringResource(R.string.passage_missing), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
        }
    }
    Section(header = null, footer = stringResource(R.string.tick_learned)) {
        val learned = ChallengeRules.LEARNED_ITEM in summary.myItems
        Tick(stringResource(if (learned) R.string.ive_learned_it else R.string.mark_as_learned), learned, challenge.canTick(ChallengeRules.LEARNED_ITEM, today)) {
            onTick(!learned, ChallengeRules.LEARNED_ITEM)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DailySections(challenge: GroupChallenge, summary: ChallengeSummary, status: ChallengeStatus, today: LocalDate, onTick: (Boolean, Int) -> Unit, onPrayers: () -> Unit) {
    val colors = LocalReaderColors.current
    val day = challenge.dayIndex(today)
    Section(header = stringResource(R.string.group_today)) {
        when (status) {
            ChallengeStatus.RUNNING -> {
                val done = day in summary.myItems
                val title = when {
                    challenge.kind == ChallengeKind.PRAYER && done -> R.string.challenge_prayed_today
                    challenge.kind == ChallengeKind.PRAYER -> R.string.challenge_i_prayed_today
                    done -> R.string.read_today
                    else -> R.string.i_read_today
                }
                Tick(stringResource(title), done, challenge.canTick(day, today)) { onTick(!done, day) }
            }
            ChallengeStatus.UPCOMING -> Text(stringResource(R.string.tick_once_begins), color = colors.secondaryText)
            ChallengeStatus.FINISHED -> Text(stringResource(R.string.challenge_has_finished), color = colors.secondaryText)
        }
        val streak = summary.myStreak
        if (streak > 0) Text("🔥 " + if (streak == 1) stringResource(R.string.one_day_row) else stringResource(R.string.days_row, streak), color = colors.text)
        Text(stillGoing(summary), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
    }
    Section(header = stringResource(R.string.every_day)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp), maxItemsInEachRow = 7) {
            (1..challenge.days).forEach { number ->
                val ticked = number in summary.myItems
                val enabled = challenge.canTick(number, today)
                Box(
                    Modifier.size(36.dp).clip(CircleShape)
                        .background(if (ticked) colors.accent else colors.background)
                        .border(if (number == day) 2.dp else 1.dp, if (number == day || ticked) colors.accent else colors.separator, CircleShape)
                        .clickable(enabled = enabled) { onTick(!ticked, number) },
                    contentAlignment = Alignment.Center,
                ) {
                    Text("$number", style = MaterialTheme.typography.labelMedium, color = if (ticked) colors.background else if (enabled) colors.text else colors.secondaryText)
                }
            }
        }
    }
    if (challenge.kind == ChallengeKind.PRAYER) {
        TextButton(onClick = onPrayers) { Text("🙏 " + stringResource(R.string.groups_prayer_requests), color = colors.accent) }
    }
}

/** Everyone, in name order (you first), with their progress. Never ranked. */
@Composable
private fun MembersSection(challenge: GroupChallenge, rows: List<ChallengeProgress>, me: String?, summary: ChallengeSummary) {
    val colors = LocalReaderColors.current
    fun isMe(row: ChallengeProgress) = me != null && row.userId.equals(me, ignoreCase = true)
    val sorted = rows.sortedWith(compareBy<ChallengeProgress> { !isMe(it) }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.displayName })
    Section(header = stringResource(R.string.members), footer = stringResource(R.string.no_rankings)) {
        if (sorted.isEmpty()) Text(stringResource(R.string.no_one_joined), color = colors.secondaryText)
        sorted.forEach { row ->
            val count = minOf(row.done, challenge.itemCount)
            val ticked = row.items.orEmpty().toSet()
            val done = when (challenge.kind) {
                ChallengeKind.READING, ChallengeKind.MEMORISE -> row.done >= challenge.itemCount
                else -> summary.day in ticked
            }
            val detail = when (challenge.kind) {
                ChallengeKind.READING -> stringResource(R.string.chapters_of, count, challenge.itemCount)
                ChallengeKind.MEMORISE -> stringResource(if (count > 0) R.string.learned_it else R.string.still_learning)
                else -> if (ChallengeStreak.isAlive(ticked, summary.day)) stringResource(R.string.still_going_label) else stringResource(R.string.days_of, count, challenge.itemCount)
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(if (isMe(row)) stringResource(R.string.you) else row.displayName, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = colors.text)
                    if (done) Text(" ✓", color = colors.accent)
                    Spacer(Modifier.weight(1f))
                    Text(detail, style = MaterialTheme.typography.labelMedium, color = colors.secondaryText)
                }
                if (challenge.kind == ChallengeKind.READING) Bar(ChallengeSummary.fraction(row.done, challenge.itemCount))
            }
        }
    }
}

/** Loads a group's challenges and the progress of those that aren't finished. */
internal suspend fun loadChallenges(api: com.genesis.core.cloud.community.ChallengeApi, group: String): ChallengeContent {
    val today = LocalDate.now()
    val challenges = api.challenges(group)
    val progress = challenges.filter { it.status(today) != ChallengeStatus.UPCOMING }.associate { it.id to api.progress(it.id) }
    return ChallengeContent(challenges, progress, loaded = true)
}

