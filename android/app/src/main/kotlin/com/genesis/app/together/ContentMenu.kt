package com.genesis.app.together

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.core.cloud.community.ReportReason
import com.genesis.core.design.LocalReaderColors
import kotlinx.coroutines.launch

/**
 * Report, block and delete for anything people post, as `.contentActions`
 * on iOS (App Store 1.2 and Play's user-generated content policy ask for
 * reporting and blocking wherever people see each other's posts).
 */
@Composable
internal fun ContentMenu(
    authorName: String,
    isMine: Boolean,
    canRemove: Boolean,
    onRemove: suspend () -> Unit,
    onReport: suspend (ReportReason) -> Boolean,
    onBlock: suspend () -> Unit,
    onHidden: () -> Unit,
) {
    if (!canRemove && isMine) return
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    var menu by remember { mutableStateOf(false) }
    var reporting by remember { mutableStateOf(false) }
    var blocking by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf(false) }
    var thanks by remember { mutableStateOf(false) }
    Box {
        val more = stringResource(R.string.more)
        IconButton(onClick = { menu = true }, modifier = Modifier.size(36.dp).semantics { contentDescription = more }) {
            Canvas(Modifier.size(18.dp)) {
                listOf(0.2f, 0.5f, 0.8f).forEach { drawCircle(colors.secondaryText, size.minDimension * 0.08f, Offset(size.width * it, size.height / 2)) }
            }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            if (canRemove) DropdownMenuItem(text = { Text(stringResource(R.string.delete)) }, onClick = { menu = false; removing = true })
            if (!isMine) {
                DropdownMenuItem(text = { Text(stringResource(R.string.report)) }, onClick = { menu = false; reporting = true })
                DropdownMenuItem(text = { Text(stringResource(R.string.block_name, authorName)) }, onClick = { menu = false; blocking = true })
            }
        }
    }
    if (reporting) {
        AlertDialog(
            onDismissRequest = { reporting = false },
            title = { Text(stringResource(R.string.report_this)) },
            text = {
                Column {
                    Text(stringResource(R.string.report_message))
                    ReportReason.entries.forEach { reason ->
                        TextButton(onClick = {
                            reporting = false
                            scope.launch { if (onReport(reason)) thanks = true }
                        }) { Text(stringResource(reason.title), color = colors.accent) }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { reporting = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    if (thanks) {
        AlertDialog(
            onDismissRequest = { thanks = false; onHidden() },
            title = { Text(stringResource(R.string.thank_you)) },
            text = { Text(stringResource(R.string.report_thanks)) },
            confirmButton = { TextButton(onClick = { thanks = false; onHidden() }) { Text(stringResource(R.string.ok)) } },
        )
    }
    if (blocking) {
        AlertDialog(
            onDismissRequest = { blocking = false },
            title = { Text(stringResource(R.string.block_name_question, authorName)) },
            text = { Text(stringResource(R.string.block_message)) },
            confirmButton = {
                TextButton(onClick = {
                    blocking = false
                    scope.launch { onBlock() }
                }) { Text(stringResource(R.string.block_name, authorName)) }
            },
            dismissButton = { TextButton(onClick = { blocking = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    if (removing) {
        AlertDialog(
            onDismissRequest = { removing = false },
            title = { Text(stringResource(R.string.delete_this)) },
            confirmButton = {
                TextButton(onClick = {
                    removing = false
                    scope.launch { onRemove() }
                }) { Text(stringResource(R.string.delete)) }
            },
            dismissButton = { TextButton(onClick = { removing = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}
