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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.prayer.fieldColors
import com.genesis.core.cloud.community.CommunityComment
import com.genesis.core.cloud.community.CommunityDraft
import com.genesis.core.cloud.community.CommunityError
import com.genesis.core.cloud.community.CommunityPost
import com.genesis.core.cloud.community.CommunityPostKind
import com.genesis.core.cloud.community.ContentKind
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The prayer wall or reflections, as CommunityFeedView on iOS: newest first,
 * "I prayed" / "Amen", comments, and report or block on everything. Only
 * while the server's `community` switch is on; every rule (the word filter,
 * rate limits, anonymous authors) is the database's.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CommunityFeed(kind: CommunityPostKind, language: String, onRead: (ChapterId) -> Unit) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val store = app.community
    val state by store.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    val posts = remember(kind) { mutableStateListOf<CommunityPost>() }
    var reacted by remember(kind) { mutableStateOf(emptySet<String>()) }
    var hidden by remember(kind) { mutableStateOf(emptySet<String>()) }
    var loading by remember(kind) { mutableStateOf(false) }
    var reachedEnd by remember(kind) { mutableStateOf(false) }
    var error by remember(kind) { mutableStateOf<CommunityError?>(null) }
    var composing by rememberSaveable { mutableStateOf(false) }
    var guidelines by rememberSaveable { mutableStateOf(false) }
    var openPost by rememberSaveable { mutableStateOf<String?>(null) }

    suspend fun load(more: Boolean) {
        val api = store.api ?: return
        if (loading || (more && reachedEnd)) return
        loading = true
        try {
            val before = if (more) posts.lastOrNull()?.createdAt else null
            val (page, mine) = withContext(Dispatchers.IO) {
                val page = api.feed(kind, before)
                page to api.myReactions(page.map { it.id })
            }
            if (more) {
                val known = posts.map { it.id }.toSet()
                posts += page.filter { it.id !in known }
                reacted = reacted + mine
            } else {
                posts.clear(); posts += page
                reacted = mine
            }
            reachedEnd = page.size < CommunityDraft.PAGE
            error = null
        } catch (failure: CommunityError) {
            error = failure
        } finally {
            loading = false
        }
    }

    fun toggle(post: CommunityPost) {
        val api = store.api ?: return
        val reacting = post.id.lowercase() !in reacted
        fun apply(on: Boolean) {
            reacted = if (on) reacted + post.id.lowercase() else reacted - post.id.lowercase()
            val index = posts.indexOfFirst { it.id == post.id }
            if (index >= 0) posts[index] = posts[index].copy(reactionCount = maxOf(0, posts[index].reactionCount + if (on) 1 else -1))
        }
        apply(reacting)
        scope.launch {
            try {
                withContext(Dispatchers.IO) { api.setReacted(reacting, post.id) }
            } catch (failure: CommunityError) {
                apply(!reacting)
                error = failure
            }
        }
    }

    LaunchedEffect(kind) { load(more = false) }

    val visible = posts.filter { post -> post.id !in hidden && (post.authorId?.lowercase()?.let { it !in state.blocked } ?: true) }
    openPost?.let { id ->
        val post = posts.firstOrNull { it.id == id }
        if (post != null) {
            BackHandler { openPost = null }
            PostDetail(
                post = post,
                reacted = post.id.lowercase() in reacted,
                language = language,
                onReact = { toggle(post) },
                onRead = onRead,
                onRemoved = { posts.removeAll { it.id == id }; openPost = null },
                onHidden = { hidden = hidden + id; openPost = null },
                onCommented = { scope.launch { load(more = false) } },
                onBack = { openPost = null },
            )
            return
        }
    }

    var refreshing by remember { mutableStateOf(false) }
    PullToRefreshBox(isRefreshing = refreshing, onRefresh = { scope.launch { refreshing = true; load(more = false); refreshing = false } }) {
        LazyColumn(Modifier.fillMaxSize().widthIn(max = 720.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Column(Modifier.fillMaxWidth()) {
                    Text(
                        stringResource(if (kind == CommunityPostKind.PRAYER) R.string.share_prayer_request else R.string.share_reflection),
                        style = MaterialTheme.typography.bodyLarge,
                        color = colors.accent,
                        modifier = Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(16.dp))
                            .clickable { if (state.profile?.hasAcceptedTerms == true) composing = true else guidelines = true }
                            .padding(16.dp),
                    )
                    Text(
                        stringResource(if (kind == CommunityPostKind.PRAYER) R.string.prayer_wall_footer else R.string.reflections_footer),
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.secondaryText,
                        modifier = Modifier.padding(start = 16.dp, top = 6.dp, end = 16.dp),
                    )
                }
            }
            error?.let { item { Text(stringResource(it.text()), color = colors.accent, style = MaterialTheme.typography.bodySmall) } }
            if (visible.isEmpty() && !loading) {
                item {
                    Column(Modifier.fillMaxWidth().padding(vertical = 32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            stringResource(if (kind == CommunityPostKind.PRAYER) R.string.no_prayer_requests_yet else R.string.no_reflections_yet),
                            style = MaterialTheme.typography.titleMedium, color = colors.text,
                        )
                        Spacer(Modifier.size(6.dp))
                        Text(
                            stringResource(if (kind == CommunityPostKind.PRAYER) R.string.first_to_share_request else R.string.share_what_reading),
                            style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, textAlign = TextAlign.Center,
                        )
                    }
                }
            }
            items(visible, key = { it.id }) { post ->
                PostCard(
                    post = post,
                    reacted = post.id.lowercase() in reacted,
                    language = language,
                    onReact = { toggle(post) },
                    onComments = { openPost = post.id },
                    onRead = onRead,
                    onRemoved = { posts.removeAll { it.id == post.id } },
                    onHidden = { hidden = hidden + post.id },
                )
                if (post.id == visible.lastOrNull()?.id) LaunchedEffect(post.id) { load(more = true) }
            }
            if (loading) item { Box(Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp), color = colors.accent) } }
        }
    }

    if (guidelines) {
        Guidelines(onAccepted = { guidelines = false; composing = true }, onCancel = { guidelines = false }, community = true)
    }
    if (composing) {
        Compose(kind, language, onPosted = { composing = false; scope.launch { load(more = false) } }, onCancel = { composing = false; store.clearError() })
    }
}

