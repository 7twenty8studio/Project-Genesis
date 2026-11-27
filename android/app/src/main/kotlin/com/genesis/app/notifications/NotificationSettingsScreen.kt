package com.genesis.app.notifications

import android.Manifest
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.rememberTimePickerState
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.edit
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.notifications.ReminderScheduler.detailRes
import com.genesis.app.notifications.ReminderScheduler.titleRes
import com.genesis.app.settings.Footer
import com.genesis.app.settings.Group
import com.genesis.app.settings.Header
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.notifications.ReminderKind
import kotlinx.coroutines.launch
import java.util.Calendar

/**
 * Settings › Notifications, as NotificationSettingsView on iOS: one switch
 * for everything, then each kind with its own switch and time.
 */
@Composable
fun NotificationSettingsScreen(onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val app = context.applicationContext as VerselyApplication
    val state by app.notifications.state.collectAsStateWithLifecycle()
    val permission = rememberNotificationPermission()
    var editing by remember { mutableStateOf<ReminderKind?>(null) }
    BackHandler(onBack = onDone)

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.notifications),
                style = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp)) {
            Spacer(Modifier.size(12.dp))
            Group {
                SwitchRow(stringResource(R.string.allow_notifications), null, state.allowsNotifications) { on ->
                    app.notifications.setAllowsNotifications(on)
                    if (on) permission.ask()
                }
            }
            when {
                state.allowsNotifications && !permission.allowed && permission.asked -> {
                    Footer(stringResource(R.string.notifications_off_system))
                    FooterButton(stringResource(R.string.open_settings)) { openSystemSettings(context) }
                }
                state.allowsNotifications && !permission.allowed -> {
                    Footer(stringResource(R.string.notifications_not_asked))
                    FooterButton(stringResource(R.string.turn_on_notifications)) { permission.ask() }
                }
                else -> Footer(stringResource(R.string.notifications_master_footer))
            }

            if (state.allowsNotifications) {
                Section(stringResource(R.string.every_day), listOf(ReminderKind.VERSE_OF_THE_DAY, ReminderKind.DAILY_READING), state, permission) { editing = it }
                Section(stringResource(R.string.your_bible_life), listOf(ReminderKind.READING_PLAN, ReminderKind.PRAYER, ReminderKind.PRAYER_ANNIVERSARY), state, permission) { editing = it }
            }
            Spacer(Modifier.size(32.dp))
        }
    }

    editing?.let { kind ->
        TimeDialog(
            minutes = state.minutes(kind),
            onDismiss = { editing = null },
            onPick = {
                app.notifications.setMinutes(kind, it)
                editing = null
            },
        )
    }
}

@Composable
private fun Section(
    title: String,
    kinds: List<ReminderKind>,
    state: NotificationPreferences.State,
    permission: NotificationPermission,
    onTime: (ReminderKind) -> Unit,
) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val colors = LocalReaderColors.current
    Header(title)
    Group {
        kinds.forEachIndexed { index, kind ->
            SwitchRow(stringResource(kind.titleRes), stringResource(kind.detailRes), state.isOn(kind)) { on ->
                app.notifications.set(kind, on)
                if (on) permission.ask()
            }
            if (kind.hasTime && state.isOn(kind)) {
                HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                TimeRow(state.minutes(kind)) { onTime(kind) }
            }
            if (index < kinds.lastIndex) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
        }
    }
}

@Composable
internal fun SwitchRow(title: String, detail: String?, checked: Boolean, onChange: (Boolean) -> Unit) {
    val colors = LocalReaderColors.current
    Row(
        Modifier.fillMaxWidth().toggleable(value = checked, role = Role.Switch, onValueChange = onChange).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = colors.text)
            if (detail != null) Text(detail, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        }
        Switch(
            checked = checked,
            onCheckedChange = null,
            colors = SwitchDefaults.colors(
                checkedTrackColor = colors.accent,
                checkedThumbColor = colors.background,
                uncheckedTrackColor = colors.background,
                uncheckedBorderColor = colors.separator,
                uncheckedThumbColor = colors.secondaryText,
            ),
        )
    }
}

@Composable
internal fun TimeRow(minutes: Int, label: String = stringResource(R.string.time), value: String? = null, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.weight(1f))
        Text(value ?: timeText(context, minutes), style = MaterialTheme.typography.bodyLarge, color = colors.accent)
    }
}

/** A time in the phone's own style (12 or 24 hours). */
internal fun timeText(context: Context, minutes: Int): String {
    val calendar = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, minutes / 60)
        set(Calendar.MINUTE, minutes % 60)
    }
    return android.text.format.DateFormat.getTimeFormat(context).format(calendar.time)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun TimeDialog(minutes: Int, onDismiss: () -> Unit, onPick: (Int) -> Unit) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val picker = rememberTimePickerState(minutes / 60, minutes % 60, android.text.format.DateFormat.is24HourFormat(context))
    AlertDialog(
        onDismissRequest = onDismiss,
        text = {
            TimePicker(
                picker,
                colors = TimePickerDefaults.colors(
                    clockDialColor = colors.background,
                    selectorColor = colors.accent,
                    timeSelectorSelectedContainerColor = colors.accent.copy(alpha = 0.2f),
                    timeSelectorSelectedContentColor = colors.text,
                    periodSelectorSelectedContainerColor = colors.accent.copy(alpha = 0.2f),
                    periodSelectorSelectedContentColor = colors.text,
                    periodSelectorBorderColor = colors.separator,
                ),
            )
        },
        confirmButton = { TextButton(onClick = { onPick(picker.hour * 60 + picker.minute) }) { Text(stringResource(R.string.done), color = colors.accent) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = colors.accent) } },
        containerColor = colors.surface,
    )
}

@Composable
private fun FooterButton(title: String, onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.padding(start = 4.dp)) { Text(title, color = LocalReaderColors.current.accent) }
}

private fun openSystemSettings(context: Context) {
    context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
}

/** Android's own permission (Android 13 and later ask once; earlier phones allow by default). */
internal class NotificationPermission(val allowed: Boolean, val asked: Boolean, val ask: () -> Unit)

@Composable
internal fun rememberNotificationPermission(): NotificationPermission {
    val context = LocalContext.current
    val app = context.applicationContext as VerselyApplication
    val scope = rememberCoroutineScope()
    val store = remember { context.getSharedPreferences("notifications", Context.MODE_PRIVATE) }
    var allowed by remember { mutableStateOf(ReminderScheduler.systemAllows(context)) }
    var asked by remember { mutableStateOf(store.getBoolean(ASKED, false)) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        allowed = ReminderScheduler.systemAllows(context)
        asked = true
        store.edit { putBoolean(ASKED, true) }
        scope.launch { ReminderScheduler.refresh(app) }
    }
    // Back from Android's settings: show the new answer.
    LifecycleResumeEffect(Unit) {
        allowed = ReminderScheduler.systemAllows(context)
        onPauseOrDispose { }
    }
    return NotificationPermission(allowed, asked) {
        if (!allowed && Build.VERSION.SDK_INT >= 33) launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
}

private const val ASKED = "notifications.askedSystem"
