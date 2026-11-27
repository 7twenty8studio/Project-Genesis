package com.genesis.app.notifications

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.notifications.ReminderKind
import kotlinx.coroutines.launch

/**
 * A one-time invitation on Home (NotificationInviteCard on iOS): the verse
 * of the day each morning and a gentle evening reminder to read. Turn On
 * asks Android for permission; either answer hides the card (Settings ›
 * Notifications has everything, any time).
 */
@Composable
fun NotificationInviteCard() {
    val context = LocalContext.current
    val app = context.applicationContext as VerselyApplication
    val state by app.notifications.state.collectAsState()
    if (state.hasAnsweredInvite) return
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    val permission = rememberNotificationPermission()
    var waiting by remember { mutableStateOf(false) }

    // The answer to Android's question: on when allowed, and the card goes either way.
    LaunchedEffect(waiting, permission.allowed, permission.asked) {
        if (!waiting) return@LaunchedEffect
        if (permission.allowed || permission.asked) {
            if (permission.allowed) turnOn(app)
            app.notifications.answerInvite()
            scope.launch { ReminderScheduler.refresh(app) }
            waiting = false
        }
    }

    Column(
        Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(20.dp)).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("🔔", style = MaterialTheme.typography.titleLarge)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.start_each_day_with_verse), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
                Text(stringResource(R.string.notification_invite_message), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(
                onClick = {
                    if (permission.allowed) {
                        turnOn(app)
                        app.notifications.answerInvite()
                        scope.launch { ReminderScheduler.refresh(app) }
                    } else {
                        waiting = true
                        permission.ask()
                    }
                },
                enabled = !waiting,
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
                modifier = Modifier.weight(1f),
            ) { Text(stringResource(R.string.turn_on)) }
            OutlinedButton(onClick = { app.notifications.answerInvite() }, modifier = Modifier.weight(1f)) {
                Text(stringResource(R.string.not_now), color = colors.accent)
            }
        }
    }
}

private fun turnOn(app: VerselyApplication) {
    app.notifications.setAllowsNotifications(true)
    app.notifications.set(ReminderKind.VERSE_OF_THE_DAY, true)
    app.notifications.set(ReminderKind.DAILY_READING, true)
}