/** "Psalm 23" or "John 3:16–18" for a post's verse ids (verse 0 is the whole chapter), in the reader's language. */
private fun CommunityPost.referenceLabel(language: String): Pair<String, ChapterId>? {
    val (startRaw, endRaw) = passage ?: return null
    val start = VerseId(startRaw)
    val chapter = start.chapterId
    if (start.verse == 0) return chapter.description(language) to chapter
    return ReferenceParser.describe(startRaw, maxOf(startRaw, endRaw), language) to chapter
}

@Composable
private fun PostCard(
    post: CommunityPost,
    reacted: Boolean,
    language: String,
    onReact: () -> Unit,
    onComments: (() -> Unit)?,
    onRead: (ChapterId) -> Unit,
    onRemoved: () -> Unit,
    onHidden: () -> Unit,
) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val store = app.community
    val colors = LocalReaderColors.current
    Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(16.dp)).padding(start = 16.dp, top = 12.dp, end = 4.dp, bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(post.displayName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = colors.text)
                Text(relativeTime(post.createdAt), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                if (post.hiddenAt != null) Text(stringResource(R.string.under_review), style = MaterialTheme.typography.labelSmall, color = colors.accent)
            }
            ContentMenu(
                authorName = post.displayName,
                isMine = post.isMine,
                canRemove = post.isMine,
                onRemove = { if (store.perform { it.remove(ContentKind.COMMUNITY_POST, post.id) }) onRemoved() },
                onReport = { reason -> store.report(ContentKind.COMMUNITY_POST, post.id, reason) },
                onBlock = { if (store.perform { it.blockPostAuthor(post.id) }) { store.refresh(); onHidden() } },
                onHidden = onHidden,
            )
        }
        post.referenceLabel(language)?.let { (label, chapter) ->
            Text(
                "📖 $label",
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
                color = colors.accent,
                modifier = Modifier.clickable { onRead(chapter) },
            )
        }
        Text(post.body, style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.padding(end = 12.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            val title = stringResource(if (post.postKind == CommunityPostKind.PRAYER) R.string.i_prayed else R.string.amen)
            TextButton(onClick = onReact) {
                Text(
                    (if (reacted) "✓ " else "") + if (post.reactionCount > 0) "$title · ${post.reactionCount}" else title,
                    color = if (reacted) colors.accent else colors.secondaryText,
                    fontWeight = if (reacted) FontWeight.SemiBold else FontWeight.Normal,
                )
            }
            if (onComments != null) {
                TextButton(onClick = onComments) {
                    Text(if (post.commentCount > 0) "💬 ${post.commentCount}" else stringResource(R.string.comment), color = colors.secondaryText)
                }
            }
        }
    }
}

