package com.genesis.app.churchsermons

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.genesis.app.R
import com.genesis.core.cloud.community.ChurchPassageBible
import com.genesis.core.cloud.community.ChurchSermonEvent
import com.genesis.core.cloud.community.ChurchSermonLink
import com.genesis.core.cloud.community.ChurchSermonLookup
import com.genesis.core.cloud.community.ChurchSermonSummary
import com.genesis.core.cloud.community.CommunityError
import com.genesis.core.cloud.community.PublishedSermon
import com.genesis.core.cloud.community.ReportReason
import com.genesis.core.cloud.community.SermonAnswers
import com.genesis.core.cloud.community.SermonBlanks
import com.genesis.core.cloud.community.SermonOutline
import com.genesis.core.cloud.community.SermonReference
import com.genesis.app.together.title
import com.genesis.core.design.LocalReaderColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

private sealed interface LoadState {
    data object Loading : LoadState
    data class Loaded(val lookup: ChurchSermonLookup) : LoadState
    data class Failed(val message: Int) : LoadState
}

/**
 * Opens a church sermon by its link's slug, as ChurchSermonScreen on iOS:
 * the outline, or why it can't be shown (members only, no longer available,
 * hidden by the person, or switched off). Asked again each time it opens,
 * on sign-in and on return to the app, so an unpublish applies at once.
 */
@Composable
fun ChurchSermonScreen(initialSlug: String, context: ChurchSermonContext, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    var slug by rememberSaveable(initialSlug) { mutableStateOf(initialSlug) }
    var state by remember { mutableStateOf<LoadState>(LoadState.Loading) }
    var reloads by remember { mutableStateOf(0) }
    val hidden by context.hidden.ids.collectAsState()
    BackHandler(onBack = onDone)

    LaunchedEffect(slug, context.isSignedIn, reloads) {
        val api = context.api
        if (!context.isAvailable || api == null) return@LaunchedEffect
        val shown = (state as? LoadState.Loaded)?.lookup as? ChurchSermonLookup.Found
        if (shown != null && shown.sermon.slug != slug) state = LoadState.Loading
        state = try {
            LoadState.Loaded(withContext(Dispatchers.IO) { api.sermon(slug) })
        } catch (error: CommunityError) {
            // Keep a sermon already on screen when a refresh fails offline.
            if (state is LoadState.Loaded && (state as LoadState.Loaded).lookup is ChurchSermonLookup.Found) return@LaunchedEffect
            LoadState.Failed(error.sermonText())
        }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { reloads++ }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding().imePadding()) {
        val current = state
        val sermon = ((current as? LoadState.Loaded)?.lookup as? ChurchSermonLookup.Found)?.sermon?.takeUnless { it.groupId in hidden }
        if (sermon == null) {
            Row(Modifier.fillMaxWidth().padding(start = 8.dp, end = 8.dp, top = 8.dp)) {
                Box(Modifier.weight(1f))
                TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
            }
        }
        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            when {
                !context.isAvailable || context.api == null -> Message(R.string.church_sermons_unavailable, stringResource(R.string.church_sermons_unavailable_message))
                current is LoadState.Loading -> CircularProgressIndicator(color = colors.accent)
                current is LoadState.Failed -> Message(R.string.sermon_failed, stringResource(current.message)) {
                    Pill(stringResource(R.string.try_again)) { reloads++ }
                }
                current is LoadState.Loaded -> when (val lookup = current.lookup) {
                    ChurchSermonLookup.NotFound -> Message(R.string.sermon_not_found, stringResource(R.string.sermon_not_found_message))
                    ChurchSermonLookup.MembersOnly -> Message(
                        R.string.for_church_members,
                        stringResource(if (context.isSignedIn) R.string.members_only_join else R.string.members_only_sign_in),
                    ) {
                        if (!context.isSignedIn) Pill(stringResource(R.string.sign_in), filled = true, onClick = context.onSignIn)
                    }
                    is ChurchSermonLookup.Found -> if (lookup.sermon.groupId in hidden) {
                        Message(R.string.church_hidden, stringResource(R.string.church_hidden_message), titleArgument = lookup.sermon.church) {
                            Pill(stringResource(R.string.show_sermons_from, lookup.sermon.church)) { context.hidden.set(lookup.sermon.groupId, false) }
                        }
                    } else {
                        PublishedSermonView(lookup.sermon, context, onOpenSermon = { slug = it }, onDone = onDone)
                    }
                }
            }
        }
    }
}

