package com.genesis.app.together

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.core.cloud.community.CommunityError
import com.genesis.core.cloud.community.ContentKind
import com.genesis.core.cloud.community.GroupBan
import com.genesis.core.cloud.community.GroupJoinRequest
import com.genesis.core.cloud.community.GroupReport
import com.genesis.core.cloud.community.GroupSummary
import com.genesis.core.cloud.community.ReportAction
import com.genesis.core.cloud.community.ReportReason
import com.genesis.core.design.LocalReaderColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What's waiting for a group's moderators. */
internal data class ModerationContent(
    val requests: List<GroupJoinRequest> = emptyList(),
    val reports: List<GroupReport> = emptyList(),
    val bans: List<GroupBan> = emptyList(),
) {
    val pendingCount: Int get() = requests.size + reports.size
}

/** Loads the moderation lists; empty for anyone who isn't a moderator. */
internal suspend fun loadModeration(app: VerselyApplication, group: String): ModerationContent {
    val api = app.community.api ?: return ModerationContent()
    return withContext(Dispatchers.IO) {
        ModerationContent(api.joinRequests(group), api.reports(group), api.bans(group))
    }
}

/**
 * Moderation for a group's owner and moderators, as GroupModerationView on
 * iOS: whether new members need approving, people asking to join, reported
 * content, and banned people.
 */
@Composable
internal fun ModerationScreen(group: GroupSummary, onChanged: suspend () -> Unit, onDone: () -> Unit) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val store = app.community
    val state by store.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    var content by remember { mutableStateOf(ModerationContent()) }
    var error by remember { mutableStateOf<CommunityError?>(null) }
    BackHandler(onBack = onDone)

    suspend fun reload() {
        try {
            content = loadModeration(app, group.id)
            error = null
        } catch (failure: CommunityError) {
            error = failure
        }
    }
    LaunchedEffect(group.id) { reload() }

    fun act(action: (com.genesis.core.cloud.community.CommunityApi) -> Unit) {
        scope.launch {
            if (store.perform(action)) {
                reload()
                onChanged()
            }
        }
    }

    Column(Modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.moderation),
                style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            (error ?: state.error)?.let { Text(stringResource(it.text()), color = colors.accent, style = MaterialTheme.typography.bodySmall) }

            Section(header = null, footer = listOf(
                stringResource(if (group.isChurch) R.string.approval_footer_admin else R.string.approval_footer_moderator),
                stringResource(R.string.approval_off_footer),
            )) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.approve_new_members), style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.weight(1f))
                    Switch(
                        checked = group.requiresApproval,
                        onCheckedChange = { on -> act { it.setRequiresApproval(on, group.id) } },
                        colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.background),
                    )
                }
            }

            Section(header = stringResource(R.string.join_requests), footer = emptyList()) {
                if (content.requests.isEmpty()) Empty(R.string.no_one_waiting)
                content.requests.forEachIndexed { index, request ->
                    if (index > 0) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                    Column(Modifier.fillMaxWidth().padding(start = 16.dp, top = 12.dp, end = 8.dp, bottom = 4.dp)) {
                        Text(request.displayName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = colors.text)
                        Text(stringResource(R.string.asked_when, relativeTime(request.createdAt)), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                        Row {
                            TextButton(onClick = { act { it.answerJoinRequest(request.userId, group.id, true) } }) { Text(stringResource(R.string.approve), color = colors.accent) }
                            TextButton(onClick = { act { it.answerJoinRequest(request.userId, group.id, false) } }) { Text(stringResource(R.string.decline), color = colors.accent) }
                            Spacer(Modifier.weight(1f))
                            TextButton(onClick = { act { it.banMember(request.userId, group.id, "") } }) { Text(stringResource(R.string.ban), color = colors.secondaryText) }
                        }
                    }
                }
            }

            Section(
                header = stringResource(R.string.reports),
                footer = listOf(stringResource(if (group.isChurch) R.string.reports_footer_admin else R.string.reports_footer_moderator)),
            ) {
                if (content.reports.isEmpty()) Empty(R.string.nothing_reported)
                content.reports.forEachIndexed { index, report ->
                    if (index > 0) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                    ReportRow(
                        report,
                        onRemove = { report.kind?.let { kind -> act { it.reviewReport(kind, report.contentId, ReportAction.REMOVE) } } },
                        onKeep = { report.kind?.let { kind -> act { it.reviewReport(kind, report.contentId, ReportAction.KEEP) } } },
                    )
                }
            }

            Section(header = stringResource(R.string.banned), footer = listOf(stringResource(R.string.banned_footer))) {
                if (content.bans.isEmpty()) Empty(R.string.no_one_banned)
                content.bans.forEachIndexed { index, ban ->
                    if (index > 0) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(ban.displayName, style = MaterialTheme.typography.bodyLarge, color = colors.text)
                            if (ban.reason.isNotBlank()) Text(ban.reason, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                        }
                        TextButton(onClick = { act { it.unbanMember(ban.userId, group.id) } }) { Text(stringResource(R.string.unban), color = colors.accent) }
                    }
                }
            }
        }
    }
}

@Composable
private fun Section(header: String?, footer: List<String>, content: @Composable ColumnScope.() -> Unit) {
    val colors = LocalReaderColors.current
    Column(Modifier.fillMaxWidth().padding(bottom = 14.dp)) {
        header?.let { Text(it.uppercase(), style = MaterialTheme.typography.labelMedium, color = colors.secondaryText, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp)) }
        Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(14.dp)), content = content)
        footer.forEach { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp)) }
    }
}

@Composable
private fun Empty(text: Int) {
    Text(stringResource(text), style = MaterialTheme.typography.bodyLarge, color = LocalReaderColors.current.secondaryText, modifier = Modifier.padding(16.dp))
}

@Composable
private fun ReportRow(report: GroupReport, onRemove: () -> Unit, onKeep: () -> Unit) {
    val colors = LocalReaderColors.current
    val kind = when (report.kind) {
        ContentKind.GROUP_PRAYER -> R.string.kind_prayer_request
        ContentKind.GROUP_POST -> R.string.kind_discussion
        ContentKind.GROUP_ANNOUNCEMENT -> R.string.kind_announcement
        null -> R.string.kind_group_post
    }
    val count = if (report.reportCount == 1) stringResource(R.string.reported_once) else stringResource(R.string.reported_times, report.reportCount)
    val reasons = report.reasons.map { raw -> ReportReason.entries.firstOrNull { it.value == raw }?.let { stringResource(it.title) } ?: raw }.distinct().sorted()
    Column(Modifier.fillMaxWidth().padding(start = 16.dp, top = 12.dp, end = 8.dp, bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("${report.authorName} · ${stringResource(kind)}", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = colors.text)
        Text(report.body, style = MaterialTheme.typography.bodyLarge, color = colors.text, maxLines = 6, overflow = TextOverflow.Ellipsis)
        Text(count, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        if (reasons.isNotEmpty()) Text(reasons.joinToString(", "), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        if (report.hidden) Text(stringResource(R.string.hidden_for_review), style = MaterialTheme.typography.bodySmall, fontStyle = FontStyle.Italic, color = colors.secondaryText)
        Row {
            TextButton(onClick = onRemove) { Text(stringResource(R.string.remove), color = colors.accent) }
            TextButton(onClick = onKeep) { Text(stringResource(R.string.keep), color = colors.accent) }
        }
    }
}
