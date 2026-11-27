package com.genesis.app.reader

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.study.Note
import com.genesis.core.domain.study.NoteAnchor
import com.genesis.core.domain.study.NoteKind

/**
 * Writes a note on a passage, as NoteEditorView on iOS: the kind, a title
 * and the note itself, saved when the sheet closes (Done, a swipe down or
 * Back), with Delete asking first. The passage is named, never quoted.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun NoteEditorSheet(
    note: Note,
    language: String,
    onChange: ((Note) -> Note) -> Unit,
    onClose: () -> Unit,
    onDelete: () -> Unit,
) {
    val colors = LocalReaderColors.current
    var confirmDelete by rememberSaveable { mutableStateOf(false) }
    val fieldColors = TextFieldDefaults.colors(
        focusedContainerColor = Color.Transparent,
        unfocusedContainerColor = Color.Transparent,
        focusedIndicatorColor = Color.Transparent,
        unfocusedIndicatorColor = Color.Transparent,
        focusedTextColor = colors.text,
        unfocusedTextColor = colors.text,
        cursorColor = colors.accent,
    )

    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = colors.surface,
    ) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).imePadding()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                val reference = (note.anchor as? NoteAnchor.Verses)?.let { ReferenceParser.describe(it.start.rawValue, it.end.rawValue, language) }
                Text(
                    reference?.let { stringResource(R.string.note_on, it) } ?: stringResource(R.string.note),
                    style = MaterialTheme.typography.titleMedium,
                    color = colors.text,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                if (!note.isEmpty) {
                    TextButton(onClick = { confirmDelete = true }) {
                        Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error)
                    }
                }
                TextButton(onClick = onClose) {
                    Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (kind in NoteKind.writable) {
                    FilterChip(
                        selected = note.kind == kind,
                        onClick = { onChange { it.copy(kind = kind) } },
                        label = { Text(stringResource(kind.title)) },
                        colors = FilterChipDefaults.filterChipColors(
                            labelColor = colors.secondaryText,
                            selectedContainerColor = colors.accent.copy(alpha = 0.16f),
                            selectedLabelColor = colors.text,
                        ),
                    )
                }
            }
            TextField(
                value = note.title,
                onValueChange = { title -> onChange { it.copy(title = title) } },
                placeholder = { Text(stringResource(R.string.note_title)) },
                textStyle = MaterialTheme.typography.titleLarge,
                colors = fieldColors,
                modifier = Modifier.fillMaxWidth(),
            )
            TextField(
                value = note.body,
                onValueChange = { body -> onChange { it.copy(body = body) } },
                placeholder = { Text(stringResource(note.kind.placeholder)) },
                textStyle = MaterialTheme.typography.bodyLarge,
                colors = fieldColors,
                modifier = Modifier.fillMaxWidth().heightIn(min = 200.dp),
            )
            Spacer(Modifier.padding(bottom = 16.dp))
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.delete_this_note)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    onDelete()
                }) { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

private val NoteKind.title: Int
    get() = when (this) {
        NoteKind.STUDY -> R.string.note_kind_study
        NoteKind.JOURNAL -> R.string.note_kind_journal
        else -> R.string.note
    }

private val NoteKind.placeholder: Int
    get() = when (this) {
        NoteKind.STUDY -> R.string.note_placeholder_study
        NoteKind.JOURNAL -> R.string.note_placeholder_journal
        else -> R.string.note_placeholder_text
    }