@Composable
private fun Message(title: Int, detail: String, titleArgument: String? = null, action: @Composable () -> Unit = {}) {
    val colors = LocalReaderColors.current
    Column(Modifier.padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            if (titleArgument != null) stringResource(title, titleArgument) else stringResource(title),
            style = MaterialTheme.typography.titleLarge,
            color = colors.text,
            textAlign = TextAlign.Center,
        )
        Text(detail, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, textAlign = TextAlign.Center)
        action()
    }
}

/**
 * A church's published outline, as PublishedSermonView on iOS: the church's
 * words exactly as published, each verified passage a tap away, Copy for
 * each section, the handout, the series' next and previous, Locations and
 * Times, the person's own notes, and report or hide.
 */
@Composable
private fun PublishedSermonView(sermon: PublishedSermon, context: ChurchSermonContext, onOpenSermon: (String) -> Unit, onDone: () -> Unit) {
    val colors = LocalReaderColors.current
    val android = LocalContext.current
    val scope = rememberCoroutineScope()
    val list = rememberLazyListState()
    val sections = remember(sermon) { SermonOutline.sections(sermon.blocks) }
    val sermons by context.sermons.all.collectAsState()
    val hasNotes = sermons.any { it.sourceSermonId.equals(sermon.id, ignoreCase = true) }
    var passage by remember { mutableStateOf<SermonReference?>(null) }
    var passageBible by rememberSaveable(sermon.slug) { mutableStateOf<String?>(null) }
    var copied by remember { mutableStateOf<String?>(null) }
    var menu by remember { mutableStateOf(false) }
    var jump by remember { mutableStateOf(false) }
    var reporting by remember { mutableStateOf(false) }
    var hiding by remember { mutableStateOf(false) }
    var reportMessage by remember { mutableStateOf<Int?>(null) }
    val shownBible = ChurchPassageBible.shown(ChurchPassageBible.options(context.currentBible, passageBible, null) { it in context.bibles }, passageBible) ?: context.currentBible
    val api = context.api

    LaunchedEffect(sermon.slug) { withContext(Dispatchers.IO) { api?.count(ChurchSermonEvent.OPEN, sermon.slug) } }
    val cover by produceState<android.graphics.Bitmap?>(null, sermon.coverPath) {
        val path = sermon.coverPath ?: return@produceState
        // Asked for each time it's shown, so access is checked again; never saved.
        value = withContext(Dispatchers.IO) { api?.cover(path)?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } }
    }
    val handout = remember(sermon.slug, sermon.revision, sermon.answers) {
        if (!sermon.hasBlanks) null else {
            var saved = ChurchSermonNotes.savedHandout(context.sermons, sermon)
            if (saved != null && sermon.answers == SermonAnswers.REVEALED && !saved.hasKey) {
                ChurchSermonNotes.saveHandout(context.sermons, sermon, saved.responses)
                saved = ChurchSermonNotes.savedHandout(context.sermons, sermon)
            }
            var pending: kotlinx.coroutines.Job? = null
            HandoutState(sermon.blanks, sermon.answers, saved?.responses.orEmpty(), saved?.blanks.orEmpty()) { responses ->
                // Saved privately with the notes a moment after typing stops.
                pending?.cancel()
                pending = scope.launch {
                    delay(600)
                    val isNew = ChurchSermonNotes.existing(context.sermons, sermon.id) == null
                    ChurchSermonNotes.saveHandout(context.sermons, sermon, responses)
                    if (isNew) withContext(Dispatchers.IO) { api?.count(ChurchSermonEvent.SAVE, sermon.slug) }
                }
            }
        }
    }
    val known = sermon.blanks.map { it.n }.toSet()
    fun plain(text: String) = SermonBlanks.filled(text, known::contains)
    fun copy(text: String) {
        (android.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText(sermon.title, text))
    }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 4.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(sermon.church, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text, maxLines = 1, modifier = Modifier.weight(1f))
            val titled = sections.filter { it.title != null }
            if (titled.size > 1) {
                Box {
                    TextButton(onClick = { jump = true }) { Text("☰", color = colors.accent) }
                    DropdownMenu(expanded = jump, onDismissRequest = { jump = false }) {
                        titled.forEach { section ->
                            DropdownMenuItem(text = { Text(plain(section.title.orEmpty())) }, onClick = {
                                jump = false
                                scope.launch { list.animateScrollToItem(1 + sections.indexOf(section)) }
                            })
                        }
                    }
                }
            }
            Box {
                TextButton(onClick = { menu = true }) { Text("•••", color = colors.accent) }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.share)) }, onClick = {
                        menu = false
                        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, ChurchSermonLink.url(sermon.slug))
                        android.startActivity(Intent.createChooser(send, null))
                    })
                    DropdownMenuItem(text = { Text(stringResource(R.string.copy_outline)) }, onClick = {
                        menu = false
                        copy(SermonOutline.copyText(sermon.blocks, sermon.blanks))
                    })
                    DropdownMenuItem(text = { Text(stringResource(R.string.report)) }, onClick = { menu = false; reporting = true })
                    DropdownMenuItem(text = { Text(stringResource(R.string.hide_sermons_from, sermon.church)) }, onClick = { menu = false; hiding = true })
                }
            }
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        LazyColumn(
            state = list,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            item(key = "header") {
                Column(Modifier.widthIn(max = 680.dp).fillMaxWidth().padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    cover?.let { bitmap ->
                        Image(
                            bitmap.asImageBitmap(),
                            contentDescription = sermon.coverAlt.takeUnless { sermon.coverDecorative },
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(16.dp)),
                        )
                    }
                    Text(sermon.church.uppercase(), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.accent)
                    Text(
                        sermon.title.ifEmpty { stringResource(R.string.sermon_untitled) },
                        style = MaterialTheme.typography.headlineLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                        color = colors.text,
                        modifier = Modifier.semantics { heading() },
                    )
                    val date = sermon.preachedDate?.let(::longDate)
                    listOfNotNull(
                        listOfNotNull(sermon.speaker.ifEmpty { null }, date).joinToString(" · ").ifEmpty { null },
                        sermon.series?.let { stringResource(R.string.sermon_series_line, it) },
                        sermon.location.ifEmpty { null },
                    ).forEach { Text(it, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText) }
                    if (sermon.audience == com.genesis.core.cloud.community.ChurchSermonAudience.MEMBERS) {
                        Text("👥 " + stringResource(R.string.sermon_for_members_of, sermon.church), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
                        Pill(stringResource(if (hasNotes) R.string.open_my_notes else R.string.take_notes), filled = true) {
                            val isNew = !hasNotes
                            val notes = ChurchSermonNotes.notes(context.sermons, sermon)
                            if (isNew) scope.launch { withContext(Dispatchers.IO) { api?.count(ChurchSermonEvent.SAVE, sermon.slug) } }
                            context.onOpenNotes(notes.id)
                        }
                        if (sermon.locations.isNotEmpty()) {
                            Pill(stringResource(R.string.locations_and_times)) { scope.launch { list.animateScrollToItem(sections.size + 3) } }
                        }
                    }
                }
            }
            sections.forEach { section ->
                item(key = "section-${section.id}") {
                    Column(Modifier.widthIn(max = 680.dp).fillMaxWidth().padding(vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        section.blocks.forEach { block ->
                            OutlineBlock(block, handout, context.language, shownBible) { reference ->
                                passage = reference
                                scope.launch { withContext(Dispatchers.IO) { api?.count(ChurchSermonEvent.PASSAGE, sermon.slug) } }
                            }
                        }
                        Row(Modifier.fillMaxWidth()) {
                            Box(Modifier.weight(1f))
                            Text(
                                stringResource(if (copied == section.id) R.string.copied else R.string.copy),
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.secondaryText,
                                modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable {
                                    copy(SermonOutline.copyText(section.blocks, sermon.blanks))
                                    copied = section.id
                                }.padding(8.dp),
                            )
                        }
                    }
                }
            }
            item(key = "handout") { handout?.let { Box(Modifier.widthIn(max = 680.dp)) { HandoutBar(it) } } }
            item(key = "next") { sermon.next?.let { JoinNext(it) { onOpenSermon(it.slug) } } }
            item(key = "locations") { if (sermon.locations.isNotEmpty()) Locations(sermon) }
            item(key = "previous") {
                sermon.previous?.let { previous ->
                    Column(Modifier.widthIn(max = 680.dp).fillMaxWidth().padding(top = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        sermon.series?.let { Text(it.uppercase(), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.secondaryText) }
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(colors.surface).clickable { onOpenSermon(previous.slug) }.padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text("‹", style = MaterialTheme.typography.titleLarge, color = colors.secondaryText, modifier = Modifier.padding(end = 12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(stringResource(R.string.previous), style = MaterialTheme.typography.labelSmall, color = colors.secondaryText)
                                Text(previous.title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, color = colors.text)
                            }
                        }
                    }
                }
            }
            item(key = "footer") {
                Text(
                    stringResource(R.string.sermon_shared_by, sermon.church),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.secondaryText,
                    modifier = Modifier.widthIn(max = 680.dp).fillMaxWidth().padding(top = 28.dp),
                )
            }
        }
    }

    passage?.let { reference ->
        ChurchPassageSheet(reference, context, passageBible, onChoose = { passageBible = it }, onDismiss = { passage = null })
    }
    if (reporting) {
        AlertDialog(
            onDismissRequest = { reporting = false },
            title = { Text(stringResource(R.string.report_sermon_question)) },
            text = {
                Column {
                    Text(stringResource(R.string.report_sermon_message))
                    ReportReason.entries.forEach { reason ->
                        TextButton(onClick = {
                            reporting = false
                            scope.launch {
                                reportMessage = try {
                                    withContext(Dispatchers.IO) { api?.report(sermon.slug, reason.value) }
                                    R.string.sermon_report_thanks
                                } catch (error: CommunityError) {
                                    error.sermonText()
                                }
                            }
                        }) { Text(stringResource(reason.title), color = colors.accent) }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { reporting = false }) { Text(stringResource(R.string.cancel)) } },
            containerColor = colors.surface,
            titleContentColor = colors.text,
            textContentColor = colors.text,
        )
    }
    reportMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { reportMessage = null },
            title = { Text(stringResource(R.string.report)) },
            text = { Text(stringResource(message)) },
            confirmButton = { TextButton(onClick = { reportMessage = null }) { Text(stringResource(R.string.ok)) } },
            containerColor = colors.surface,
            titleContentColor = colors.text,
            textContentColor = colors.text,
        )
    }
    if (hiding) {
        AlertDialog(
            onDismissRequest = { hiding = false },
            title = { Text(stringResource(R.string.hide_sermons_question, sermon.church)) },
            text = { Text(stringResource(R.string.hide_sermons_message)) },
            confirmButton = {
                TextButton(onClick = {
                    hiding = false
                    context.hidden.set(sermon.groupId, true)
                }) { Text(stringResource(R.string.hide), color = androidx.compose.ui.graphics.Color(0xFFC0392B)) }
            },
            dismissButton = { TextButton(onClick = { hiding = false }) { Text(stringResource(R.string.cancel), color = colors.accent) } },
            containerColor = colors.surface,
            titleContentColor = colors.text,
            textContentColor = colors.text,
        )
    }
}

