package com.genesis.app.audio

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.audio.AmbientMix
import com.genesis.core.domain.audio.AmbientRules
import com.genesis.core.domain.audio.AmbientSound
import java.text.DateFormat
import java.util.Date

/**
 * Choose ambient sounds to read and pray with, as AmbientSoundsView.swift:
 * play/pause with what's in the mix, each sound on or off with its own
 * volume, ready-made mixes and a timer. Premium (callers check).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AmbientSoundsSheet(ambient: AmbientSounds, onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    val state by ambient.state.collectAsState()
    val context = LocalContext.current
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = colors.background,
    ) {
        Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(bottom = 24.dp)) {
            Text(
                stringResource(R.string.ambient_title),
                style = MaterialTheme.typography.titleLarge,
                color = colors.text,
                modifier = Modifier.padding(horizontal = 24.dp).semantics { heading() },
            )

            // Play / pause and what's in the mix.
            Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                val label = stringResource(if (state.isPlaying) R.string.pause else R.string.play)
                IconButton(
                    onClick = ambient::togglePlayback,
                    enabled = state.mix.isNotEmpty(),
                    modifier = Modifier
                        .size(52.dp)
                        .background(if (state.mix.isEmpty()) colors.separator else colors.accent, CircleShape)
                        .semantics { contentDescription = label },
                ) {
                    if (state.isPlaying) PauseIcon(colors.background) else PlayIcon(colors.background)
                }
                Column(Modifier.padding(start = 14.dp).weight(1f)) {
                    Text(
                        if (state.mix.isEmpty()) stringResource(R.string.ambient_choose) else state.summary(context),
                        style = MaterialTheme.typography.titleMedium,
                        color = colors.text,
                        maxLines = 2,
                    )
                    Text(
                        stringResource(if (state.isPlaying) R.string.ambient_playing else R.string.ambient_paused),
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.secondaryText,
                    )
                }
            }

            SectionHeading(R.string.ambient_sounds)
            for (sound in AmbientSound.entries) SoundRow(sound, state, ambient)
            Text(
                stringResource(R.string.ambient_footer_android),
                style = MaterialTheme.typography.bodySmall,
                color = colors.secondaryText,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
            )

            SectionHeading(R.string.ambient_mixes)
            Row(
                Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                for (preset in AmbientMix.all) {
                    val selected = state.currentMix == preset
                    Text(
                        stringResource(preset.title),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Medium,
                        color = if (selected) colors.background else colors.text,
                        modifier = Modifier
                            .background(if (selected) colors.accent else colors.background, RoundedCornerShape(50))
                            .border(if (selected) BorderStroke(0.dp, colors.accent) else BorderStroke(1.dp, colors.separator), RoundedCornerShape(50))
                            .clickable(role = Role.Button) { ambient.choose(preset) }
                            .semantics { this.selected = selected }
                            .padding(horizontal = 14.dp, vertical = 9.dp),
                    )
                }
            }

            SectionHeading(R.string.ambient_timer)
            var timerMenu by remember { mutableStateOf(false) }
            Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.ambient_timer), color = colors.text, modifier = Modifier.weight(1f))
                TextButton(onClick = { timerMenu = true }, enabled = state.isPlaying) {
                    Text(state.timerMinutes?.let { stringResource(R.string.minutes_count, it.toLong()) } ?: stringResource(R.string.off), color = colors.accent)
                }
                DropdownMenu(expanded = timerMenu, onDismissRequest = { timerMenu = false }) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.off)) }, onClick = { ambient.setTimer(null); timerMenu = false })
                    for (minutes in AmbientRules.timerChoices) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.minutes_count, minutes.toLong())) },
                            onClick = { ambient.setTimer(minutes); timerMenu = false },
                        )
                    }
                }
            }
            state.timerEndsAt?.let { end ->
                Text(
                    stringResource(R.string.ambient_fades_at, DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(end))),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.secondaryText,
                    modifier = Modifier.padding(horizontal = 24.dp),
                )
            }
        }
    }
}

@Composable
private fun SectionHeading(title: Int) {
    Text(
        stringResource(title),
        style = MaterialTheme.typography.titleMedium,
        color = LocalReaderColors.current.text,
        modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 20.dp, bottom = 8.dp).semantics { heading() },
    )
}

@Composable
private fun SoundRow(sound: AmbientSound, state: AmbientState, ambient: AmbientSounds) {
    val colors = LocalReaderColors.current
    val on = state.contains(sound)
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable(role = Role.Checkbox) { ambient.toggle(sound) }
                .semantics { selected = on }
                .padding(horizontal = 24.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(stringResource(sound.title), color = colors.text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            Text(if (on) "●" else "○", color = if (on) colors.accent else colors.separator, fontSize = 20.sp)
        }
        if (on) {
            val name = stringResource(sound.title)
            val label = stringResource(R.string.ambient_volume, name)
            Slider(
                value = state.volume(sound),
                onValueChange = { ambient.setVolume(it, sound) },
                colors = SliderDefaults.colors(thumbColor = colors.accent, activeTrackColor = colors.accent),
                modifier = Modifier.padding(start = 40.dp, end = 24.dp).semantics { contentDescription = label },
            )
        }
    }
}

/**
 * A small bar at the bottom of the reader while ambient sounds are out, as
 * AmbientMiniBar: what's playing (opens the sheet), pause and stop.
 */
