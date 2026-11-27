package com.genesis.app.together

import android.content.ClipData
import android.content.Intent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.prayer.fieldColors
import com.genesis.core.cloud.community.ChurchMemberRole
import com.genesis.core.cloud.community.CommunityApi
import com.genesis.core.cloud.community.GroupMember
import com.genesis.core.cloud.community.GroupPermissions
import com.genesis.core.cloud.community.GroupStanding
import com.genesis.core.cloud.community.GroupSummary
import com.genesis.core.cloud.community.MuteDuration
import com.genesis.core.cloud.community.isMuted
import com.genesis.core.design.LocalReaderColors
import kotlinx.coroutines.launch

/**
 * The Members tab, as GroupMembersView on iOS: the invite code (a new one
 * for moderators), everyone in the group with their role, and what the
 * signed-in person may do about each of them. The database checks every
 * action again (genesis_can_moderate).
 */
@Composable
internal fun GroupMembers(group: GroupSummary, members: List<GroupMember>, onChanged: suspend () -> Unit) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val store = app.community
    val state by store.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    val permissions = GroupPermissions(group, state.userId)
    var removing by remember { mutableStateOf<GroupMember?>(null) }
    var banning by remember { mutableStateOf<GroupMember?>(null) }
    var newOwner by remember { mutableStateOf<GroupMember?>(null) }
    var steppingDown by remember { mutableStateOf<GroupMember?>(null) }
    // Members nudged from this screen (the server allows one a day each).
    var nudged by remember(group.id) { mutableStateOf(emptySet<String>()) }

    fun act(action: (CommunityApi) -> Unit) {
        scope.launch { if (store.perform(action)) onChanged() }
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (group.inviteCode.isNotBlank()) item { InviteCard(group, canRenew = permissions.isModerator, onRenew = { act { it.newInviteCode(group.id) } }) }
        item {
            Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(14.dp))) {
                members.forEachIndexed { index, member ->
                    MemberRow(
                        member = member,
                        permissions = permissions,
                        blocked = member.userId.lowercase() in state.blocked,
                        act = ::act,
                        onRemove = { removing = member },
                        onBan = { banning = member },
                        onMakeOwner = { newOwner = member },
                        onStepDown = { steppingDown = member },
                        nudged = member.userId.lowercase() in nudged,
                        onNudge = {
                            scope.launch {
                                if (store.perform { it.nudge(member.userId, group.id) }) nudged = nudged + member.userId.lowercase()
                            }
                        },
                    )
                    if (index < members.lastIndex) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                }
            }
        }
        if (members.size > 1 && app.features.isOn(com.genesis.core.domain.features.OptionalFeature.NUDGES)) item {
            run {
                // What a nudge says; the push uses the same sentence, in the receiver's language.
                val name = members.firstOrNull { permissions.isMe(it) }?.displayName ?: stringResource(R.string.a_friend)
                Text(
                    stringResource(R.string.nudge_footer, stringResource(R.string.nudge_message, name)),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.secondaryText,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp),
                )
            }
        }
    }

    removing?.let { member ->
        Confirm(
            title = stringResource(R.string.remove_name_question, member.displayName),
            message = stringResource(R.string.remove_member_message),
            action = stringResource(R.string.remove),
            onConfirm = { act { it.removeMember(member.userId, group.id) } },
            onDismiss = { removing = null },
        )
    }
    newOwner?.let { member ->
        Confirm(
            title = stringResource(R.string.make_owner_question, member.displayName),
            message = stringResource(if (group.isChurch) R.string.make_owner_message_admin else R.string.make_owner_message_moderator),
            action = stringResource(R.string.make_owner),
            onConfirm = {
                scope.launch {
                    if (store.perform { it.transferOwnership(group.id, member.userId) }) {
                        store.refreshGroups()
                        onChanged()
                    }
                }
            },
            onDismiss = { newOwner = null },
        )
    }
    steppingDown?.let { member ->
        Confirm(
            title = stringResource(R.string.step_down_question),
            message = stringResource(R.string.step_down_message),
            action = stringResource(R.string.step_down),
            onConfirm = {
                scope.launch {
                    if (store.perform { it.setChurchRole(ChurchMemberRole.MEMBER, member.userId, group.id) }) {
                        store.refreshGroups()
                        onChanged()
                    }
                }
            },
            onDismiss = { steppingDown = null },
        )
    }
    banning?.let { member ->
        var reason by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { banning = null },
            title = { Text(stringResource(R.string.ban_name_question, member.displayName)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(stringResource(R.string.ban_message))
                    OutlinedTextField(value = reason, onValueChange = { reason = it.take(300) }, placeholder = { Text(stringResource(R.string.reason_optional)) }, colors = fieldColors())
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    banning = null
                    act { it.banMember(member.userId, group.id, reason) }
                }) { Text(stringResource(R.string.ban), color = colors.accent) }
            },
            dismissButton = { TextButton(onClick = { banning = null }) { Text(stringResource(R.string.cancel), color = colors.secondaryText) } },
        )
    }
}

@Composable
private fun InviteCard(group: GroupSummary, canRenew: Boolean, onRenew: () -> Unit) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    var copied by remember(group.inviteCode) { mutableStateOf(false) }
    val invite = stringResource(R.string.invite_message, group.name, group.formattedInviteCode)
    val shareTitle = stringResource(R.string.invite_people)
    Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(14.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.invite_code), style = MaterialTheme.typography.labelLarge, color = colors.secondaryText)
        Text(group.formattedInviteCode, style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold), color = colors.text)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            Button(
                onClick = {
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, invite)
                    context.startActivity(Intent.createChooser(send, shareTitle))
                },
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.background),
            ) { Text(shareTitle) }
            TextButton(onClick = {
                scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText(shareTitle, group.formattedInviteCode))) }
                copied = true
            }) { Text(stringResource(if (copied) R.string.copied else R.string.copy), color = colors.accent) }
            if (canRenew) TextButton(onClick = onRenew) { Text(stringResource(R.string.new_code), color = colors.accent) }
        }
        val footer = when {
            !group.requiresApproval -> R.string.invite_footer_open
            group.isChurch -> R.string.invite_footer_approval_admin
            else -> R.string.invite_footer_approval_moderator
        }
        Text(stringResource(footer), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
    }
}

