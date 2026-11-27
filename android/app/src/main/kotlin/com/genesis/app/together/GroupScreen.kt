package com.genesis.app.together

import android.content.ClipData
import android.content.Intent
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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
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
import com.genesis.app.prayer.EmptyJournal
import com.genesis.app.prayer.Segmented
import com.genesis.app.prayer.fieldColors
import com.genesis.core.cloud.community.CommunityError
import com.genesis.core.cloud.community.ContentKind
import com.genesis.core.cloud.community.GroupAnnouncement
import com.genesis.core.cloud.community.GroupMember
import com.genesis.core.cloud.community.GroupPost
import com.genesis.core.cloud.community.GroupPrayer
import com.genesis.core.cloud.community.GroupStanding
import com.genesis.core.cloud.community.GroupSummary
import com.genesis.core.design.LocalReaderColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private enum class GroupTab { DISCUSSION, PRAYER, NEWS, MEMBERS }

/** What a group shows, loaded together (GroupDetailModel on iOS). */
private data class GroupContent(
    val posts: List<GroupPost> = emptyList(),
    val prayers: List<GroupPrayer> = emptyList(),
    val prayed: Set<String> = emptySet(),
    val announcements: List<GroupAnnouncement> = emptyList(),
    val members: List<GroupMember> = emptyList(),
    val loaded: Boolean = false,
)

/**
 * One group: its discussion, prayer requests, news from its leaders and the
 * people in it. Blocked people's posts and anything reported here are left
 * out; the database still decides who may post, remove or announce.
 */
@Composable
fun GroupScreen(groupId: String, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val store = app.community
    val state by store.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    val group = state.groups.firstOrNull { it.id == groupId }
    var tab by rememberSaveable { mutableStateOf(GroupTab.DISCUSSION) }
    var content by remember { mutableStateOf(GroupContent()) }
    var hidden by remember { mutableStateOf(setOf<String>()) }
    var loadError by remember { mutableStateOf<CommunityError?>(null) }
    var leaving by remember { mutableStateOf(false) }
    var closing by remember { mutableStateOf(false) }
    var moderating by rememberSaveable { mutableStateOf(false) }
    var moderation by remember { mutableStateOf(ModerationContent()) }

    suspend fun reload() {
        val api = store.api ?: return
        try {
            content = withContext(Dispatchers.IO) {
                val prayers = api.prayers(groupId)
                GroupContent(
                    posts = api.posts(groupId),
                    prayers = prayers,
                    prayed = api.myPrayerMarks(prayers.map { it.id }),
                    announcements = api.announcements(groupId),
                    members = api.members(groupId),
                    loaded = true,
                )
            }
            loadError = null
        } catch (error: CommunityError) {
            loadError = error
            content = content.copy(loaded = true)
        }
    }
    suspend fun reloadModeration() {
        if (group?.isLeader == true) runCatching { moderation = loadModeration(app, groupId) }
    }
    LaunchedEffect(groupId) { reload() }
    LaunchedEffect(groupId, group?.isLeader, moderating) { if (!moderating) reloadModeration() }

    if (moderating && group != null) {
        ModerationScreen(group, onChanged = { store.refreshGroups(); reload() }, onDone = { moderating = false })
        return
    }

    fun shows(user: String, id: String) = user.lowercase() !in state.blocked && id !in hidden

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding().imePadding()) {
        Row(Modifier.padding(start = 4.dp, end = 4.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ " + stringResource(R.string.tab_together), color = colors.accent) }
            Spacer(Modifier.weight(1f))
            if (group?.isLeader == true) {
                TextButton(onClick = { moderating = true }) {
                    val count = moderation.pendingCount
                    Text(stringResource(R.string.moderation) + if (count > 0) " ($count)" else "", color = colors.accent)
                }
            }
            if (group != null) GroupMenu(isOwner = group.isOwner, onLeave = { leaving = true }, onClose = { closing = true })
        }
        if (group == null) {
            EmptyJournal(R.string.not_available, R.string.not_in_group)
            return@Column
        }
        Text(
            group.name,
            style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
            color = colors.text,
            modifier = Modifier.padding(horizontal = 20.dp).semantics { heading() },
        )
        if (group.description.isNotBlank()) {
            Text(group.description, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp))
        }
        Box(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
            Segmented(
                options = listOf(stringResource(R.string.discussion), stringResource(R.string.prayer_tab), stringResource(R.string.news), stringResource(R.string.members)),
                selected = tab.ordinal,
                onSelect = { tab = GroupTab.entries[it] },
            )
        }
        (loadError ?: state.error)?.let {
            Text(stringResource(it.text()), color = colors.accent, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = 20.dp))
        }
        if (!content.loaded) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = colors.accent) }
            return@Column
        }
        val canRemove = { user: String -> store.isMine(user) || group.isLeader }
        fun menu(kind: ContentKind, id: String, user: String, name: String): @Composable () -> Unit = {
            ContentMenu(
                authorName = name,
                isMine = store.isMine(user),
                canRemove = canRemove(user),
                onRemove = { if (store.perform { it.remove(kind, id) }) reload() },
                onReport = { reason -> store.report(kind, id, reason) },
                onBlock = { store.block(user) },
                onHidden = { hidden = hidden + id },
            )
        }
        when (tab) {
            GroupTab.DISCUSSION -> Discussion(
                posts = content.posts.filter { shows(it.userId, it.id) },
                menu = { menu(ContentKind.GROUP_POST, it.id, it.userId, it.displayName) },
                onSend = { body -> store.perform { it.addPost(body, null, groupId) }.also { if (it) reload() } },
            )
            GroupTab.PRAYER -> Prayers(
                prayers = content.prayers.filter { shows(it.userId, it.id) },
                prayed = content.prayed,
                isMine = store::isMine,
                menu = { menu(ContentKind.GROUP_PRAYER, it.id, it.userId, it.displayName) },
                onPrayed = { prayer, on -> scope.launch { if (store.perform { it.setPrayed(on, prayer.id) }) reload() } },
                onAnswered = { prayer -> scope.launch { if (store.perform { it.setAnswered(prayer.answeredAt == null, prayer.id) }) reload() } },
                onShare = { body -> store.perform { it.addPrayer(body, groupId) }.also { if (it) reload() } },
            )
            GroupTab.NEWS -> News(
                announcements = content.announcements.filter { shows(it.userId, it.id) },
                canPost = group.isLeader,
                menu = { menu(ContentKind.GROUP_ANNOUNCEMENT, it.id, it.userId, it.displayName) },
                onPost = { title, body -> store.perform { it.addAnnouncement(title, body, groupId) }.also { if (it) reload() } },
            )
            GroupTab.MEMBERS -> GroupMembers(group, content.members, onChanged = {
                store.refreshGroups()
                reload()
            })
        }
    }

    if (leaving && group != null) {
        Confirm(
            title = stringResource(R.string.leave_name_question, group.name),
            message = stringResource(
                when {
                    !group.isOwner -> R.string.leave_rejoin
                    group.isChurch -> R.string.leave_owner_admin
                    else -> R.string.leave_owner_moderator
                },
            ),
            action = stringResource(R.string.leave),
            onConfirm = { scope.launch { if (store.leaveGroup(group.id)) onBack() } },
            onDismiss = { leaving = false },
        )
    }
    if (closing && group != null) {
        Confirm(
            title = stringResource(R.string.close_name_question, group.name),
            message = stringResource(R.string.close_message),
            action = stringResource(R.string.close_group),
            onConfirm = { scope.launch { if (store.deleteGroup(group.id)) onBack() } },
            onDismiss = { closing = false },
        )
    }
}

