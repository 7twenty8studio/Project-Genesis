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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.background
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
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
 * Settings from Home, as SettingsView.swift: Features, Notifications, Goals
 * & Streaks, Bibles and Account; Reading (Theme & Reading, Listening,
 * Ambient Sounds, Morning Welcome); Send Feedback; About Versely (help, privacy, version);
 * Language; and the note that the reader's Aa holds the same settings.
 * Versely Premium's paywall joins with Google Play Billing.
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
    onBibles: () -> Unit = {},
    onFeedback: () -> Unit = {},
    onAppIcon: () -> Unit = {},
    showsListening: Boolean = true,
    onAmbient: (() -> Unit)? = null,
    offersYouVersionBibles: Boolean = false,
    onMorningWelcome: () -> Unit = {},
    onWidgetStyles: () -> Unit = {},
    onWidgetPhoto: () -> Unit = {},
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    var language by remember { mutableStateOf(AppLanguageChoice.saved(context)) }
    var languageOpen by remember { mutableStateOf(false) }
    var listeningOpen by remember { mutableStateOf(false) }
    val version = remember {
        val info = runCatching { context.packageManager.getPackageInfo(context.packageName, 0) }.getOrNull()
        "${info?.versionName ?: ""} (${info?.longVersionCode ?: ""})"
    }
    val uri = androidx.compose.ui.platform.LocalUriHandler.current

    if (languageOpen) {
        androidx.activity.compose.BackHandler { languageOpen = false }
        LanguageScreen(language, onChoose = { language = it }, onDone = { languageOpen = false }, modifier = modifier)
        return
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
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp).navigationBarsPadding()) {
            Group {
                Row_(stringResource(R.string.features), onClick = onFeatures, trailing = "›", icon = "▦")
                Divider_()
                Row_(stringResource(R.string.notifications), onClick = onNotifications, trailing = "›", icon = "🔔")
                if (showsGoals) {
                    Divider_()
                    Row_(stringResource(R.string.goals_and_streaks), onClick = onGoals, trailing = "›", icon = "◎")
                }
                Divider_()
                Row_(stringResource(R.string.bibles), onClick = onBibles, trailing = "›", icon = "📚")
                Divider_()
                // The account's email once signed in, else Sign In (as iOS's Account row).
                Row_(stringResource(R.string.account), onClick = onAccount, trailing = "›", icon = "👤", value = accountTitle ?: stringResource(R.string.sign_in))
            }

            Header(stringResource(R.string.reading))
            Group {
                Row_(stringResource(R.string.theme_and_reading), onClick = onReading, trailing = "›", icon = "Aa")
                if (showsListening) {
                    Divider_()
                    Row_(stringResource(R.string.listening), onClick = { listeningOpen = true }, trailing = "›", icon = "🎧")
                }
                if (onAmbient != null) {
                    Divider_()
                    Row_(stringResource(R.string.ambient_title), onClick = onAmbient, trailing = "›", icon = "🔈", premium = !Entitlements.isPremium)
                }
                Divider_()
                // Premium: without it the row shows its tag (the paywall comes with Google Play Billing).
                Row_(
                    stringResource(R.string.morning_welcome),
                    onClick = { if (Entitlements.isPremium) onMorningWelcome() },
                    trailing = "›",
                    icon = "🌅",
                    premium = !Entitlements.isPremium,
                )
                Divider_()
                // Open to everyone: Premium styles carry their tag inside.
                Row_(stringResource(R.string.widget_styles), onClick = onWidgetStyles, trailing = "›", icon = "▦")
                Divider_()
                Row_(stringResource(R.string.widget_photo), onClick = onWidgetPhoto, trailing = "›", icon = "🖼")
                Divider_()
                // Open to everyone: the standard icon is free, the others carry their tag inside.
                Row_(stringResource(R.string.app_icon), onClick = onAppIcon, trailing = "›", icon = "◻")
            }

            Spacer(Modifier.size(20.dp))
            Group { Row_(stringResource(R.string.send_feedback), onClick = onFeedback, trailing = "›", icon = "✉") }
            Footer(stringResource(R.string.feedback_footer))

            Header(stringResource(R.string.about_versely))
            Group {
                Row_(stringResource(R.string.help_and_support), onClick = { uri.openUri(SUPPORT_URL) }, trailing = "↗", icon = "?")
                Divider_()
                Row_(stringResource(R.string.privacy_policy), onClick = { uri.openUri(PRIVACY_URL) }, trailing = "↗", icon = "✋")
            }
            Footer(stringResource(R.string.version, version))

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

            Spacer(Modifier.size(20.dp))
            Group {
                Row_(
                    stringResource(R.string.language),
                    onClick = { languageOpen = true },
                    trailing = "›",
                    icon = "🌐",
                    value = language.nativeName ?: stringResource(R.string.same_as_phone),
                )
            }
            Footer(stringResource(R.string.settings_languages_footer))

            Spacer(Modifier.size(12.dp))
            Footer(stringResource(R.string.settings_also_in_reader))
            if (offersYouVersionBibles) Footer(stringResource(R.string.settings_youversion_free))
            Spacer(Modifier.size(24.dp))
        }
    }

    if (listeningOpen) ListeningSettingsSheet { listeningOpen = false }
}

