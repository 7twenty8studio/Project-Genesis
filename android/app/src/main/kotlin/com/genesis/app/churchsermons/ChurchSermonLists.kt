package com.genesis.app.churchsermons

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
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
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.prayer.fieldColors
import com.genesis.core.cloud.community.ChurchSermonApi
import com.genesis.core.cloud.community.ChurchSermonAudience
import com.genesis.core.cloud.community.ChurchSermonLink
import com.genesis.core.cloud.community.ChurchSermonSummary
import com.genesis.core.cloud.community.CommunityError
import com.genesis.core.cloud.community.GroupSummary
import com.genesis.core.cloud.community.SermonChurch
import com.genesis.core.design.LocalReaderColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** A sermon in a list: title, speaker, date and series, and whether it's for members. */
@Composable
internal fun ChurchSermonRow(sermon: ChurchSermonSummary, onOpen: () -> Unit) {
    val colors = LocalReaderColors.current
    Column(Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(sermon.title.ifEmpty { stringResource(R.string.sermon_untitled) }, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, color = colors.text)
        val date = sermon.preachedDate?.let { DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(it) }
        val line = listOfNotNull(sermon.speaker.ifEmpty { null }, date, sermon.series).joinToString(" · ")
        if (line.isNotEmpty()) Text(line, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        if (sermon.audience == ChurchSermonAudience.MEMBERS) Text("👥 " + stringResource(R.string.members_only), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
    }
}

/**
 * A church group's published sermons, newest first, as GroupSermonsSection
 * on iOS. Shown only where the church has sermons on (the server refuses the
 * list otherwise): to members once there's one, and straight away to the
 * owner, admins and preachers, who publish from Church Studio on the web.
 */
@Composable
fun GroupSermonsCard(group: GroupSummary, api: ChurchSermonApi?, hidden: HiddenChurches, onOpen: (String) -> Unit) {
    val colors = LocalReaderColors.current
    val android = LocalContext.current
    val hiddenIds by hidden.ids.collectAsState()
    val sermons by produceState<List<ChurchSermonSummary>?>(null, group.id, api) {
        value = if (api == null) null else withContext(Dispatchers.IO) { runCatching { api.archive(group.id) }.getOrNull() }
    }
    var showsAll by rememberSaveable { mutableStateOf(false) }
    val list = sermons ?: return
    val writes = group.isLeader || group.isPreacher
    if (group.id.lowercase() in hiddenIds || (list.isEmpty() && !writes)) return
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.surface).padding(vertical = 8.dp)) {
        Text(
            stringResource(R.string.sermons).uppercase(),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = colors.secondaryText,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp).semantics { heading() },
        )
        if (list.isEmpty()) Text(stringResource(R.string.group_sermons_empty), color = colors.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
        (if (showsAll) list else list.take(3)).forEach { sermon -> ChurchSermonRow(sermon) { onOpen(sermon.slug) } }
        if (list.size > 3) {
            TextButton(onClick = { showsAll = !showsAll }, modifier = Modifier.padding(horizontal = 4.dp)) {
                Text(if (showsAll) stringResource(R.string.show_less) else stringResource(R.string.show_all_count, list.size), color = colors.accent)
            }
        }
        if (writes) {
            TextButton(onClick = { runCatching { android.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(ChurchSermonLink.studio(group.id)))) } }, modifier = Modifier.padding(horizontal = 4.dp)) {
                Text(stringResource(R.string.open_in_church_studio), color = colors.accent)
            }
        }
    }
}

/**
 * Find a church's sermons by its name, as ChurchSearchView on iOS: only
 * churches that chose to be listed, and only their link sermons. No location
 * is asked for or sent.
 */
@Composable
fun ChurchSearchScreen(api: ChurchSermonApi?, hidden: HiddenChurches, onOpen: (String) -> Unit, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    BackHandler(onBack = onDone)
    var query by rememberSaveable { mutableStateOf("") }
    var results by remember { mutableStateOf<List<SermonChurch>>(emptyList()) }
    var searched by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<Int?>(null) }
    val hiddenIds by hidden.ids.collectAsState()
    LaunchedEffect(query) {
        val trimmed = query.trim()
        if (trimmed.length < 2 || api == null) {
            results = emptyList()
            searched = false
            return@LaunchedEffect
        }
        // Wait for a pause in typing.
        delay(350)
        try {
            results = withContext(Dispatchers.IO) { api.searchChurches(trimmed) }
            error = null
        } catch (failure: CommunityError) {
            error = failure.sermonText()
        }
        searched = true
    }
    val shown = results.filter { it.id !in hiddenIds }
    Column(modifier.fillMaxSize().background(colors.background).imePadding()) {
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.find_a_church),
                style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        LazyColumn(contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    placeholder = { Text(stringResource(R.string.church_search_hint)) },
                    singleLine = true,
                    colors = fieldColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            when {
                query.trim().length < 2 -> item { Text(stringResource(R.string.church_search_intro), color = colors.secondaryText) }
                searched && shown.isEmpty() -> item { Text(stringResource(R.string.church_search_none, query.trim()), color = colors.secondaryText) }
            }
            error?.let { item { Text(stringResource(it), style = MaterialTheme.typography.bodySmall, color = androidx.compose.ui.graphics.Color(0xFFC77700)) } }
            items(shown, key = { it.id }) { church ->
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.surface).padding(vertical = 8.dp)) {
                    Text(church.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = colors.text, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                    if (church.sermons.isEmpty()) Text(stringResource(R.string.church_no_link_sermons), color = colors.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                    church.sermons.forEachIndexed { index, sermon ->
                        if (index > 0) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                        ChurchSermonRow(sermon) { onOpen(sermon.slug) }
                    }
                }
            }
        }
    }
}
