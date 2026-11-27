package com.genesis.app.audio

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.core.design.LocalReaderColors

/**
 * What's playing, from every tab but the reader (which keeps its own bar),
 * as NowPlayingAccessory on iOS: a small player above the tab bar while the
 * Bible is read aloud or ambient sounds are out. Tap it for both players'
 * full controls in one sheet.
 */
@Composable
fun NowPlayingAccessory(showsAmbient: Boolean, modifier: Modifier = Modifier) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val listening by app.listening.state.collectAsStateWithLifecycle()
    val ambient by app.ambient.state.collectAsStateWithLifecycle()
    val ambientOut = showsAmbient && ambient.showsControls && ambient.mix.isNotEmpty()
    var open by rememberSaveable { mutableStateOf(false) }
    val active = listening.isActive || ambientOut
    androidx.compose.runtime.LaunchedEffect(active) { if (!active) open = false }
    if (!active) return

    val title = if (listening.isActive) listening.title else ambient.summary(context)
    val source = stringResource(R.string.device_voice_source, listening.abbreviation)
    // "KJV · Device voice · Rain", as iOS.
    val subtitle = when {
        listening.isActive && ambientOut && ambient.isPlaying -> "$source · ${ambient.summary(context)}"
        listening.isActive -> source
        else -> stringResource(R.string.ambient_sounds_lower)
    }
    val isPlaying = if (listening.isActive) listening.isPlaying else ambient.isPlaying
    val openLabel = "$title, $subtitle"
    val toggleLabel = stringResource(if (isPlaying) R.string.pause else R.string.play)
    val stopLabel = stringResource(R.string.stop)

    Row(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .background(colors.surface, RoundedCornerShape(50))
            .padding(start = 18.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f).clickable { open = true }.semantics(mergeDescendants = true) { contentDescription = openLabel }.padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (listening.isActive) HeadphonesIcon(colors.accent, 20.dp) else Text("♪", color = colors.accent, fontSize = 18.sp)
            Spacer(Modifier.size(10.dp))
            Column {
                Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = colors.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        IconButton(
            onClick = { if (listening.isActive) app.listening.toggle() else app.ambient.togglePlayback() },
            modifier = Modifier.semantics { contentDescription = toggleLabel },
        ) { if (isPlaying) PauseIcon(colors.accent, 20.dp) else PlayIcon(colors.accent, 20.dp) }
        IconButton(
            onClick = {
                if (listening.isActive) app.listening.stop()
                if (ambient.showsControls) app.ambient.close()
            },
            modifier = Modifier.semantics { contentDescription = stopLabel },
        ) { Text("✕", color = colors.secondaryText, fontSize = 14.sp) }
    }

    if (open) NowPlayingSheet(showsAmbient = showsAmbient, onDismiss = { open = false })
}

/** Everything playing in one place, as NowPlayingSheet on iOS: the Bible read aloud and the ambient sounds, each with its own controls. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NowPlayingSheet(showsAmbient: Boolean, onDismiss: () -> Unit) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val colors = LocalReaderColors.current
    val listening by app.listening.state.collectAsStateWithLifecycle()
    val preferences by app.listening.settings.state.collectAsStateWithLifecycle()
    val ambient by app.ambient.state.collectAsStateWithLifecycle()
    var sounds by rememberSaveable { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = colors.background) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                stringResource(R.string.now_playing),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                color = colors.text,
                modifier = Modifier.semantics { heading() },
            )
            if (listening.isActive) ListeningBar(listening, preferences.speed, app.listening)
            if (showsAmbient) {
                val ambientOut = ambient.showsControls && ambient.mix.isNotEmpty()
                if (ambientOut) {
                    Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(16.dp)).padding(start = 14.dp, end = 4.dp, top = 4.dp, bottom = 4.dp)) {
                        AmbientControlsRow(app.ambient, onOpen = { sounds = true })
                    }
                }
                TextButton(onClick = { sounds = true }) {
                    Text(stringResource(if (ambientOut) R.string.change_sounds else R.string.add_ambient_sounds), color = colors.accent)
                }
            }
            Spacer(Modifier.size(12.dp))
        }
    }
    if (sounds) AmbientSoundsSheet(app.ambient) { sounds = false }
}