@Composable
private fun MemberRow(
    member: GroupMember,
    permissions: GroupPermissions,
    blocked: Boolean,
    act: ((CommunityApi) -> Unit) -> Unit,
    onRemove: () -> Unit,
    onBan: () -> Unit,
    onMakeOwner: () -> Unit,
    onStepDown: () -> Unit,
    nudged: Boolean = false,
    onNudge: () -> Unit = {},
) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    val isMe = permissions.isMe(member)
    val standing = permissions.standing(member)
    val group = member.groupId
    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(vertical = 6.dp)) {
            Text(
                if (isMe) stringResource(R.string.member_you, member.displayName) else member.displayName,
                style = MaterialTheme.typography.bodyLarge,
                color = colors.text,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (standing != GroupStanding.MEMBER) Text(stringResource(standing.title(permissions.isChurch)), style = MaterialTheme.typography.labelMedium, color = colors.accent)
                if (member.isMuted()) Text(stringResource(R.string.muted), style = MaterialTheme.typography.labelMedium, color = colors.secondaryText)
            }
        }
        val shows = com.genesis.app.features.rememberFeatureShows()
        if (!isMe && !blocked && shows(com.genesis.core.domain.features.OptionalFeature.NUDGES)) {
            if (nudged) {
                val label = stringResource(R.string.nudged_name, member.displayName)
                Text("✓", color = colors.secondaryText, modifier = Modifier.padding(horizontal = 12.dp).semantics { contentDescription = label })
            } else {
                val label = stringResource(R.string.nudge_name, member.displayName)
                IconButton(onClick = onNudge, modifier = Modifier.size(40.dp).semantics { contentDescription = label }) {
                    Text("👋", modifier = Modifier.clearAndSetSemantics {})
                }
            }
        }
        if (isMe && !permissions.canStepDown(member)) return@Row
        var open by remember { mutableStateOf(false) }
        var muting by remember { mutableStateOf(false) }
        Box {
            val more = stringResource(R.string.more)
            IconButton(onClick = { open = true }, modifier = Modifier.size(40.dp).semantics { contentDescription = more }) {
                Canvas(Modifier.size(18.dp)) {
                    listOf(0.2f, 0.5f, 0.8f).forEach { drawCircle(colors.secondaryText, size.minDimension * 0.08f, Offset(size.width * it, size.height / 2)) }
                }
            }
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                @Composable
                fun item(title: Int, onClick: () -> Unit) = DropdownMenuItem(text = { Text(stringResource(title)) }, onClick = { open = false; onClick() })
                if (permissions.canStepDown(member)) item(R.string.step_down_as_preacher, onStepDown)
                if (permissions.canChooseRole(member)) {
                    if (permissions.isChurch) {
                        if (member.isLeader) item(R.string.remove_as_admin) { act { it.setChurchRole(ChurchMemberRole.MEMBER, member.userId, group) } }
                        else item(R.string.make_admin) { act { it.setChurchRole(ChurchMemberRole.ADMIN, member.userId, group) } }
                    } else {
                        if (member.isLeader) item(R.string.remove_as_moderator) { act { it.setRole("member", member.userId, group) } }
                        else item(R.string.make_moderator) { act { it.setRole("leader", member.userId, group) } }
                    }
                    item(R.string.make_owner_more, onMakeOwner)
                }
                if (permissions.canChoosePreacher(member)) {
                    if (member.preacher == true) item(R.string.remove_as_preacher) { act { it.setChurchRole(ChurchMemberRole.MEMBER, member.userId, group) } }
                    else item(R.string.make_preacher) { act { it.setChurchRole(ChurchMemberRole.PREACHER, member.userId, group) } }
                }
                if (permissions.canModerate(member)) {
                    if (member.isMuted()) item(R.string.unmute) { act { it.muteMember(member.userId, group, 0) } }
                    else item(R.string.mute) { muting = true }
                    item(R.string.remove_from_group, onRemove)
                    item(R.string.ban_more, onBan)
                }
                if (!isMe) {
                    if (blocked) item(R.string.unblock) { scope.launch { app.community.unblock(member.userId) } }
                    else item(R.string.block) { scope.launch { app.community.block(member.userId) } }
                }
            }
            DropdownMenu(expanded = muting, onDismissRequest = { muting = false }) {
                MuteDuration.entries.forEach { duration ->
                    DropdownMenuItem(
                        text = { Text(stringResource(duration.title)) },
                        onClick = {
                            muting = false
                            act { it.muteMember(member.userId, group, duration.hours) }
                        },
                    )
                }
            }
        }
    }
}

private val MuteDuration.title: Int
    get() = when (this) {
        MuteDuration.HOUR -> R.string.mute_hour
        MuteDuration.DAY -> R.string.mute_day
        MuteDuration.WEEK -> R.string.mute_week
    }

/** A yes-or-cancel question before something that can't be taken back. */
@Composable
internal fun Confirm(title: String, message: String?, action: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = message?.let { { Text(it) } },
        confirmButton = {
            TextButton(onClick = {
                onDismiss()
                onConfirm()
            }) { Text(action, color = colors.accent) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = colors.secondaryText) } },
    )
}
