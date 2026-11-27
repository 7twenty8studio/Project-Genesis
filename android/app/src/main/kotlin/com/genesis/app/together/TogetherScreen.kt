package com.genesis.app.together

import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.prayer.fieldColors
import com.genesis.core.cloud.community.GroupStanding
import com.genesis.core.cloud.community.GroupSummary
import com.genesis.core.cloud.community.InviteCode
import com.genesis.core.design.LocalReaderColors
import kotlinx.coroutines.launch

/**
 * The Together tab, as TogetherView on iOS: your church groups. Everything
 * here needs an account and a display name, and starting or joining a group
 * asks once for the community guidelines.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun TogetherScreen(
    bible: com.genesis.app.prayer.JournalBible,
    bibleId: String,
    onSignIn: () -> Unit,
    onRead: (com.genesis.core.domain.bible.ChapterId) -> Unit,
    modifier: Modifier = Modifier,
    onOpenSermon: (String) -> Unit = {},
    /** A group to open (a Group Progress widget tap), once per request. */
    startGroup: String? = null,
    onStartGroupHandled: () -> Unit = {},
) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val store = app.community
    val state by store.state.collectAsStateWithLifecycle()
    val account by app.account.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    var openGroup by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(startGroup) {
        if (startGroup != null) {
            openGroup = startGroup
            onStartGroupHandled()
        }
    }
    var editingName by rememberSaveable { mutableStateOf(false) }
    var findingChurch by rememberSaveable { mutableStateOf(false) }
    val flags by app.flags.values.collectAsStateWithLifecycle()
    val churchSermons = flags[com.genesis.app.FeatureFlags.CHURCH_SERMONS] == true
    LaunchedEffect(account.user?.id) { store.refresh() }

    if (findingChurch && churchSermons) {
        com.genesis.app.churchsermons.ChurchSearchScreen(store.sermons, app.hiddenChurches, onOpen = onOpenSermon, onDone = { findingChurch = false }, modifier = modifier.statusBarsPadding())
        return
    }

    openGroup?.let { id ->
        BackHandler { openGroup = null }
        GroupScreen(groupId = id, bible = bible, bibleId = bibleId, onBack = { openGroup = null }, onRead = onRead, modifier = modifier, onOpenSermon = if (churchSermons) onOpenSermon else null)
        return
    }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.tab_together),
                style = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            if (churchSermons) {
                TextButton(onClick = { findingChurch = true }) { Text(stringResource(R.string.find_a_church), color = colors.accent) }
            }
            if (state.isSignedIn && state.profile != null) {
                TextButton(onClick = { editingName = true }) { Text(stringResource(R.string.change_display_name), color = colors.accent) }
            }
        }
        when {
            !state.hasLoaded -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = colors.accent) }
            !state.isSignedIn -> SignInPrompt(onSignIn)
            state.needsDisplayName || editingName -> DisplayName(
                current = state.profile?.displayName.orEmpty(),
                onDone = if (editingName) ({ editingName = false }) else null,
            )
            else -> {
                // Groups, then the prayer wall and reflections while the community switch is on.
                val sections = buildList {
                    if (flags[com.genesis.app.FeatureFlags.GROUPS] == true) add(TogetherSection.GROUPS)
                    if (flags[com.genesis.app.FeatureFlags.COMMUNITY] == true) { add(TogetherSection.PRAYER); add(TogetherSection.REFLECTIONS) }
                }.ifEmpty { listOf(TogetherSection.GROUPS) }
                var chosen by rememberSaveable { mutableStateOf(TogetherSection.GROUPS) }
                val section = if (chosen in sections) chosen else sections.first()
                if (sections.size > 1) {
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        sections.forEach { item ->
                            androidx.compose.material3.FilterChip(
                                selected = item == section,
                                onClick = { chosen = item },
                                label = { Text(stringResource(item.title)) },
                                colors = androidx.compose.material3.FilterChipDefaults.filterChipColors(
                                    selectedContainerColor = colors.accent.copy(alpha = 0.18f),
                                    selectedLabelColor = colors.text,
                                    labelColor = colors.secondaryText,
                                ),
                            )
                        }
                    }
                }
                when (section) {
                    TogetherSection.GROUPS -> {
                        val scope = rememberCoroutineScope()
                        var refreshing by remember { mutableStateOf(false) }
                        PullToRefreshBox(
                            isRefreshing = refreshing,
                            onRefresh = { scope.launch { refreshing = true; store.refreshGroups(); refreshing = false } },
                        ) { GroupsList(state, onOpen = { openGroup = it }) }
                    }
                    TogetherSection.PRAYER -> CommunityFeed(com.genesis.core.cloud.community.CommunityPostKind.PRAYER, bible.language, onRead)
                    TogetherSection.REFLECTIONS -> CommunityFeed(com.genesis.core.cloud.community.CommunityPostKind.REFLECTION, bible.language, onRead)
                }
            }
        }
    }
}

