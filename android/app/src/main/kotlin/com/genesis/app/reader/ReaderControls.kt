package com.genesis.app.reader

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.app.audio.HeadphonesIcon
import com.genesis.app.audio.PauseIcon
import com.genesis.app.bibles.languageName
import com.genesis.core.bible.InstalledBible
import com.genesis.core.design.LocalReaderColors

/**
 * The reader's floating controls, as ReaderControls.swift: on the left
 * "‹ John 15 ›" (the name opens the book picker), on the right the Bible,
 * bookmark, listening, reading settings and, on a wide screen, the study
 * panel. A narrow phone moves the bookmark into a More menu rather than
 * squeezing the chapter's name.
 */
@Composable
internal fun ReaderControls(
    state: ReaderUiState,
    listening: ReaderListening?,
    showsListen: Boolean,
    showsOriginalItem: Boolean,
    showsPanelToggle: Boolean,
    onChapterPicker: () -> Unit,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onSettings: () -> Unit,
    onBookmark: () -> Unit,
    onChooseBible: (InstalledBible) -> Unit,
    onMoreBibles: () -> Unit,
    onToggleOriginal: () -> Unit,
    onTogglePanel: () -> Unit,
) {
    val colors = LocalReaderColors.current
    val language = state.chapter?.translation?.language ?: "en"
    BoxWithConstraints(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 12.dp, vertical = 4.dp)) {
        val overflow = maxWidth < 380.dp
        val iconWidth = if (maxWidth < 360.dp) 32.dp else 38.dp
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Capsule {
                ControlButton(stringResource(R.string.previous_chapter), iconWidth, enabled = state.chapterId.previous != null, onClick = onPrevious) {
                    Text("‹", color = colors.text, fontSize = 24.sp)
                }
                val pick = stringResource(R.string.choose_book_and_chapter)
                Text(
                    state.chapterId.description(language),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = colors.text,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .widthIn(max = if (overflow) 130.dp else 180.dp)
                        .clickable(role = Role.Button, onClick = onChapterPicker)
                        .semantics { contentDescription = pick }
                        .padding(horizontal = 4.dp, vertical = 8.dp),
                )
                ControlButton(stringResource(R.string.next_chapter), iconWidth, enabled = state.chapterId.next != null, onClick = onNext) {
                    Text("›", color = colors.text, fontSize = 24.sp)
                }
            }
            Spacer(Modifier.weight(1f).widthIn(min = 6.dp))
            Capsule {
                BibleMenu(state, showsOriginalItem, onChooseBible, onMoreBibles, onToggleOriginal)
                if (!overflow) BookmarkButton(state.isChapterBookmarked, iconWidth, onBookmark)
                if (showsListen && listening != null) {
                    val current = listening.state
                    val playingHere = current.isPlaying && current.chapter == state.chapterId && current.bible == state.bible
                    ControlButton(
                        stringResource(if (playingHere) R.string.pause_listening else R.string.listen_to_chapter),
                        iconWidth,
                        onClick = {
                            if (current.isActive && current.chapter == state.chapterId && current.bible == state.bible) listening.controls.toggle()
                            else listening.controls.play(state.bible, state.chapterId)
                        },
                    ) { if (playingHere) PauseIcon(colors.text, 20.dp) else HeadphonesIcon(colors.text, 20.dp) }
                }
                ControlButton(stringResource(R.string.reading_settings), iconWidth, onClick = onSettings) {
                    Text("Aa", color = colors.text, style = MaterialTheme.typography.titleMedium)
                }
                if (showsPanelToggle && !overflow) {
                    ControlButton(stringResource(R.string.toggle_study_panel), iconWidth, onClick = onTogglePanel) { SidebarIcon(colors.text) }
                }
                if (overflow) MoreMenu(state.isChapterBookmarked, showsPanelToggle, iconWidth, onBookmark, onTogglePanel)
            }
        }
    }
}

