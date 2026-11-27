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
import com.genesis.core.cloud.community.MemberProgress
import com.genesis.core.cloud.community.ChallengeProgress
import com.genesis.app.prayer.JournalBible
import com.genesis.core.domain.bible.ChapterId
import androidx.activity.compose.BackHandler
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.foundation.lazy.LazyListScope
import com.genesis.core.cloud.community.GroupSummary
import com.genesis.core.design.LocalReaderColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private enum class GroupTab { TODAY, PRAYER, NEWS, MEMBERS }

/** What a group shows, loaded together (GroupDetailModel on iOS). */
internal data class GroupContent(
    val posts: List<GroupPost> = emptyList(),
    val prayers: List<GroupPrayer> = emptyList(),
    val prayed: Set<String> = emptySet(),
    val announcements: List<GroupAnnouncement> = emptyList(),
    val members: List<GroupMember> = emptyList(),
    /** Who has read each plan day (today's, and any day opened). */
    val readers: Map<Int, Set<String>> = emptyMap(),
    /** Each member's progress through the plan, by user id. */
    val progress: Map<String, MemberProgress> = emptyMap(),
    /** The days I've marked read. */
    val myDays: Set<Int> = emptySet(),
    val loaded: Boolean = false,
)

/**
 * One group: its discussion, prayer requests, news from its leaders and the
 * people in it. Blocked people's posts and anything reported here are left
 * out; the database still decides who may post, remove or announce.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun GroupScreen(
    groupId: String,
    bible: JournalBible,
    bibleId: String,
    onBack: () -> Unit,
    onRead: (ChapterId) -> Unit,
    modifier: Modifier = Modifier,
    onOpenSermon: ((String) -> Unit)? = null,
) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val store = app.community
    val state by store.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    val group = state.groups.firstOrNull { it.id == groupId }
    var tab by rememberSaveable { mutableStateOf(GroupTab.TODAY) }
    var content by remember { mutableStateOf(GroupContent()) }
    var hidden by remember { mutableStateOf(setOf<String>()) }
    var loadError by remember { mutableStateOf<CommunityError?>(null) }
    var leaving by remember { mutableStateOf(false) }
    var closing by remember { mutableStateOf(false) }
    var moderating by rememberSaveable { mutableStateOf(false) }
    var moderation by remember { mutableStateOf(ModerationContent()) }
    var editing by remember { mutableStateOf(false) }
    var allDays by rememberSaveable { mutableStateOf(false) }
    var openDay by rememberSaveable { mutableStateOf<Int?>(null) }
    var challenges by remember { mutableStateOf(ChallengeContent()) }
    var openChallenge by rememberSaveable { mutableStateOf<String?>(null) }
    var finishedChallenges by rememberSaveable { mutableStateOf(false) }
    var newChallenge by remember { mutableStateOf(false) }

    val planName = group?.plan?.let { groupPlanTitle(group, it) }
    val widgetLanguage = bible.language

    suspend fun reload() {
        val api = store.api ?: return
        try {
            val today = group?.planDay()
            content = withContext(Dispatchers.IO) {
                val prayers = api.prayers(groupId)
                val hasPlan = group?.plan != null
                GroupContent(
                    readers = if (today != null && today > 0) content.readers + (today to api.readers(groupId, today)) else content.readers,
                    progress = if (hasPlan) api.progressSummary(groupId).associateBy { it.userId.lowercase() } else emptyMap(),
                    myDays = if (hasPlan) api.myReadDays(groupId) else emptySet(),
                    posts = api.posts(groupId),
                    prayers = prayers,
                    prayed = api.myPrayerMarks(prayers.map { it.id }),
                    announcements = api.announcements(groupId),
                    members = api.members(groupId),
                    loaded = true,
                )
            }
            loadError = null
            writeGroupWidget(app, group, planName, widgetLanguage, content, state.blocked)
        } catch (error: CommunityError) {
            loadError = error
            content = content.copy(loaded = true)
        }
    }
    suspend fun reloadChallenges() {
        val api = store.challenges ?: return
        runCatching { withContext(Dispatchers.IO) { loadChallenges(api, groupId) } }.onSuccess { challenges = it }
    }
    suspend fun reloadModeration() {
        if (group?.isLeader == true) runCatching { moderation = loadModeration(app, groupId) }
    }
    LaunchedEffect(groupId) {
        reload()
        reloadChallenges()
    }
    LaunchedEffect(groupId, group?.isLeader, moderating) { if (!moderating) reloadModeration() }

    if (moderating && group != null) {
        ModerationScreen(group, onChanged = { store.refreshGroups(); reload() }, onDone = { moderating = false })
        return
    }

    fun shows(user: String, id: String) = user.lowercase() !in state.blocked && id !in hidden

    /** Marks a plan day read (or not), showing it at once and putting it back if saving fails. */
    fun setRead(done: Boolean, day: Int) {
        val me = state.userId ?: return
        val before = content
        val readers = (content.readers[day] ?: if (day in content.myDays) setOf(me) else emptySet()).let { if (done) it + me else it - me }
        val changed = done != (day in content.myDays)
        val old = content.progress[me] ?: MemberProgress(me, 0, 0)
        content = content.copy(
            readers = content.readers + (day to readers),
            myDays = if (done) content.myDays + day else content.myDays - day,
            progress = if (!changed) content.progress else content.progress + (me to old.copy(
                daysDone = maxOf(0, old.daysDone + if (done) 1 else -1),
                lastDay = if (done) maxOf(old.lastDay, day) else old.lastDay,
            )),
        )
        scope.launch { if (!store.perform { it.setDayDone(done, day, groupId) }) content = before }
    }
    fun loadReaders(day: Int) {
        scope.launch {
            val api = store.api ?: return@launch
            runCatching { withContext(Dispatchers.IO) { api.readers(groupId, day) } }.onSuccess { content = content.copy(readers = content.readers + (day to it)) }
        }
    }
    BackHandler(enabled = openDay != null || allDays || openChallenge != null || finishedChallenges) {
        when {
            openChallenge != null -> openChallenge = null
            finishedChallenges -> finishedChallenges = false
            openDay != null -> openDay = null
            else -> allDays = false
        }
    }

    /** Ticks a challenge item, showing it at once and putting it back if saving fails. */
    fun tick(challengeId: String, done: Boolean, item: Int) {
        val me = state.userId ?: return
        val before = challenges
        val rows = challenges.progress[challengeId].orEmpty().toMutableList()
        val index = rows.indexOfFirst { it.userId.equals(me, ignoreCase = true) }.takeIf { it >= 0 }
            ?: rows.size.also { rows += ChallengeProgress(me, state.profile?.displayName.orEmpty(), 0, emptyList()) }
        val items = rows[index].items.orEmpty().toMutableSet().apply { if (done) add(item) else remove(item) }
        rows[index] = rows[index].copy(items = items.sorted(), done = items.size)
        challenges = challenges.copy(progress = challenges.progress + (challengeId to rows))
        scope.launch {
            if (store.performChallenge { it.setCheckin(done, item, challengeId) }) {
                store.challenges?.let { api -> runCatching { withContext(Dispatchers.IO) { api.progress(challengeId) } }.onSuccess { challenges = challenges.copy(progress = challenges.progress + (challengeId to it)) } }
            } else {
                challenges = before
            }
        }
    }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding().imePadding()) {
        Row(Modifier.padding(start = 4.dp, end = 4.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            // Inside a challenge or a plan day the button goes back one step, to the group.
            val inside = openChallenge != null || finishedChallenges || openDay != null || allDays
            TextButton(onClick = {
                when {
                    openChallenge != null -> openChallenge = null
                    finishedChallenges -> finishedChallenges = false
                    openDay != null -> openDay = null
                    allDays -> allDays = false
                    else -> onBack()
                }
            }) {
                val label = if (inside && group != null) group.name else stringResource(R.string.tab_together)
                Text("‹ $label", color = colors.accent, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 220.dp))
            }
            Spacer(Modifier.weight(1f))
            if (group?.isLeader == true) {
                TextButton(onClick = { moderating = true }) {
                    val count = moderation.pendingCount
                    Text(stringResource(R.string.moderation) + if (count > 0) " ($count)" else "", color = colors.accent)
                }
            }
            if (group != null) GroupMenu(isLeader = group.isLeader, isOwner = group.isOwner, onEdit = { editing = true }, onLeave = { leaving = true }, onClose = { closing = true })
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
                options = listOf(stringResource(R.string.group_today), stringResource(R.string.prayer_tab), stringResource(R.string.news), stringResource(R.string.members)),
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
        var refreshing by remember { mutableStateOf(false) }
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    store.refreshGroups()
                    reload()
                    reloadChallenges()
                    reloadModeration()
                    refreshing = false
                }
            },
            modifier = Modifier.weight(1f),
        ) { Column(Modifier.fillMaxSize()) {
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
        val plan = group.plan
        val today = group.planDay()
        fun posts(day: Int?) = content.posts.filter { it.day == day && shows(it.userId, it.id) }
        val postMenu = { post: GroupPost -> menu(ContentKind.GROUP_POST, post.id, post.userId, post.displayName) }
        fun send(day: Int?): suspend (String) -> Boolean = { body -> store.perform { it.addPost(body, day, groupId) }.also { if (it) reload() } }
        val visibleMembers = content.members.filter { it.userId.lowercase() !in state.blocked }
        openChallenge?.let { id ->
            val challenge = challenges.challenges.firstOrNull { it.id == id }
            LaunchedEffect(id) {
                store.challenges?.let { api -> runCatching { withContext(Dispatchers.IO) { api.progress(id) } }.onSuccess { challenges = challenges.copy(progress = challenges.progress + (id to it)) } }
            }
            ChallengeScreen(
                challenge = challenge,
                rows = challenges.progress[id].orEmpty().filter { store.isMine(it.userId) || it.userId.lowercase() !in state.blocked },
                me = state.userId,
                canManage = group.isLeader,
                bible = bible,
                onTick = { done, item -> tick(id, done, item) },
                onRead = onRead,
                onPrayers = {
                    openChallenge = null
                    finishedChallenges = false
                    tab = GroupTab.PRAYER
                },
                onEnd = { scope.launch { if (store.performChallenge { it.end(id) }) reloadChallenges() } },
            )
            return@Column
        }
        if (finishedChallenges) {
            FinishedChallenges(challenges, onOpen = { openChallenge = it })
            return@Column
        }
        val day = openDay
        if (plan != null && day != null) {
            LaunchedEffect(day) { loadReaders(day) }
            PlanDayView(group, plan, day, today ?: 0, content, visibleMembers, store::isMine, posts(day), postMenu, onRead, ::setRead, send(day))
            return@Column
        }
        if (plan != null && allDays) {
            PlanDaysView(group, plan, today ?: 0, content, countFor = { posts(it).size }, onOpen = { openDay = it })
            return@Column
        }
        when (tab) {
            GroupTab.TODAY -> {
                val discussionDay = today?.takeIf { it > 0 }
                Discussion(
                    posts = posts(discussionDay),
                    menu = postMenu,
                    title = if (discussionDay != null) R.string.todays_discussion else null,
                    empty = if (discussionDay != null) R.string.stood_out_today else R.string.start_conversation,
                    placeholder = if (discussionDay != null) R.string.thought_today else R.string.write_message,
                    onSend = send(discussionDay),
                    header = {
                        if (plan != null && today != null) item {
                            TodayCard(group, plan, today, content, visibleMembers.size, onRead, onSetRead = { setRead(it, today) })
                        }
                        if (plan != null && today != null && today > 0) item {
                            ProgressCard(plan, today, content, visibleMembers, store::isMine, onAllDays = { allDays = true })
                        }
                        if (group.isChurch && onOpenSermon != null) item {
                            val app = androidx.compose.ui.platform.LocalContext.current.applicationContext as com.genesis.app.VerselyApplication
                            com.genesis.app.churchsermons.GroupSermonsCard(group, app.community.sermons, app.hiddenChurches, onOpenSermon)
                        }
                        item {
                            ChallengesCard(
                                challenges,
                                me = state.userId,
                                canManage = group.isLeader,
                                onOpen = { openChallenge = it },
                                onFinished = { finishedChallenges = true },
                                onNew = { newChallenge = true },
                            )
                        }
                    },
                )
            }
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
        } }
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
    if (newChallenge && group != null) {
        NewChallengeDialog(
            bible = bible,
            bibleId = bibleId,
            onCreate = { draft ->
                var id: String? = null
                val created = store.performChallenge { id = it.create(draft, groupId) }
                if (created) {
                    newChallenge = false
                    reloadChallenges()
                    openChallenge = id
                }
                created
            },
            onCancel = { newChallenge = false; store.clearError() },
        )
    }
    if (editing && group != null) {
        GroupForm(existing = group, onSaved = { editing = false; scope.launch { reload() } }, onCancel = { editing = false; store.clearError() })
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
private fun GroupMenu(isLeader: Boolean, isOwner: Boolean, onEdit: () -> Unit, onLeave: () -> Unit, onClose: () -> Unit) {
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
            if (isLeader) DropdownMenuItem(text = { Text(stringResource(R.string.edit_group)) }, onClick = { open = false; onEdit() })
            DropdownMenuItem(text = { Text(stringResource(R.string.leave_group)) }, onClick = { open = false; onLeave() })
            if (isOwner) DropdownMenuItem(text = { Text(stringResource(R.string.close_group)) }, onClick = { open = false; onClose() })
        }
    }
}