/** Together's parts, as TogetherView.Area on iOS. */
internal enum class TogetherSection(val title: Int) {
    GROUPS(R.string.together_groups), PRAYER(R.string.prayer_wall), REFLECTIONS(R.string.wn_community_reflections)
}

@Composable
private fun SignInPrompt(onSignIn: () -> Unit) {
    val colors = LocalReaderColors.current
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Spacer(Modifier.size(32.dp))
        Text(stringResource(R.string.read_pray_together), style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif), color = colors.text, textAlign = TextAlign.Center)
        Text(stringResource(R.string.together_sign_in_message), style = MaterialTheme.typography.bodyLarge, color = colors.secondaryText, textAlign = TextAlign.Center)
        Spacer(Modifier.size(8.dp))
        Button(onClick = onSignIn, colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.background)) {
            Text(stringResource(R.string.sign_in_or_create), fontWeight = FontWeight.SemiBold)
        }
    }
}

/** Choose the name others see in groups (DisplayNameView on iOS). */
@Composable
private fun DisplayName(current: String, onDone: (() -> Unit)?) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val state by app.community.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    var name by rememberSaveable { mutableStateOf(current) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).widthIn(max = 560.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.display_name_question), style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold), color = colors.text)
        Text(stringResource(R.string.display_name_message), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
        OutlinedTextField(
            value = name,
            onValueChange = { name = it.take(40) },
            placeholder = { Text(stringResource(R.string.display_name)) },
            singleLine = true,
            colors = fieldColors(),
            modifier = Modifier.fillMaxWidth(),
        )
        state.error?.let { Text(stringResource(it.text()), color = colors.accent, style = MaterialTheme.typography.bodySmall) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (onDone != null) TextButton(onClick = onDone) { Text(stringResource(R.string.cancel), color = colors.secondaryText) }
            Button(
                onClick = { scope.launch { if (app.community.setDisplayName(name)) onDone?.invoke() } },
                enabled = name.isNotBlank() && !state.isWorking,
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.background),
            ) { Text(stringResource(if (onDone != null) R.string.save else R.string.continue_button)) }
        }
    }
}

private enum class GroupSheet { JOIN, CREATE }