/** A post and its comments, as CommunityPostDetailView on iOS. */
@Composable
private fun PostDetail(
    post: CommunityPost,
    reacted: Boolean,
    language: String,
    onReact: () -> Unit,
    onRead: (ChapterId) -> Unit,
    onRemoved: () -> Unit,
    onHidden: () -> Unit,
    onCommented: () -> Unit,
    onBack: () -> Unit,
) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val store = app.community
    val state by store.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    val comments = remember(post.id) { mutableStateListOf<CommunityComment>() }
    var draft by rememberSaveable(post.id) { mutableStateOf("") }
    var error by remember { mutableStateOf<CommunityError?>(null) }
    var sending by remember { mutableStateOf(false) }
    var guidelines by remember { mutableStateOf(false) }
    var hiddenComments by remember(post.id) { mutableStateOf(emptySet<String>()) }

    suspend fun load() {
        val api = store.api ?: return
        try {
            val rows = withContext(Dispatchers.IO) { api.comments(post.id) }
            comments.clear(); comments += rows
            error = null
        } catch (failure: CommunityError) {
            error = failure
        }
    }
    LaunchedEffect(post.id) { load() }

    fun send() {
        if (state.profile?.hasAcceptedTerms != true) { guidelines = true; return }
        sending = true
        scope.launch {
            if (store.perform { it.addComment(draft, post.id) }) {
                draft = ""
                load()
                onCommented()
            } else {
                error = store.state.value.error
            }
            sending = false
        }
    }

    Column(Modifier.fillMaxSize().background(colors.background)) {
        Row(Modifier.padding(start = 8.dp, end = 8.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ " + stringResource(R.string.back), color = colors.accent) }
            Text(
                stringResource(if (post.postKind == CommunityPostKind.PRAYER) R.string.prayer_request else R.string.reflection),
                style = MaterialTheme.typography.titleMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
        }
        LazyColumn(Modifier.weight(1f).fillMaxWidth().widthIn(max = 720.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { PostCard(post, reacted, language, onReact, onComments = null, onRead = onRead, onRemoved = onRemoved, onHidden = onHidden) }
            item { Text(stringResource(R.string.comments), style = MaterialTheme.typography.titleSmall, color = colors.secondaryText, modifier = Modifier.padding(top = 8.dp, start = 4.dp)) }
            val shown = comments.filter { it.id !in hiddenComments && it.userId.lowercase() !in state.blocked }
            items(shown, key = { it.id }) { comment ->
                Row(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(12.dp)).padding(start = 14.dp, top = 10.dp, bottom = 10.dp, end = 4.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(comment.displayName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = colors.text)
                            Text(relativeTime(comment.createdAt), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                        }
                        Text(comment.body, color = colors.text)
                    }
                    val mine = store.isMine(comment.userId)
                    ContentMenu(
                        authorName = comment.displayName,
                        isMine = mine,
                        canRemove = mine,
                        onRemove = { if (store.perform { it.remove(ContentKind.COMMUNITY_COMMENT, comment.id) }) comments.removeAll { it.id == comment.id } },
                        onReport = { reason -> store.report(ContentKind.COMMUNITY_COMMENT, comment.id, reason) },
                        onBlock = { store.block(comment.userId) },
                        onHidden = { hiddenComments = hiddenComments + comment.id },
                    )
                }
            }
            error?.let { item { Text(stringResource(it.text()), color = colors.accent, style = MaterialTheme.typography.bodySmall) } }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.Bottom) {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it.take(CommunityDraft.MAXIMUM_LENGTH) },
                placeholder = { Text(stringResource(if (post.postKind == CommunityPostKind.PRAYER) R.string.send_encouragement else R.string.add_a_comment)) },
                maxLines = 5,
                colors = fieldColors(),
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = ::send, enabled = draft.isNotBlank() && !sending) {
                Text(stringResource(R.string.send), color = colors.accent, fontWeight = FontWeight.SemiBold)
            }
        }
    }
    if (guidelines) {
        Guidelines(onAccepted = { guidelines = false; send() }, onCancel = { guidelines = false }, community = true)
    }
}

