package com.genesis.app.audio

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.audio.Narration

/**
 * The reader's listening controls while a chapter is read aloud, as
 * AudioMiniPlayer on iOS: where it is, Previous / Play-Pause / Next by
 * chapter, the speed, and a menu with the sleep timer and Stop.
 */
@Composable
fun ListeningBar(
    state: ListeningState,
    speed: Double,
    listening: Listening,
    modifier: Modifier = Modifier,
    ambient: AmbientSounds? = null,
    onOpenAmbient: () -> Unit = {},
) {
    val colors = LocalReaderColors.current
    var speedMenu by remember { mutableStateOf(false) }
    var moreMenu by remember { mutableStateOf(false) }
    Column(modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(16.dp)).padding(start = 14.dp, end = 4.dp, top = 6.dp, bottom = 6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                Text(state.title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = colors.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                val detail = state.error?.let { stringResource(it) }
                    ?: state.sleepTimer?.let { sleepLabel(it) }
                    ?: stringResource(R.string.device_voice_source, state.abbreviation)
                Text(detail, style = MaterialTheme.typography.bodySmall, color = if (state.error != null) colors.accent else colors.secondaryText, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            val previous = stringResource(R.string.previous_chapter)
            IconButton(onClick = listening::previousChapter, modifier = Modifier.semantics { contentDescription = previous }) { SkipIcon(colors.text, forward = false) }
            val toggle = stringResource(if (state.isPlaying) R.string.pause else R.string.play)
            IconButton(onClick = listening::toggle, modifier = Modifier.semantics { contentDescription = toggle }) {
                if (state.isPlaying) PauseIcon(colors.accent, 26.dp) else PlayIcon(colors.accent, 26.dp)
            }
            val next = stringResource(R.string.next_chapter)
            IconButton(onClick = listening::nextChapter, enabled = state.chapter?.next != null, modifier = Modifier.semantics { contentDescription = next }) { SkipIcon(colors.text, forward = true) }
            Box {
                val speedLabel = stringResource(R.string.speed)
                TextButton(onClick = { speedMenu = true }, modifier = Modifier.semantics { contentDescription = "$speedLabel ${Narration.speedLabel(speed)}" }) {
                    Text(Narration.speedLabel(speed), color = colors.accent, fontWeight = FontWeight.SemiBold)
                }
                DropdownMenu(expanded = speedMenu, onDismissRequest = { speedMenu = false }) {
                    Narration.speeds.forEach { choice ->
                        DropdownMenuItem(
                            text = { Text((if (choice == speed) "✓  " else "     ") + Narration.speedLabel(choice)) },
                            onClick = {
                                speedMenu = false
                                listening.setSpeed(choice)
                            },
                        )
                    }
                }
            }
            Box {
                val more = stringResource(R.string.more)
                IconButton(onClick = { moreMenu = true }, modifier = Modifier.semantics { contentDescription = more }) { MoreIcon(colors.secondaryText) }
                DropdownMenu(expanded = moreMenu, onDismissRequest = { moreMenu = false }) {
                    Text(
                        stringResource(R.string.sleep_timer),
                        style = MaterialTheme.typography.labelMedium,
                        color = colors.secondaryText,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                    )
                    DropdownMenuItem(
                        text = { Text((if (state.sleepTimer == null) "✓  " else "     ") + stringResource(R.string.off)) },
                        onClick = {
                            moreMenu = false
                            listening.setSleepTimer(null)
                        },
                    )
                    SleepTimer.choices.forEach { timer ->
                        DropdownMenuItem(
                            text = { Text((if (state.sleepTimer == timer) "✓  " else "     ") + timerTitle(timer)) },
                            onClick = {
                                moreMenu = false
                                listening.setSleepTimer(timer)
                            },
                        )
                    }
                    HorizontalDivider()
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.stop_listening)) },
                        onClick = {
                            moreMenu = false
                            listening.stop()
                        },
                    )
                }
            }
        }
        // While both play, the sounds are a row of this player (AmbientControlsRow on iOS), so there's one player.
        if (ambient != null) AmbientControlsRow(ambient, onOpenAmbient, divider = true)
    }
}

@Composable
private fun timerTitle(timer: SleepTimer): String = when (timer) {
    is SleepTimer.Minutes -> stringResource(R.string.minutes_count, timer.minutes)
    SleepTimer.EndOfChapter -> stringResource(R.string.end_of_chapter)
}

@Composable
private fun sleepLabel(timer: SleepTimer): String = stringResource(R.string.sleep_timer_detail, timerTitle(timer))

/** Headphones, for the reader's Listen button (drawn, so no icon library). */
@Composable
fun HeadphonesIcon(color: Color, iconSize: Dp = 22.dp) {
    Canvas(Modifier.size(iconSize)) {
        val stroke = size.minDimension * 0.1f
        drawArc(color, 180f, 180f, false, Offset(size.width * 0.12f, size.height * 0.14f), Size(size.width * 0.76f, size.height * 0.76f), style = Stroke(stroke, cap = StrokeCap.Round))
        val cup = Size(size.width * 0.2f, size.height * 0.34f)
        drawRoundRect(color, Offset(size.width * 0.08f, size.height * 0.52f), cup, androidx.compose.ui.geometry.CornerRadius(stroke))
        drawRoundRect(color, Offset(size.width * 0.72f, size.height * 0.52f), cup, androidx.compose.ui.geometry.CornerRadius(stroke))
    }
}

@Composable
internal fun PlayIcon(color: Color, iconSize: Dp = 22.dp) {
    Canvas(Modifier.size(iconSize)) {
        drawPath(Path().apply {
            moveTo(size.width * 0.25f, size.height * 0.15f)
            lineTo(size.width * 0.85f, size.height * 0.5f)
            lineTo(size.width * 0.25f, size.height * 0.85f)
            close()
        }, color)
    }
}

@Composable
internal fun PauseIcon(color: Color, iconSize: Dp = 22.dp) {
    Canvas(Modifier.size(iconSize)) {
        val bar = Size(size.width * 0.22f, size.height * 0.7f)
        drawRect(color, Offset(size.width * 0.22f, size.height * 0.15f), bar)
        drawRect(color, Offset(size.width * 0.56f, size.height * 0.15f), bar)
    }
}

@Composable
private fun SkipIcon(color: Color, forward: Boolean) {
    Canvas(Modifier.size(18.dp)) {
        val w = size.width
        val h = size.height
        fun x(value: Float) = if (forward) value * w else (1 - value) * w
        drawPath(Path().apply {
            moveTo(x(0.12f), h * 0.18f)
            lineTo(x(0.72f), h * 0.5f)
            lineTo(x(0.12f), h * 0.82f)
            close()
        }, color)
        drawRect(color, Offset(if (forward) w * 0.74f else w * 0.12f, h * 0.18f), Size(w * 0.14f, h * 0.64f))
    }
}

@Composable
private fun MoreIcon(color: Color) {
    Canvas(Modifier.size(20.dp)) {
        listOf(0.2f, 0.5f, 0.8f).forEach { drawCircle(color, size.minDimension * 0.08f, Offset(size.width * it, size.height / 2)) }
    }
}