@Composable
private fun GroupMenu(isOwner: Boolean, onLeave: () -> Unit, onClose: () -> Unit) {
    val colors = LocalReaderColors.current
    var open by remember { mutableStateOf(false) }
    Box {
        val more = stringResource(R.string.more)
        IconButton(onClick = { open = true }, modifier = Modifier.semantics { contentDescription = more }) {
            Canvas(Modifier.size(20.dp)) {
                listOf(0.2f, 0.5f, 0.8f).forEach { drawCircle(colors.accent, size.minDimension * 0.09f, Offset(size.width * it, size.height / 2)) }
            }
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.leave_group)) }, onClick = { open = false; onLeave() })
            if (isOwner) DropdownMenuItem(text = { Text(stringResource(R.string.close_group)) }, onClick = { open = false; onClose() })
        }
    }
}

/** A post, prayer or announcement: who, when, the words, and its menu. */
@Composable
private fun Entry(name: String, time: String, menu: @Composable () -> Unit, content: @Composable () -> Unit) {
    val colors = LocalReaderColors.current
    Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(14.dp)).padding(start = 14.dp, top = 10.dp, bottom = 12.dp, end = 4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(name, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = colors.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            Text("  ·  $time", style = MaterialTheme.typography.labelMedium, color = colors.secondaryText, maxLines = 1, modifier = Modifier.weight(1f))
            menu()
        }
        Column(Modifier.padding(end = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) { content() }
    }
}

/** A text field with a send button, kept under the list. */
@Composable
private fun Composer(placeholder: Int, action: Int, onSend: suspend (String) -> Boolean) {
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    var text by rememberSaveable { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value = text,
            onValueChange = { text = it.take(2000) },
            placeholder = { Text(stringResource(placeholder)) },
            maxLines = 5,
            colors = fieldColors(),
            modifier = Modifier.weight(1f),
        )
        Button(
            onClick = {
                sending = true
                scope.launch {
                    if (onSend(text)) text = ""
                    sending = false
                }
            },
            enabled = text.isNotBlank() && !sending,
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.background),
        ) { Text(stringResource(action)) }
    }
}

