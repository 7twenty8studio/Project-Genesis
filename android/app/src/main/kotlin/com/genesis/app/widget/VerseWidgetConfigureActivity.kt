package com.genesis.app.widget

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.settings.Entitlements
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.VerselyTheme
import com.genesis.core.domain.widgets.VerseWidgetSource
import kotlinx.coroutines.launch

/**
 * The verse widget's settings (VerseWidgetIntent's "Show" on iOS): Verse of
 * the Day and Random Verse for everyone, the categories and From Your
 * Reading with Premium (a lock and a note otherwise). Opens when the widget
 * is placed and from its Reconfigure; Done saves, back keeps what it was.
 */
class VerseWidgetConfigureActivity : ComponentActivity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        widgetId = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        // Backing out of a new widget still places it, showing the verse of the day.
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        val settings = (application as VerselyApplication).readerSettings
        val glanceId = GlanceAppWidgetManager(this).getGlanceIdBy(widgetId)
        setContent {
            val preferences by settings.preferences.collectAsStateWithLifecycle()
            VerselyTheme(theme = preferences.theme) {
                var current by remember { mutableStateOf<VerseWidgetSource?>(null) }
                var background by remember { mutableStateOf(com.genesis.core.domain.widgets.VerseWidgetBackground.APP) }
                val scope = rememberCoroutineScope()
                androidx.compose.runtime.LaunchedEffect(Unit) {
                    val state = runCatching { getAppWidgetState(this@VerseWidgetConfigureActivity, PreferencesGlanceStateDefinition, glanceId) }.getOrNull()
                    current = VerseWidgetSource.of(state?.get(VerseOfTheDayWidget.SOURCE))
                    background = state?.get(VerseOfTheDayWidget.BACKGROUND) ?: com.genesis.core.domain.widgets.VerseWidgetBackground.APP
                }
                Options(
                    chosen = current,
                    onChoose = { current = it },
                    background = background,
                    onBackground = { background = it },
                    onDone = {
                        val choice = current ?: VerseWidgetSource.VERSE_OF_THE_DAY
                        scope.launch {
                            updateAppWidgetState(this@VerseWidgetConfigureActivity, glanceId) {
                                it[VerseOfTheDayWidget.SOURCE] = choice.raw
                                it[VerseOfTheDayWidget.BACKGROUND] = background
                            }
                            VerseOfTheDayWidget().update(this@VerseWidgetConfigureActivity, glanceId)
                            VerseOfTheDayReceiver.scheduleNextChange(this@VerseWidgetConfigureActivity)
                            finish()
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun Options(chosen: VerseWidgetSource?, onChoose: (VerseWidgetSource) -> Unit, background: String, onBackground: (String) -> Unit, onDone: () -> Unit) {
    val colors = LocalReaderColors.current
    val premium = Entitlements.isPremium
    Column(Modifier.fillMaxSize().background(colors.background).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.verse_of_the_day),
                style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onDone, enabled = chosen != null) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.widget_verse_choose), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
            Text(stringResource(R.string.widget_show), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = colors.secondaryText)
            Column(Modifier.clip(RoundedCornerShape(14.dp)).background(colors.surface)) {
                VerseWidgetSource.entries.forEachIndexed { index, source ->
                    if (index > 0) HorizontalDivider(color = colors.separator)
                    val locked = source.needsPremium && !premium
                    val selected = source == chosen
                    Row(
                        Modifier.fillMaxWidth()
                            .semantics { this.selected = selected }
                            .clickable(enabled = !locked, role = Role.RadioButton) { onChoose(source) }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(stringResource(source.optionRes), color = if (locked) colors.secondaryText else colors.text, modifier = Modifier.weight(1f))
                        when {
                            selected -> Text("✓", color = colors.accent, fontWeight = FontWeight.SemiBold)
                            locked -> Text("🔒 " + stringResource(R.string.premium), style = MaterialTheme.typography.labelMedium, color = colors.secondaryText)
                        }
                    }
                }
            }

            // Background: the look chosen in Versely (Widget Styles), or one for this widget alone.
            Text(stringResource(R.string.widget_background), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = colors.secondaryText, modifier = Modifier.padding(top = 12.dp))
            Column(Modifier.clip(RoundedCornerShape(14.dp)).background(colors.surface)) {
                val choices = listOf(com.genesis.core.domain.widgets.VerseWidgetBackground.APP) + com.genesis.core.domain.widgets.WidgetArtStyle.galleryOrder.map { it.rawValue }
                choices.forEachIndexed { index, raw ->
                    if (index > 0) HorizontalDivider(color = colors.separator)
                    val style = com.genesis.core.domain.widgets.WidgetArtStyle.of(raw)
                    val locked = style?.needsPremium == true && !premium
                    val selected = raw == background
                    Row(
                        Modifier.fillMaxWidth()
                            .semantics { this.selected = selected }
                            .clickable(enabled = !locked, role = Role.RadioButton) { onBackground(raw) }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(style?.let { stringResource(it.titleRes) } ?: stringResource(R.string.chosen_in_versely), color = if (locked) colors.secondaryText else colors.text, modifier = Modifier.weight(1f))
                        when {
                            selected -> Text("✓", color = colors.accent, fontWeight = FontWeight.SemiBold)
                            locked -> Text("🔒 " + stringResource(R.string.premium), style = MaterialTheme.typography.labelMedium, color = colors.secondaryText)
                        }
                    }
                }
            }
        }
    }
}

/** The style's name, as Widget Styles and the widget's Background list have it. */
internal val com.genesis.core.domain.widgets.WidgetArtStyle.titleRes: Int
    get() = when (this) {
        com.genesis.core.domain.widgets.WidgetArtStyle.CLASSIC -> R.string.initial_classic
        com.genesis.core.domain.widgets.WidgetArtStyle.PAPER -> R.string.widget_style_paper
        com.genesis.core.domain.widgets.WidgetArtStyle.NIGHT -> R.string.widget_style_night
        com.genesis.core.domain.widgets.WidgetArtStyle.SPRING -> R.string.widget_style_spring
        com.genesis.core.domain.widgets.WidgetArtStyle.SUMMER -> R.string.widget_style_summer
        com.genesis.core.domain.widgets.WidgetArtStyle.AUTUMN -> R.string.widget_style_autumn
        com.genesis.core.domain.widgets.WidgetArtStyle.WINTER -> R.string.widget_style_winter
        com.genesis.core.domain.widgets.WidgetArtStyle.FOREST -> R.string.widget_style_forest
        com.genesis.core.domain.widgets.WidgetArtStyle.OCEAN -> R.string.widget_style_ocean
        com.genesis.core.domain.widgets.WidgetArtStyle.HEARTH -> R.string.widget_style_hearth
    }
