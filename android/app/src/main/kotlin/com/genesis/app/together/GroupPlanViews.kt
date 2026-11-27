package com.genesis.app.together

import android.icu.text.ListFormatter
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.plans.appLanguage
import com.genesis.core.cloud.community.GroupMember
import com.genesis.core.cloud.community.GroupPost
import com.genesis.core.cloud.community.GroupSummary
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.plans.GroupPlan
import com.genesis.core.domain.plans.PlanDay
import com.genesis.core.domain.plans.ReadingPlan
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

// The group's plan read together, as GroupDetailView's Today tab and
// GroupProgressViews.swift on iOS: today's reading, who has read it, each
// member's progress, and every day with its own discussion.

@Composable
private fun Card(content: @Composable () -> Unit) {
    val colors = LocalReaderColors.current
    Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(14.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { content() }
}

@Composable
private fun Caption(text: String) {
    Text(text.uppercase(), style = MaterialTheme.typography.labelMedium, color = LocalReaderColors.current.secondaryText)
}

/** Read (opens the reader) and Mark as read / Done. */
@Composable
private fun ReadingActions(planDay: PlanDay, done: Boolean, onRead: (ChapterId) -> Unit, onSetRead: (Boolean) -> Unit) {
    val colors = LocalReaderColors.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        planDay.spans.firstOrNull()?.let { span ->
            Button(onClick = { onRead(span.first) }, colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.background)) {
                Text(stringResource(R.string.read_action))
            }
        }
        Spacer(Modifier.weight(1f))
        Text(
            (if (done) "✓ " else "") + stringResource(if (done) R.string.done else R.string.mark_as_read),
            style = MaterialTheme.typography.labelLarge,
            color = if (done) colors.background else colors.accent,
            modifier = Modifier.clip(CircleShape)
                .background(if (done) colors.accent else colors.accent.copy(alpha = 0.12f))
                .clickable { onSetRead(!done) }
                .padding(horizontal = 14.dp, vertical = 8.dp),
        )
    }
}

/** Today's reading in the group's plan, or when it starts. */
@Composable
internal fun TodayCard(group: GroupSummary, plan: ReadingPlan, today: Int, content: GroupContent, memberCount: Int, onRead: (ChapterId) -> Unit, onSetRead: (Boolean) -> Unit) {
    val colors = LocalReaderColors.current
    val language = appLanguage()
    val title = groupPlanTitle(group, plan)
    Card {
        Caption(if (today == 0) stringResource(R.string.reading_plan_header) else stringResource(R.string.day_of_days, today, plan.dayCount))
        if (today == 0) {
            val start = GroupPlan.startDate(group.planStart)
            Text(
                if (start != null) stringResource(R.string.plan_starts_on, title, start.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))) else stringResource(R.string.plan_starts_soon, title),
                style = MaterialTheme.typography.bodyLarge,
                color = colors.text,
            )
            return@Card
        }
        val planDay = plan.days[today - 1]
        Text(title, style = MaterialTheme.typography.labelLarge, color = colors.secondaryText)
        Text(planDay.title(language), style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold), color = colors.text)
        ReadingActions(planDay, done = today in content.myDays, onRead = onRead, onSetRead = onSetRead)
        val count = content.readers[today]?.size ?: 0
        Text(
            if (memberCount == 1) stringResource(R.string.one_member_read_today, count) else stringResource(R.string.members_read_today, count, memberCount),
            style = MaterialTheme.typography.bodySmall,
            color = colors.secondaryText,
        )
    }
}

