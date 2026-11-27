package com.genesis.app.prayer

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.notifications.SwitchRow
import com.genesis.app.notifications.TimeDialog
import com.genesis.app.notifications.TimeRow
import com.genesis.app.notifications.rememberNotificationPermission
import com.genesis.app.settings.Footer
import com.genesis.app.settings.Group
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.prayer.Prayer
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit

/**
 * "Remind me to pray", as PrayerEditorView's reminder section on iOS: once
 * at a date and time, or every day. The notification shows only the
 * prayer's title, never the prayer.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PrayerReminder(prayer: Prayer, onChange: (Prayer) -> Unit) {
    val colors = LocalReaderColors.current
    val zone = ZoneId.systemDefault()
    val permission = rememberNotificationPermission()
    var pickingTime by remember { mutableStateOf(false) }
    var pickingDate by remember { mutableStateOf(false) }
    val at = prayer.reminderAt?.let { LocalDateTime.ofInstant(Instant.ofEpochMilli(it), zone) }
    fun set(value: LocalDateTime) = onChange(prayer.copy(reminderAt = value.atZone(zone).toInstant().toEpochMilli()))

    Group {
        SwitchRow(stringResource(R.string.remind_me_to_pray), null, at != null) { on ->
            if (on) {
                set(LocalDateTime.now(zone).plusHours(1).truncatedTo(ChronoUnit.MINUTES))
                permission.ask()
            } else {
                onChange(prayer.copy(reminderAt = null, reminderRepeatsDaily = false))
            }
        }
        if (at != null) {
            if (!prayer.reminderRepeatsDaily) {
                HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                TimeRow(0, label = stringResource(R.string.date), value = at.toLocalDate().format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))) { pickingDate = true }
            }
            HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
            TimeRow(at.hour * 60 + at.minute) { pickingTime = true }
            HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
            SwitchRow(stringResource(R.string.every_day_lower), null, prayer.reminderRepeatsDaily) { onChange(prayer.copy(reminderRepeatsDaily = it)) }
        }
    }
    if (at != null && !permission.allowed && permission.asked) {
        Footer(stringResource(R.string.prayer_notifications_off))
    } else {
        Footer(stringResource(R.string.reminder_title_only))
    }

    if (pickingTime && at != null) {
        TimeDialog(
            minutes = at.hour * 60 + at.minute,
            onDismiss = { pickingTime = false },
            onPick = { minutes ->
                pickingTime = false
                set(at.toLocalDate().atTime(minutes / 60, minutes % 60))
            },
        )
    }
    if (pickingDate && at != null) {
        // The picker works in UTC midnights.
        val state = rememberDatePickerState(initialSelectedDateMillis = at.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { pickingDate = false },
            confirmButton = {
                TextButton(onClick = {
                    pickingDate = false
                    state.selectedDateMillis?.let { millis ->
                        val day = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                        set(day.atTime(at.toLocalTime()))
                    }
                }) { Text(stringResource(R.string.done), color = colors.accent) }
            },
            dismissButton = { TextButton(onClick = { pickingDate = false }) { Text(stringResource(R.string.cancel), color = colors.accent) } },
            colors = DatePickerDefaults.colors(containerColor = colors.surface),
        ) {
            DatePicker(
                state,
                colors = DatePickerDefaults.colors(
                    containerColor = colors.surface,
                    selectedDayContainerColor = colors.accent,
                    todayDateBorderColor = colors.accent,
                    todayContentColor = colors.accent,
                ),
            )
        }
    }
}