/** Write a prayer request or reflection, as CommunityComposeView on iOS: a passage links by its ids, never quoted. */
@Composable
private fun Compose(kind: CommunityPostKind, language: String, onPosted: () -> Unit, onCancel: () -> Unit) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val store = app.community
    val state by store.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    var body by rememberSaveable { mutableStateOf("") }
    var passage by rememberSaveable { mutableStateOf("") }
    var anonymous by rememberSaveable { mutableStateOf(false) }
    val reference = remember(passage) { if (passage.isBlank()) null else ReferenceParser.parse(passage, portugueseFirst = language == "pt") }
    val canPost = body.isNotBlank() && body.trim().length <= CommunityDraft.MAXIMUM_LENGTH && (passage.isBlank() || reference != null) && !state.isWorking
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(stringResource(if (kind == CommunityPostKind.PRAYER) R.string.prayer_request else R.string.reflection)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = body,
                    onValueChange = { body = it.take(CommunityDraft.MAXIMUM_LENGTH) },
                    placeholder = { Text(stringResource(if (kind == CommunityPostKind.PRAYER) R.string.what_can_people_pray_for else R.string.what_did_you_notice)) },
                    minLines = 4,
                    maxLines = 10,
                    colors = fieldColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
                Text("${body.length}/${CommunityDraft.MAXIMUM_LENGTH}", style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                OutlinedTextField(
                    value = passage,
                    onValueChange = { passage = it },
                    placeholder = { Text(stringResource(R.string.passage_optional)) },
                    singleLine = true,
                    colors = fieldColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
                if (passage.isNotBlank()) {
                    Text(
                        reference?.description(language) ?: stringResource(R.string.not_a_passage),
                        style = MaterialTheme.typography.bodySmall,
                        color = if (reference == null) colors.accent else colors.secondaryText,
                    )
                }
                if (kind == CommunityPostKind.PRAYER) {
                    Row(Modifier.clickable { anonymous = !anonymous }, verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = anonymous, onCheckedChange = { anonymous = it }, colors = CheckboxDefaults.colors(checkedColor = colors.accent))
                        Text(stringResource(R.string.post_anonymously), color = colors.text)
                    }
                }
                Text(stringResource(R.string.posts_link_passage), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                state.error?.let { Text(stringResource(it.text()), color = colors.accent, style = MaterialTheme.typography.bodySmall) }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                // Verse 0 stands for the whole chapter.
                val draft = reference?.let {
                    val chapter = it.chapter ?: 1
                    CommunityDraft(
                        kind, body,
                        start = VerseId(it.book.id, chapter, it.verseStart ?: 0).rawValue,
                        end = it.verseEnd?.let { end -> VerseId(it.book.id, chapter, end).rawValue },
                        isAnonymous = anonymous && kind == CommunityPostKind.PRAYER,
                    )
                } ?: CommunityDraft(kind, body, isAnonymous = anonymous && kind == CommunityPostKind.PRAYER)
                scope.launch { if (store.perform { it.addCommunityPost(draft) }) onPosted() }
            }, enabled = canPost) { Text(stringResource(R.string.post), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        },
        dismissButton = { TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel), color = colors.secondaryText) } },
    )
}
