package com.genesis.app.settings

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.background
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import androidx.compose.foundation.selection.toggleable
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.BuildConfig
import com.genesis.app.R
import com.genesis.core.design.LocalReaderColors

/**
 * Settings, as on iOS: Account, Reading (the reader's look), Notifications,
 * Language, and About Versely with the version. Features and the rest
 * join as their features arrive.
 */
@Composable
fun SettingsScreen(
    accountTitle: String?,
    onAccount: () -> Unit,
    onReading: () -> Unit,
    onNotifications: () -> Unit,
    onGoals: () -> Unit,
    onFeatures: () -> Unit = {},
    showsGoals: Boolean = true,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    var language by remember { mutableStateOf(AppLanguageChoice.saved(context)) }
    val version = remember {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: ""
    }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.settings),
                style = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onDone) {
                Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold)
            }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp)) {
            Group {
                // The account's email once signed in, else Sign In (as iOS's Account row).
                Row_(accountTitle ?: stringResource(R.string.sign_in), onClick = onAccount, trailing = "›", label = stringResource(R.string.account))
            }
            Spacer(Modifier.size(20.dp))
            Group {
                Row_(stringResource(R.string.reading), onClick = onReading, trailing = "›")
                HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                Row_(stringResource(R.string.notifications), onClick = onNotifications, trailing = "›")
                if (showsGoals) {
                    HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                    Row_(stringResource(R.string.goals_and_streaks), onClick = onGoals, trailing = "›")
                }
                HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                Row_(stringResource(R.string.features), onClick = onFeatures, trailing = "›")
            }

            Header(stringResource(R.string.listening))
            val listening = (context.applicationContext as com.genesis.app.VerselyApplication).listening.settings
            val listeningPreferences by listening.state.collectAsStateWithLifecycle()
            Group {
                SettingSwitch(stringResource(R.string.follow_along), listeningPreferences.followsAlong, listening::setFollowsAlong)
                HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                SettingSwitch(stringResource(R.string.continue_next_chapter), listeningPreferences.continuesToNextChapter, listening::setContinuesToNextChapter)
            }
            Footer(stringResource(R.string.follow_along_footer))

            Header(stringResource(R.string.language))
            Group {
                AppLanguageChoice.entries.forEachIndexed { index, choice ->
                    val title = choice.nativeName ?: stringResource(R.string.same_as_phone)
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .selectable(selected = language == choice, role = Role.RadioButton) {
                                if (language == choice) return@selectable
                                language = choice
                                AppLanguageChoice.save(context, choice)
                                // Android 13+ redraws by itself; Android 12 starts the screen again.
                                if (Build.VERSION.SDK_INT < 33) (context as? Activity)?.recreate()
                            }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(title, style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.weight(1f))
                        if (language == choice) Text("✓", color = colors.accent, fontWeight = FontWeight.SemiBold)
                    }
                    if (index < AppLanguageChoice.entries.lastIndex) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                }
            }
            Footer(stringResource(R.string.language_footer))

            if (BuildConfig.DEBUG) {
                Header(stringResource(R.string.developer))
                Group {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.test_as_premium), style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.weight(1f))
                        Switch(
                            checked = Entitlements.isPremium,
                            onCheckedChange = { Entitlements.setTestingPremium(context, it) },
                            colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                        )
                    }
                }
            }

            Header(stringResource(R.string.about_versely))
            Footer(stringResource(R.string.version, version))
        }
    }
}

@Composable
internal fun SettingSwitch(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    val colors = LocalReaderColors.current
    Row(
        Modifier.fillMaxWidth().toggleable(value = checked, role = Role.Switch, onValueChange = onChange).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = null, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent))
    }
}

@Composable
internal fun Group(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().background(LocalReaderColors.current.surface, RoundedCornerShape(14.dp))) { content() }
}

@Composable
internal fun Row_(title: String, onClick: () -> Unit, trailing: String? = null, label: String? = null) {
    val colors = LocalReaderColors.current
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            if (label != null) Text(label, style = MaterialTheme.typography.labelMedium, color = colors.secondaryText)
            Text(title, style = MaterialTheme.typography.bodyLarge, color = colors.text)
        }
        if (trailing != null) Text(trailing, color = colors.secondaryText, style = MaterialTheme.typography.titleLarge)
    }
}

@Composable
internal fun Header(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        color = LocalReaderColors.current.secondaryText,
        modifier = Modifier.padding(start = 16.dp, top = 28.dp, bottom = 8.dp).semantics { heading() },
    )
}

@Composable
internal fun Footer(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = LocalReaderColors.current.secondaryText,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp),
    )
}