@Composable
fun AmbientMiniBar(ambient: AmbientSounds, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val state by ambient.state.collectAsState()
    val context = LocalContext.current
    if (!state.showsControls || state.mix.isEmpty()) return
    val summary = state.summary(context)
    val barLabel = stringResource(R.string.ambient_bar_label, summary)
    val playLabel = stringResource(if (state.isPlaying) R.string.pause else R.string.play)
    val stopLabel = stringResource(R.string.ambient_stop)
    Row(
        modifier
            .fillMaxWidth()
            .background(colors.surface, RoundedCornerShape(50))
            .padding(start = 18.dp, end = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            summary,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = colors.text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .weight(1f)
                .clickable(role = Role.Button, onClick = onOpen)
                .semantics { contentDescription = barLabel }
                .padding(vertical = 12.dp),
        )
        IconButton(onClick = ambient::togglePlayback, modifier = Modifier.semantics { contentDescription = playLabel }) {
            if (state.isPlaying) PauseIcon(colors.accent, 18.dp) else PlayIcon(colors.accent, 18.dp)
        }
        IconButton(onClick = ambient::close, modifier = Modifier.semantics { contentDescription = stopLabel }) {
            Text("✕", color = colors.secondaryText, fontSize = 14.sp)
        }
    }
}

/**
 * The ambient sounds as a row of a player (AmbientControlsRow on iOS): what's
 * in the mix and whether it plays (opens the sounds), Play/Pause and Stop.
 * Shows nothing while the sounds are put away.
 */
@Composable
fun AmbientControlsRow(ambient: AmbientSounds, onOpen: () -> Unit, divider: Boolean = false, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val state by ambient.state.collectAsState()
    val context = LocalContext.current
    if (!state.showsControls || state.mix.isEmpty()) return
    val summary = state.summary(context)
    val barLabel = stringResource(R.string.ambient_bar_label, summary)
    val playLabel = stringResource(if (state.isPlaying) R.string.pause_ambient_sounds else R.string.play_ambient_sounds)
    val stopLabel = stringResource(R.string.ambient_stop)
    Column(modifier.fillMaxWidth()) {
        if (divider) androidx.compose.material3.HorizontalDivider(Modifier.padding(end = 10.dp, top = 2.dp), color = colors.separator)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(
                Modifier
                    .weight(1f)
                    .clickable(role = Role.Button, onClick = onOpen)
                    .semantics(mergeDescendants = true) { contentDescription = barLabel }
                    .padding(vertical = 6.dp),
            ) {
                Text(summary, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = colors.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    stringResource(if (state.isPlaying) R.string.ambient_playing else R.string.ambient_paused),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.secondaryText,
                )
            }
            IconButton(onClick = ambient::togglePlayback, modifier = Modifier.semantics { contentDescription = playLabel }) {
                if (state.isPlaying) PauseIcon(colors.accent, 18.dp) else PlayIcon(colors.accent, 18.dp)
            }
            IconButton(onClick = ambient::close, modifier = Modifier.semantics { contentDescription = stopLabel }) {
                Text("✕", color = colors.secondaryText, fontSize = 14.sp)
            }
        }
    }
}
