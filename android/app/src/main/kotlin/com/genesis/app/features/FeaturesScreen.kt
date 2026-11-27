package com.genesis.app.features

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
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
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.settings.Footer
import com.genesis.app.settings.Header
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.features.OptionalFeature

internal val OptionalFeature.titleRes: Int
    get() = when (this) {
        OptionalFeature.PLANS -> R.string.plans_title
        OptionalFeature.PRAYER -> R.string.prayer_journal
        OptionalFeature.MEMORISE -> R.string.memorise_title
        OptionalFeature.LISTEN -> R.string.listen
        OptionalFeature.AMBIENT_SOUNDS -> R.string.feature_ambient
        OptionalFeature.WORD_STUDY -> R.string.feature_word_study
        OptionalFeature.EXPLORE -> R.string.feature_explore
        OptionalFeature.STUDY_ASSISTANT -> R.string.study_action
        OptionalFeature.INSIGHTS -> R.string.feature_insights
        OptionalFeature.MOMENTS -> R.string.feature_moments
        OptionalFeature.TOGETHER -> R.string.feature_together
        OptionalFeature.SERMONS -> R.string.sermon_notes
        OptionalFeature.STUDY_LIBRARY -> R.string.study_library
        OptionalFeature.GOALS -> R.string.feature_goals
        OptionalFeature.NUDGES -> R.string.feature_nudges
        OptionalFeature.CHURCH_SERMONS -> R.string.feature_church_sermons
    }

internal val OptionalFeature.detailRes: Int
    get() = when (this) {
        OptionalFeature.PLANS -> R.string.feature_plans_detail
        OptionalFeature.PRAYER -> R.string.feature_prayer_detail
        OptionalFeature.MEMORISE -> R.string.feature_memorise_detail
        OptionalFeature.LISTEN -> R.string.feature_listen_detail
        OptionalFeature.AMBIENT_SOUNDS -> R.string.feature_ambient_detail
        OptionalFeature.WORD_STUDY -> R.string.feature_word_study_detail
        OptionalFeature.EXPLORE -> R.string.feature_explore_detail
        OptionalFeature.STUDY_ASSISTANT -> R.string.feature_explore_detail
        OptionalFeature.INSIGHTS -> R.string.feature_insights_detail
        OptionalFeature.MOMENTS -> R.string.feature_moments_detail
        OptionalFeature.TOGETHER -> R.string.feature_together_detail
        OptionalFeature.SERMONS -> R.string.feature_sermons_detail
        OptionalFeature.STUDY_LIBRARY -> R.string.feature_study_library_detail
        OptionalFeature.GOALS -> R.string.feature_goals_detail
        OptionalFeature.NUDGES -> R.string.feature_nudges_detail
        OptionalFeature.CHURCH_SERMONS -> R.string.feature_church_sermons_detail
    }

private val OptionalFeature.Area.titleRes: Int
    get() = when (this) {
        OptionalFeature.Area.DAILY -> R.string.area_daily
        OptionalFeature.Area.STUDY -> R.string.study_action
        OptionalFeature.Area.LISTENING -> R.string.area_listening
        OptionalFeature.Area.COMMUNITY -> R.string.tab_together
        OptionalFeature.Area.TOUCHES -> R.string.area_touches
    }

/** A feature with its switch: a title and a short description on a card. */
@Composable
internal fun FeatureSwitchCard(feature: OptionalFeature, on: Boolean, onChange: (Boolean) -> Unit) {
    val colors = LocalReaderColors.current
    Row(
        Modifier
            .fillMaxWidth()
            .background(colors.surface, RoundedCornerShape(18.dp))
            .toggleable(value = on, role = Role.Switch, onValueChange = onChange)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).padding(end = 12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(stringResource(feature.titleRes), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
            Text(stringResource(feature.detailRes), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
        }
        Switch(
            checked = on,
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

/** Settings › Features: the setup's choices, any time, grouped. */
@Composable
fun FeaturesScreen(onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val app = LocalContext.current.applicationContext as VerselyApplication
    val enabled by app.features.enabled.collectAsStateWithLifecycle()
    val flags by app.flags.values.collectAsStateWithLifecycle()
    val offered = FeaturePreferences.offered(flags)

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.features),
                style = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp).widthIn(max = 720.dp)) {
            for (area in OptionalFeature.Area.entries) {
                val items = offered.filter { it.area == area }
                if (items.isEmpty()) continue
                Header(stringResource(area.titleRes))
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (feature in items) FeatureSwitchCard(feature, feature in enabled) { app.features.set(feature, it) }
                }
            }
            Footer(stringResource(R.string.features_footer))
            Spacer(Modifier.size(32.dp))
        }
    }
}

/**
 * The last step of setup, as FeatureChoicesView on iOS: which parts of
 * Versely to show. Continue keeps the suggested set; Keep It Simple shows
 * just the reader.
 */
@Composable
fun MakeVerselyYours(onFinish: () -> Unit) {
    val colors = LocalReaderColors.current
    val app = LocalContext.current.applicationContext as VerselyApplication
    val flags by app.flags.values.collectAsStateWithLifecycle()
    var chosen by rememberSaveable { mutableStateOf(OptionalFeature.defaults.map { it.rawValue }.toSet()) }
    Column(
        Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 24.dp)
            .padding(bottom = 40.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Column(Modifier.padding(top = 40.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.make_versely_yours), fontFamily = FontFamily.Serif, fontSize = 34.sp, color = colors.text, modifier = Modifier.semantics { heading() })
            Text(stringResource(R.string.make_versely_yours_detail), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            for (feature in FeaturePreferences.offered(flags).filter { it.isOfferedInSetup }) {
                FeatureSwitchCard(feature, feature.rawValue in chosen) { on -> chosen = if (on) chosen + feature.rawValue else chosen - feature.rawValue }
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Button(
                onClick = {
                    // Those not offered here (ribbons, nudges…) keep their suggested state, already in `chosen`.
                    app.features.choose(chosen.mapNotNull(OptionalFeature::of).toSet())
                    onFinish()
                },
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.background),
                modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
            ) { Text(stringResource(R.string.continue_button), fontWeight = FontWeight.SemiBold) }
            TextButton(onClick = { app.features.choose(emptySet()); onFinish() }) {
                Text(stringResource(R.string.keep_it_simple), color = colors.accent)
            }
        }
    }
}