@Composable
private fun Discussion(posts: List<GroupPost>, menu: (GroupPost) -> @Composable () -> Unit, onSend: suspend (String) -> Boolean) {
    val colors = LocalReaderColors.current
    val list = rememberLazyListState()
    LaunchedEffect(posts.size) { if (posts.isNotEmpty()) list.scrollToItem(posts.lastIndex) }
    Column(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (posts.isEmpty()) item { EmptyJournal(R.string.discussion, R.string.start_conversation) }
            items(posts, key = { it.id }) { post ->
                Entry(post.displayName, relativeTime(post.createdAt), menu(post)) {
                    Text(post.body, style = MaterialTheme.typography.bodyLarge, color = colors.text)
                }
            }
        }
        HorizontalDivider(color = colors.separator)
        Composer(R.string.write_message, R.string.send, onSend)
    }
}

@Composable
private fun Prayers(
    prayers: List<GroupPrayer>,
    prayed: Set<String>,
    isMine: (String) -> Boolean,
    menu: (GroupPrayer) -> @Composable () -> Unit,
    onPrayed: (GroupPrayer, Boolean) -> Unit,
    onAnswered: (GroupPrayer) -> Unit,
    onShare: suspend (String) -> Boolean,
) {
    val colors = LocalReaderColors.current
    Column(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { Text(stringResource(R.string.group_prayers_private), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText) }
            if (prayers.isEmpty()) item { EmptyJournal(R.string.prayer_tab, R.string.no_group_prayer_requests) }
            items(prayers, key = { it.id }) { prayer ->
                val mine = isMine(prayer.userId)
                val didPray = prayer.id.lowercase() in prayed
                Entry(prayer.displayName, relativeTime(prayer.createdAt), menu(prayer)) {
                    Text(prayer.body, style = MaterialTheme.typography.bodyLarge, color = colors.text)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (prayer.answeredAt != null) {
                            Text(
                                stringResource(R.string.answered),
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = colors.accent,
                                modifier = Modifier.clip(CircleShape).background(colors.accent.copy(alpha = 0.15f)).padding(horizontal = 8.dp, vertical = 2.dp),
                            )
                        }
                        if (prayer.prayedCount > 0) {
                            Text(stringResource(R.string.praying_count, prayer.prayedCount), style = MaterialTheme.typography.labelMedium, color = colors.secondaryText)
                        }
                        Spacer(Modifier.weight(1f))
                        if (mine && prayer.answeredAt == null) {
                            TextButton(onClick = { onAnswered(prayer) }) { Text(stringResource(R.string.mark_answered), color = colors.accent) }
                        }
                        Text(
                            (if (didPray) "✓ " else "") + stringResource(R.string.i_prayed),
                            style = MaterialTheme.typography.labelLarge,
                            color = if (didPray) colors.background else colors.accent,
                            modifier = Modifier.clip(CircleShape)
                                .background(if (didPray) colors.accent else colors.accent.copy(alpha = 0.12f))
                                .clickable { onPrayed(prayer, !didPray) }
                                .padding(horizontal = 12.dp, vertical = 6.dp),
                        )
                    }
                }
            }
        }
        HorizontalDivider(color = colors.separator)
        Composer(R.string.share_prayer_request, R.string.share, onShare)
    }
}

@Composable
private fun News(announcements: List<GroupAnnouncement>, canPost: Boolean, menu: (GroupAnnouncement) -> @Composable () -> Unit, onPost: suspend (String, String) -> Boolean) {
    val colors = LocalReaderColors.current
    var writing by remember { mutableStateOf(false) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (canPost) item {
            TextButton(onClick = { writing = true }) { Text(stringResource(R.string.new_announcement), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        if (announcements.isEmpty()) item { EmptyJournal(R.string.news, R.string.no_announcements) }
        items(announcements, key = { it.id }) { item ->
            Entry(item.displayName, relativeTime(item.createdAt), menu(item)) {
                Text(item.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
                Text(item.body, style = MaterialTheme.typography.bodyLarge, color = colors.text)
            }
        }
    }
    if (writing) AnnouncementDialog(onPost = onPost, onDone = { writing = false })
}

@Composable
private fun AnnouncementDialog(onPost: suspend (String, String) -> Boolean, onDone: () -> Unit) {
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    var title by rememberSaveable { mutableStateOf("") }
    var body by rememberSaveable { mutableStateOf("") }
    var posting by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDone,
        title = { Text(stringResource(R.string.new_announcement)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = title, onValueChange = { title = it.take(120) }, placeholder = { Text(stringResource(R.string.title_field)) }, singleLine = true, colors = fieldColors())
                OutlinedTextField(value = body, onValueChange = { body = it.take(2000) }, placeholder = { Text(stringResource(R.string.message_field)) }, minLines = 3, colors = fieldColors())
                Text(stringResource(R.string.announcement_footer), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    posting = true
                    scope.launch {
                        if (onPost(title, body)) onDone()
                        posting = false
                    }
                },
                enabled = title.isNotBlank() && body.isNotBlank() && !posting,
            ) { Text(stringResource(R.string.post), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        },
        dismissButton = { TextButton(onClick = onDone) { Text(stringResource(R.string.cancel), color = colors.secondaryText) } },
    )
}