/** Everyone's progress: a bar each, furthest along first, ticked if read today. */
@Composable
internal fun ProgressCard(plan: ReadingPlan, today: Int, content: GroupContent, members: List<GroupMember>, isMine: (String) -> Boolean, onAllDays: () -> Unit) {
    val colors = LocalReaderColors.current
    val readToday = content.readers[today].orEmpty()
    val rows = members
        .map { it to (content.progress[it.userId.lowercase()]?.daysDone ?: 0) }
        .sortedWith(compareByDescending<Pair<GroupMember, Int>> { it.second }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.first.displayName })
    Card {
        Caption(stringResource(R.string.progress))
        rows.forEach { (member, done) ->
            val readTodayLabel = stringResource(R.string.read_today)
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(if (isMine(member.userId)) stringResource(R.string.you) else member.displayName, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = colors.text, maxLines = 1)
                    if (member.userId.lowercase() in readToday) {
                        Text(" ✓", color = colors.accent, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.semantics { contentDescription = readTodayLabel })
                    }
                    Spacer(Modifier.weight(1f))
                    Text(stringResource(R.string.days_of_days, done, plan.dayCount), style = MaterialTheme.typography.labelMedium, color = colors.secondaryText)
                }
                LinearProgressIndicator(
                    progress = { if (plan.dayCount > 0) (done.toFloat() / plan.dayCount).coerceIn(0f, 1f) else 0f },
                    color = colors.accent,
                    trackColor = colors.separator,
                    drawStopIndicator = {},
                    modifier = Modifier.fillMaxWidth().height(5.dp).clip(CircleShape),
                )
            }
        }
        TextButton(onClick = onAllDays) { Text(stringResource(R.string.every_day_of_plan), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        Text(stringResource(R.string.progress_footer), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
    }
}

/** Every day of the plan, ticked when read, with its comment count. */
@Composable
internal fun PlanDaysView(group: GroupSummary, plan: ReadingPlan, today: Int, content: GroupContent, countFor: (Int) -> Int, onOpen: (Int) -> Unit) {
    val colors = LocalReaderColors.current
    val language = appLanguage()
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp)) {
        item { Text(groupPlanTitle(group, plan), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text, modifier = Modifier.padding(start = 4.dp, bottom = 10.dp)) }
        items(plan.days, key = { it.number }) { day ->
            val done = day.number in content.myDays
            val comments = countFor(day.number)
            Row(
                Modifier.fillMaxWidth().clickable { onOpen(day.number) }.padding(horizontal = 4.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(if (done) "●" else "○", color = if (done) colors.accent else colors.separator, modifier = Modifier.width(24.dp))
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.plan_day, day.number), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = if (day.number == today) colors.accent else colors.secondaryText)
                    Text(day.title(language), style = MaterialTheme.typography.bodyLarge, color = if (day.number > today) colors.secondaryText else colors.text)
                }
                if (comments > 0) {
                    val label = if (comments == 1) stringResource(R.string.one_comment) else stringResource(R.string.comments_count, comments)
                    Text("💬 $comments", style = MaterialTheme.typography.labelMedium, color = colors.secondaryText, modifier = Modifier.semantics { contentDescription = label })
                }
            }
            HorizontalDivider(Modifier.padding(start = 28.dp), color = colors.separator)
        }
    }
}

/** One day: the reading, who has read it, and its own discussion. */
@Composable
internal fun PlanDayView(
    group: GroupSummary,
    plan: ReadingPlan,
    day: Int,
    today: Int,
    content: GroupContent,
    members: List<GroupMember>,
    isMine: (String) -> Boolean,
    posts: List<GroupPost>,
    menu: (GroupPost) -> @Composable () -> Unit,
    onRead: (ChapterId) -> Unit,
    onSetRead: (Boolean, Int) -> Unit,
    onSend: suspend (String) -> Boolean,
) {
    val colors = LocalReaderColors.current
    val language = appLanguage()
    val planDay = plan.days.getOrNull(day - 1) ?: return
    val readers = content.readers[day] ?: if (day in content.myDays) setOfNotNull(members.firstOrNull { isMine(it.userId) }?.userId?.lowercase()) else emptySet()
    val names = members.filter { it.userId.lowercase() in readers }.map { if (isMine(it.userId)) stringResource(R.string.you) else it.displayName }
    val isToday = day == today
    Discussion(
        posts = posts,
        menu = menu,
        title = if (isToday) R.string.todays_discussion else null,
        empty = if (isToday) R.string.stood_out_today else R.string.stood_out_reading,
        placeholder = if (isToday) R.string.thought_today else R.string.thought_reading,
        onSend = onSend,
        header = {
            item {
                Card {
                    Caption(stringResource(R.string.day_of_days, day, plan.dayCount))
                    Text(groupPlanTitle(group, plan), style = MaterialTheme.typography.labelLarge, color = colors.secondaryText)
                    Text(planDay.title(language), style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold), color = colors.text)
                    ReadingActions(planDay, done = day in content.myDays, onRead = onRead, onSetRead = { onSetRead(it, day) })
                    Text(
                        if (names.isEmpty()) stringResource(R.string.no_one_marked_day)
                        else stringResource(R.string.read_by, ListFormatter.getInstance(Locale.forLanguageTag(language)).format(names)),
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.secondaryText,
                    )
                }
            }
            if (!isToday) item {
                Text(stringResource(R.string.discussion_for_day, day).uppercase(), style = MaterialTheme.typography.labelMedium, color = colors.secondaryText, modifier = Modifier.padding(start = 4.dp, top = 8.dp))
            }
        },
    )
}