/** A post, prayer or announcement: who, when, the words, and its menu. */
@Composable
internal fun Entry(name: String, time: String, menu: @Composable () -> Unit, content: @Composable () -> Unit) {
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
internal fun Composer(placeholder: Int, action: Int, onSend: suspend (String) -> Boolean) {
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
internal fun Discussion(
    posts: List<GroupPost>,
    menu: (GroupPost) -> @Composable () -> Unit,
    title: Int?,
    empty: Int,
    placeholder: Int,
    onSend: suspend (String) -> Boolean,
    header: LazyListScope.() -> Unit = {},
) {
    val colors = LocalReaderColors.current
    val list = rememberLazyListState()
    Column(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            header()
            title?.let { item { Text(stringResource(it).uppercase(), style = MaterialTheme.typography.labelMedium, color = colors.secondaryText, modifier = Modifier.padding(start = 4.dp, top = 8.dp)) } }
            if (posts.isEmpty()) item {
                Text(stringResource(empty), style = MaterialTheme.typography.bodyLarge, color = colors.secondaryText, modifier = Modifier.padding(horizontal = 4.dp, vertical = 12.dp))
            }
            items(posts, key = { it.id }) { post ->
                Entry(post.displayName, relativeTime(post.createdAt), menu(post)) {
                    Text(post.body, style = MaterialTheme.typography.bodyLarge, color = colors.text)
                }
            }
        }
        HorizontalDivider(color = colors.separator)
        Composer(placeholder, R.string.send, onSend)
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

/** Keeps the Group Progress widget on this group, as GroupDetailModel does on iOS (groups with a plan only). */
private suspend fun writeGroupWidget(
    app: VerselyApplication,
    group: com.genesis.core.cloud.community.GroupSummary?,
    planName: String?,
    language: String,
    content: GroupContent,
    blocked: Set<String>,
) {
    val plan = group?.plan ?: return
    val day = group.planDay() ?: 0
    val readers = content.readers[day].orEmpty().map { it.lowercase() }.toSet()
    val members = content.members
        .filter { it.userId.lowercase() !in blocked }
        .map { member ->
            val done = content.progress[member.userId.lowercase()]?.daysDone ?: 0
            com.genesis.core.domain.widgets.GroupWidgetSnapshot.Member(
                name = member.displayName,
                fraction = if (plan.dayCount > 0) (done.toDouble() / plan.dayCount).coerceIn(0.0, 1.0) else 0.0,
                readToday = member.userId.lowercase() in readers,
            )
        }
        .sortedWith(compareByDescending<com.genesis.core.domain.widgets.GroupWidgetSnapshot.Member> { it.readToday }.thenByDescending { it.fraction })
    com.genesis.app.widget.GroupWidgetStore.write(
        app,
        com.genesis.core.domain.widgets.GroupWidgetSnapshot(
            groupId = group.id,
            groupName = group.name,
            planTitle = planName ?: "",
            day = day,
            dayCount = plan.dayCount,
            dayTitle = plan.days.getOrNull(day - 1)?.title(language),
            readTodayCount = members.count { it.readToday },
            memberCount = members.size,
            members = members,
            writtenOn = java.time.LocalDate.now().toString(),
        ),
    )
}