@Composable
private fun JoinNext(next: ChurchSermonSummary, onOpen: () -> Unit) {
    val colors = LocalReaderColors.current
    Row(
        Modifier.widthIn(max = 680.dp).fillMaxWidth().padding(top = 24.dp).clip(RoundedCornerShape(16.dp)).background(colors.accent).clickable(onClick = onOpen).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(R.string.join_us_for, next.title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.background)
            next.preachedDate?.let { Text(longDate(it), style = MaterialTheme.typography.bodyMedium, color = colors.background.copy(alpha = 0.9f)) }
        }
        Text("›", style = MaterialTheme.typography.titleLarge, color = colors.background)
    }
}

/** Where and when the church meets, with directions; headed "Join us" when there's no next sermon. */
@Composable
private fun Locations(sermon: PublishedSermon) {
    val colors = LocalReaderColors.current
    val android = LocalContext.current
    val locale = android.resources.configuration.locales[0]
    val names = com.genesis.core.cloud.community.ChurchGathering.Weekday.entries.associateWith { android.getString(it.plural) }
    Column(
        Modifier.widthIn(max = 680.dp).fillMaxWidth().padding(top = 24.dp).clip(RoundedCornerShape(16.dp)).background(colors.surface).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (sermon.next == null) Text(stringResource(R.string.join_us), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, color = colors.text)
        Text(
            stringResource(R.string.locations_and_times).let { if (sermon.next == null) it.uppercase() else it },
            style = if (sermon.next == null) MaterialTheme.typography.labelMedium else MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            color = if (sermon.next == null) colors.secondaryText else colors.text,
            modifier = Modifier.semantics { heading() },
        )
        val today = LocalDate.now().toString()
        sermon.locations.forEach { place ->
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(place.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = colors.text)
                place.scheduleLines(today, locale) { names.getValue(it) }.forEach { Text(it, color = colors.text) }
                place.mapsUrl?.let { url ->
                    Text(
                        "📍 " + place.addressLines.joinToString("\n"),
                        color = colors.accent,
                        modifier = Modifier.clickable { runCatching { android.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } },
                    )
                }
            }
        }
    }
}

internal fun longDate(date: LocalDate): String = DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG).format(date)
