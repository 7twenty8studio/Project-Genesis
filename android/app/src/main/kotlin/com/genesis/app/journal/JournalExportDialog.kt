package com.genesis.app.journal

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.prayer.JournalBible
import com.genesis.app.prayer.title
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.prayer.Prayer
import com.genesis.core.domain.prayer.PrayerCategory
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.FormatStyle

/**
 * The prayer journal as a PDF for a range of days and, optionally, one
 * category (Premium), as JournalExportSheet's options on iOS.
 */
@Composable
internal fun JournalExportDialog(prayers: List<Prayer>, bible: JournalBible, onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var from by remember { mutableStateOf(LocalDate.now().minusMonths(1)) }
    var through by remember { mutableStateOf(LocalDate.now()) }
    var category by remember { mutableStateOf<PrayerCategory?>(null) }
    var picking by remember { mutableStateOf<Boolean?>(null) } // true: From, false: Through
    var categories by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
        title = { Text(stringResource(R.string.export_as_pdf), color = colors.text) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.prayers_heading), style = MaterialTheme.typography.labelLarge, color = colors.secondaryText)
                Choice(stringResource(R.string.night_from), day(from)) { picking = true }
                Choice(stringResource(R.string.date_through), day(through)) { picking = false }
                Box {
                    Choice(stringResource(R.string.category), category?.let { stringResource(it.title) } ?: stringResource(R.string.all_categories)) { categories = true }
                    DropdownMenu(expanded = categories, onDismissRequest = { categories = false }) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.all_categories)) }, onClick = { category = null; categories = false })
                        PrayerCategory.entries.forEach { option ->
                            DropdownMenuItem(text = { Text(stringResource(option.title)) }, onClick = { category = option; categories = false })
                        }
                    }
                }
                if (working) Text(stringResource(R.string.preparing_pdf), color = colors.secondaryText, style = MaterialTheme.typography.bodySmall)
            }
        },
        confirmButton = {
            TextButton(enabled = !working, onClick = {
                working = true
                scope.launch {
                    val export = JournalExportBuilder(context, bible).exportJournal(prayers, from, through, category)
                    JournalPdf.share(context, export)
                    working = false
                    onDismiss()
                }
            }) { Text(stringResource(R.string.export_pdf), color = colors.accent) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = colors.accent) } },
    )

    picking?.let { isFrom -> DayPicker(if (isFrom) from else through, onPick = { if (isFrom) from = it else through = it; picking = null }, onDismiss = { picking = null }) }
}

@Composable
private fun Choice(label: String, value: String, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    TextButton(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(label, color = colors.text, modifier = Modifier.weight(1f))
            Text(value, color = colors.accent)
        }
    }
}

private fun day(date: LocalDate): String = JournalPdf.date(date.atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli(), FormatStyle.MEDIUM)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DayPicker(day: LocalDate, onPick: (LocalDate) -> Unit, onDismiss: () -> Unit) {
    // The date picker works in UTC midnights.
    val state = rememberDatePickerState(initialSelectedDateMillis = day.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                state.selectedDateMillis?.let { onPick(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) } ?: onDismiss()
            }) { Text(stringResource(R.string.ok)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    ) { DatePicker(state) }
}