@Composable
private fun GroupsList(state: TogetherState, onOpen: (String) -> Unit) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val colors = LocalReaderColors.current
    var sheet by remember { mutableStateOf<GroupSheet?>(null) }
    var guidelinesFor by remember { mutableStateOf<GroupSheet?>(null) }
    var requested by remember { mutableStateOf<String?>(null) }

    fun open(next: GroupSheet) {
        if (state.profile?.hasAcceptedTerms == true) sheet = next else guidelinesFor = next
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp).widthIn(max = 720.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        state.error?.let { Text(stringResource(it.text()), color = colors.accent, style = MaterialTheme.typography.bodySmall) }
        if (state.groups.isNotEmpty()) {
            Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(16.dp))) {
                state.groups.forEachIndexed { index, group ->
                    GroupRow(group, Modifier.fillMaxWidth().clickable { onOpen(group.id) }.padding(16.dp))
                    if (index < state.groups.lastIndex) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                }
            }
        }
        Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(16.dp))) {
            ActionRow(stringResource(R.string.join_with_code)) { open(GroupSheet.JOIN) }
            HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
            ActionRow(stringResource(R.string.start_group)) { open(GroupSheet.CREATE) }
        }
        if (state.groups.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(stringResource(R.string.no_groups_yet), style = MaterialTheme.typography.titleMedium, color = colors.text)
                Spacer(Modifier.size(6.dp))
                Text(stringResource(R.string.no_groups_message), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, textAlign = TextAlign.Center)
            }
        }
    }

    guidelinesFor?.let { next ->
        Guidelines(
            onAccepted = {
                guidelinesFor = null
                sheet = next
            },
            onCancel = { guidelinesFor = null },
        )
    }
    when (sheet) {
        GroupSheet.JOIN -> JoinDialog(
            onJoined = { outcome ->
                sheet = null
                if (outcome.joined) onOpen(outcome.groupId) else requested = outcome.name
            },
            onCancel = { sheet = null; app.community.clearError() },
        )
        GroupSheet.CREATE -> GroupForm(
            existing = null,
            onSaved = { id ->
                sheet = null
                onOpen(id)
            },
            onCancel = { sheet = null; app.community.clearError() },
        )
        null -> Unit
    }
    requested?.let { name ->
        AlertDialog(
            onDismissRequest = { requested = null },
            title = { Text(name) },
            text = { Text(stringResource(R.string.request_sent_message) + "\n\n" + stringResource(R.string.request_sent_detail)) },
            confirmButton = { TextButton(onClick = { requested = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

@Composable
private fun GroupRow(group: GroupSummary, modifier: Modifier) {
    val colors = LocalReaderColors.current
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(group.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text, modifier = Modifier.weight(1f, fill = false))
            if (group.isLeader || group.standing == GroupStanding.PREACHER) {
                Text(
                    stringResource(group.standing.title(group.isChurch)),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = colors.accent,
                    modifier = Modifier.clip(CircleShape).background(colors.accent.copy(alpha = 0.15f)).padding(horizontal = 8.dp, vertical = 2.dp),
                )
            }
        }
        val detail = group.plan?.let { groupPlanTitle(group, it) } ?: group.description
        if (detail.isNotBlank()) Text(detail, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun ActionRow(title: String, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Text(title, style = MaterialTheme.typography.bodyLarge, color = colors.accent, modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(16.dp))
}

/** The community guidelines, agreed to once before starting or joining a group, or posting to the community. */
@Composable
internal fun Guidelines(onAccepted: () -> Unit, onCancel: () -> Unit, community: Boolean = false) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val state by app.community.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(stringResource(R.string.community_guidelines)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(if (community) R.string.guidelines_community_intro else R.string.guidelines_groups_intro), color = colors.secondaryText)
                listOf(R.string.rule_kind, R.string.rule_abuse, R.string.rule_private, R.string.rule_spam, R.string.rule_report).forEach { rule ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("•", color = colors.accent, fontWeight = FontWeight.Bold)
                        Text(stringResource(rule), color = colors.text)
                    }
                }
                Text(stringResource(if (community) R.string.guidelines_community_footer else R.string.guidelines_groups_footer), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                state.error?.let { Text(stringResource(it.text()), color = colors.accent, style = MaterialTheme.typography.bodySmall) }
            }
        },
        confirmButton = {
            TextButton(onClick = { scope.launch { if (app.community.acceptCommunityTerms()) onAccepted() } }, enabled = !state.isWorking) {
                Text(stringResource(R.string.i_agree), color = colors.accent, fontWeight = FontWeight.SemiBold)
            }
        },
        dismissButton = { TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel), color = colors.secondaryText) } },
    )
}

@Composable
private fun JoinDialog(onJoined: (com.genesis.core.cloud.community.GroupJoinOutcome) -> Unit, onCancel: () -> Unit) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val state by app.community.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    var code by rememberSaveable { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(stringResource(R.string.join_with_code)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = code,
                    onValueChange = { code = it.uppercase().take(14) },
                    placeholder = { Text(stringResource(R.string.invite_code)) },
                    singleLine = true,
                    colors = fieldColors(),
                )
                Text(
                    state.error?.let { stringResource(it.text()) } ?: stringResource(R.string.invite_code_help),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (state.error != null) colors.accent else colors.secondaryText,
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { scope.launch { app.community.requestToJoin(InviteCode.clean(code))?.let(onJoined) } },
                enabled = InviteCode.isPlausible(code) && !state.isWorking,
            ) { Text(stringResource(R.string.join), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        },
        dismissButton = { TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel), color = colors.secondaryText) } },
    )
}