/** A rounded, nearly opaque capsule over the page (iOS's glass). */
@Composable
private fun Capsule(content: @Composable () -> Unit) {
    val colors = LocalReaderColors.current
    Row(
        Modifier
            .background(colors.surface.copy(alpha = 0.94f), RoundedCornerShape(50))
            .border(BorderStroke(0.5.dp, colors.separator), RoundedCornerShape(50))
            .padding(horizontal = 4.dp)
            .height(44.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) { content() }
}

@Composable
private fun ControlButton(label: String, width: Dp, enabled: Boolean = true, onClick: () -> Unit, icon: @Composable () -> Unit) {
    Box(
        Modifier
            .size(width = width, height = 40.dp)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .alpha(if (enabled) 1f else 0.3f)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { icon() }
}

@Composable
private fun BookmarkButton(bookmarked: Boolean, width: Dp, onBookmark: () -> Unit) {
    val colors = LocalReaderColors.current
    ControlButton(stringResource(if (bookmarked) R.string.remove_bookmark_short else R.string.add_bookmark_short), width, onClick = onBookmark) {
        BookmarkIcon(if (bookmarked) colors.accent else colors.text, filled = bookmarked)
    }
}

/** Every installed Bible by language (the one being read's first), the Hebrew and Greek, and More Bibles. */
@Composable
private fun BibleMenu(
    state: ReaderUiState,
    showsOriginalItem: Boolean,
    onChooseBible: (InstalledBible) -> Unit,
    onMoreBibles: () -> Unit,
    onToggleOriginal: () -> Unit,
) {
    val colors = LocalReaderColors.current
    var open by remember { mutableStateOf(false) }
    val current = state.chapter?.translation
    Box {
        val chooseTranslation = stringResource(R.string.choose_translation)
        Text(
            current?.abbreviation ?: state.bible.id,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold,
            color = colors.text,
            maxLines = 1,
            modifier = Modifier
                .clickable(role = Role.Button) { open = true }
                .semantics { contentDescription = chooseTranslation }
                .padding(horizontal = 8.dp, vertical = 10.dp),
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            val mine = (current?.language ?: "en").substringBefore('-')
            val groups = state.translations
                .groupBy { it.second.language.substringBefore('-') }
                .toList()
                .sortedWith(compareBy({ it.first != mine }, { it.first }))
            for ((code, bibles) in groups) {
                Text(
                    languageName(code),
                    style = MaterialTheme.typography.labelMedium,
                    color = colors.secondaryText,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                )
                for ((bible, translation) in bibles) {
                    DropdownMenuItem(
                        text = { Text((if (bible == state.bible) "✓ " else "") + "${translation.abbreviation} · ${translation.name}") },
                        onClick = {
                            open = false
                            onChooseBible(bible)
                        },
                    )
                }
            }
            if (showsOriginalItem) {
                HorizontalDivider(color = colors.separator)
                DropdownMenuItem(
                    text = { Text((if (state.showsOriginal) "✓ " else "") + stringResource(R.string.original_hebrew_greek)) },
                    onClick = {
                        open = false
                        onToggleOriginal()
                    },
                )
            }
            HorizontalDivider(color = colors.separator)
            DropdownMenuItem(
                text = { Text(stringResource(R.string.more_bibles), color = colors.accent) },
                onClick = {
                    open = false
                    onMoreBibles()
                },
            )
        }
    }
}

@Composable
private fun MoreMenu(bookmarked: Boolean, showsPanelToggle: Boolean, width: Dp, onBookmark: () -> Unit, onTogglePanel: () -> Unit) {
    val colors = LocalReaderColors.current
    var open by remember { mutableStateOf(false) }
    Box {
        ControlButton(stringResource(R.string.more), width, onClick = { open = true }) {
            Text("⋯", color = colors.text, fontSize = 20.sp)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(if (bookmarked) R.string.remove_bookmark else R.string.add_bookmark_menu)) },
                onClick = { open = false; onBookmark() },
            )
            if (showsPanelToggle) {
                DropdownMenuItem(text = { Text(stringResource(R.string.study_panel)) }, onClick = { open = false; onTogglePanel() })
            }
        }
    }
}

/** A bookmark: outlined, or filled while the chapter is bookmarked. */
@Composable
internal fun BookmarkIcon(color: Color, filled: Boolean) {
    Canvas(Modifier.size(width = 14.dp, height = 19.dp)) {
        val path = Path().apply {
            moveTo(0f, 0f)
            lineTo(size.width, 0f)
            lineTo(size.width, size.height)
            lineTo(size.width / 2, size.height * 0.72f)
            lineTo(0f, size.height)
            close()
        }
        if (filled) drawPath(path, color) else drawPath(path, color, style = Stroke(width = 1.6.dp.toPx()))
    }
}

/** The study panel's toggle: a rectangle with its right-hand column. */
@Composable
private fun SidebarIcon(color: Color) {
    Canvas(Modifier.size(width = 20.dp, height = 16.dp)) {
        val stroke = 1.6.dp.toPx()
        drawRoundRect(color, style = Stroke(stroke), cornerRadius = androidx.compose.ui.geometry.CornerRadius(3.dp.toPx()))
        val x = size.width * 0.62f
        drawLine(color, androidx.compose.ui.geometry.Offset(x, 0f), androidx.compose.ui.geometry.Offset(x, size.height), stroke)
    }
}
