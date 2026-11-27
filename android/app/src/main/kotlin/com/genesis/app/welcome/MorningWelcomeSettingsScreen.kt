package com.genesis.app.welcome

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.text.KeyboardOptions
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.audio.summary
import com.genesis.app.settings.Footer
import com.genesis.app.settings.Group
import com.genesis.app.settings.Header
import com.genesis.app.settings.Row_
import com.genesis.app.settings.SettingSwitch
import com.genesis.core.design.LocalReaderColors

/** Settings › Morning Welcome (Premium), as MorningWelcomeSettingsView.swift. */
@Composable
fun MorningWelcomeSettingsScreen(showsAmbient: Boolean, onPreview: () -> Unit, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val app = context.applicationContext as VerselyApplication
    val welcome = app.welcome
    val settings by welcome.settings.collectAsStateWithLifecycle()
    val ambient by app.ambient.state.collectAsStateWithLifecycle()
    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(start = 8.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDone) { Text("‹ " + stringResource(R.string.settings), color = colors.accent) }
            Text(stringResource(R.string.morning_welcome), style = MaterialTheme.typography.titleMedium, color = colors.text, modifier = Modifier.semantics { heading() })
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp)) {
            Group { SettingSwitch(stringResource(R.string.welcome_show_each_day), settings.isOn, welcome::setOn) }
            Footer(stringResource(R.string.welcome_show_each_day_footer))

            Header(stringResource(R.string.welcome_greeting))
            OutlinedTextField(
                value = settings.name,
                onValueChange = welcome::setName,
                label = { Text(stringResource(R.string.welcome_your_first_name)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, autoCorrectEnabled = false),
                modifier = Modifier.fillMaxWidth(),
            )
            Footer(stringResource(R.string.welcome_name_footer))

            // Only while Ambient Sounds is switched on (Settings › Features).
            if (showsAmbient) {
                Spacer(Modifier.size(20.dp))
                Group { SettingSwitch(stringResource(R.string.welcome_ease_in_sounds), settings.playsSounds, welcome::setPlaysSounds) }
                Footer(
                    if (ambient.mix.isEmpty()) stringResource(R.string.welcome_choose_sounds_first)
                    else stringResource(R.string.welcome_plays_sounds, ambient.summary(context)),
                )
            }

            Spacer(Modifier.size(20.dp))
            Group { Row_(stringResource(R.string.preview), onClick = onPreview, icon = "☀") }
        }
    }
}