private const val SUPPORT_URL = "https://www.7twenty8studio.com/versely/support"
private const val PRIVACY_URL = "https://www.7twenty8studio.com/versely/privacy"

/** Settings › Language, as LanguageSettingsView.swift. */
@Composable
private fun LanguageScreen(selected: AppLanguageChoice, onChoose: (AppLanguageChoice) -> Unit, onDone: () -> Unit, modifier: Modifier) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(start = 8.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDone) { Text("‹ " + stringResource(R.string.settings), color = colors.accent) }
            Text(stringResource(R.string.language), style = MaterialTheme.typography.titleMedium, color = colors.text, modifier = Modifier.semantics { heading() })
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp)) {
            Group {
                AppLanguageChoice.entries.forEachIndexed { index, choice ->
                    val title = choice.nativeName ?: stringResource(R.string.same_as_phone)
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .selectable(selected = selected == choice, role = Role.RadioButton) {
                                if (selected == choice) return@selectable
                                onChoose(choice)
                                AppLanguageChoice.save(context, choice)
                                // Android 13+ redraws by itself; Android 12 starts the screen again.
                                if (Build.VERSION.SDK_INT < 33) (context as? Activity)?.recreate()
                            }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(title, style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.weight(1f))
                        if (selected == choice) Text("✓", color = colors.accent, fontWeight = FontWeight.SemiBold)
                    }
                    if (index < AppLanguageChoice.entries.lastIndex) Divider_()
                }
            }
            Footer(stringResource(R.string.language_footer))
        }
    }
}

/** Settings › Listening, as AudioSettingsView.swift: speed, follow along, carry on into the next chapter. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun ListeningSettingsSheet(onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    val listening = (LocalContext.current.applicationContext as com.genesis.app.VerselyApplication).listening.settings
    val preferences by listening.state.collectAsStateWithLifecycle()
    androidx.compose.material3.ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.background) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 32.dp).navigationBarsPadding()) {
            Text(stringResource(R.string.listening), style = MaterialTheme.typography.titleMedium, color = colors.text, modifier = Modifier.padding(bottom = 8.dp).semantics { heading() })
            Header(stringResource(R.string.speed))
            val speeds = com.genesis.core.domain.audio.Narration.speeds
            androidx.compose.material3.SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                speeds.forEachIndexed { index, speed ->
                    SegmentedButton(
                        selected = preferences.speed == speed,
                        onClick = { listening.setSpeed(speed) },
                        shape = androidx.compose.material3.SegmentedButtonDefaults.itemShape(index, speeds.size),
                    ) { Text(com.genesis.core.domain.audio.Narration.speedLabel(speed)) }
                }
            }
            Spacer(Modifier.size(20.dp))
            Group {
                SettingSwitch(stringResource(R.string.follow_along), preferences.followsAlong, listening::setFollowsAlong)
                Divider_()
                SettingSwitch(stringResource(R.string.continue_next_chapter), preferences.continuesToNextChapter, listening::setContinuesToNextChapter)
            }
            Footer(stringResource(R.string.follow_along_footer))
        }
    }
}

@Composable
private fun Divider_() = HorizontalDivider(Modifier.padding(start = 16.dp), color = LocalReaderColors.current.separator)

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
internal fun Row_(title: String, onClick: () -> Unit, trailing: String? = null, label: String? = null, icon: String? = null, value: String? = null, premium: Boolean = false) {
    val colors = LocalReaderColors.current
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) {
            Text(icon, color = colors.accent, style = MaterialTheme.typography.bodyLarge, textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.width(28.dp))
            Spacer(Modifier.size(10.dp))
        }
        Column(Modifier.weight(1f)) {
            if (label != null) Text(label, style = MaterialTheme.typography.labelMedium, color = colors.secondaryText)
            Text(title, style = MaterialTheme.typography.bodyLarge, color = colors.text)
        }
        if (premium) com.genesis.app.reader.PremiumTag()
        if (value != null) Text(value, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, maxLines = 1, modifier = Modifier.padding(start = 8.dp, end = 6.dp).widthIn(max = 200.dp))
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
