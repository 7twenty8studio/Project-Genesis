package com.genesis.app.welcome

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.plans.appLanguage
import com.genesis.app.plans.enrollmentTitle
import com.genesis.app.reader.ReaderViewModel
import com.genesis.app.reader.backdrop.rememberReduceMotion
import com.genesis.app.settings.Entitlements
import com.genesis.core.design.LocalReaderColors
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.app.features.shows
import com.genesis.core.design.rememberFontFamily
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.features.OptionalFeature
import com.genesis.core.domain.home.DailyVerse
import com.genesis.core.domain.home.Greeting
import com.genesis.core.domain.plans.PlanEnrollment
import com.genesis.core.domain.welcome.MorningWelcomeRules
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * The Premium morning welcome, as MorningWelcomeView.swift: the room
 * brightens, the greeting appears, today's verse fades in (verbatim, from
 * the Bible being read, or a free one in its language beside a YouVersion
 * Bible), then today's reading and the buttons, while the person's ambient
 * sounds ease in. With Reduce Motion everything simply appears.
 */
@Composable
fun MorningWelcomeScreen(
    reader: ReaderViewModel,
    plans: List<PlanEnrollment>,
    signInName: String?,
    isPreview: Boolean = false,
    onReadChapter: (ChapterId) -> Unit,
    onContinue: () -> Unit,
    onClose: () -> Unit,
) {
    val colors = LocalReaderColors.current
    val app = LocalContext.current.applicationContext as VerselyApplication
    val settings by app.welcome.settings.collectAsStateWithLifecycle()
    val features by app.features.enabled.collectAsStateWithLifecycle()
    val flags by app.flags.values.collectAsStateWithLifecycle()
    val preferences = LocalReaderPreferences.current
    val reduceMotion = rememberReduceMotion()
    val name = MorningWelcomeRules.firstName(settings.name) ?: MorningWelcomeRules.firstName(signInName)
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    val language = appLanguage()

    // Today's verse, verbatim from the Bible Premium tools read.
    val daily = remember(today) { DailyVerse.verse(today, zone) }
    val verse by produceState<Triple<String, String, String>?>(null, daily) {
        val bible = reader.premiumToolsBible()
        value = reader.versesIn(bible, listOf(daily))?.let { (verses, abbreviation, bibleLanguage) ->
            verses[daily]?.let { Triple(it.displayText, abbreviation, bibleLanguage) }
        }
    }

    // 0 dim; 1 greeting; 2 verse; 3 reading and buttons.
    val light = remember { Animatable(if (reduceMotion) 1f else 0f) }
    val greeting = remember { Animatable(if (reduceMotion) 1f else 0f) }
    val verseIn = remember { Animatable(if (reduceMotion) 1f else 0f) }
    val rest = remember { Animatable(if (reduceMotion) 1f else 0f) }
    var startedSounds by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (!isPreview) app.welcome.markShown()
        if (!reduceMotion) {
            delay(350)
            launch { light.animateTo(1f, tween(1200)) }
            greeting.animateTo(1f, tween(1200))
            delay(200)
            verseIn.animateTo(1f, tween(800))
            delay(200)
            rest.animateTo(1f, tween(800))
        }
        // The person's own mix, faded in; nothing when none is chosen or something already plays.
        val ambient = app.ambient
        if (settings.playsSounds && Entitlements.isPremium && features.shows(OptionalFeature.AMBIENT_SOUNDS, flags) &&
            ambient.state.value.mix.isNotEmpty() && !ambient.state.value.isPlaying
        ) {
            ambient.play()
            startedSounds = true
        }
    }

    fun finish(then: (() -> Unit)?) {
        if (isPreview && startedSounds) app.ambient.pause()
        onClose()
        if (!isPreview) then?.invoke()
    }

    Box(Modifier.fillMaxSize().background(colors.background)) {
        // The page, dim at first, brightening like morning light, with the theme's own motion softer behind.
        Box(
            Modifier.fillMaxSize().drawBehind {
                drawRect(Brush.radialGradient(listOf(colors.accent.copy(alpha = 0.18f * light.value), Color.Transparent), center = androidx.compose.ui.geometry.Offset(size.width / 2, 0f), radius = 520.dp.toPx()))
            },
        )
        val theme = preferences.theme.resolved(androidx.compose.foundation.isSystemInDarkTheme())
        Box(Modifier.fillMaxSize().alpha(0.7f)) {
            val season = theme.season
            if (season != null && preferences.seasonalEffects) key(season) { com.genesis.app.reader.backdrop.SeasonalEffect(season) }
            else if (theme.hasStars) com.genesis.app.reader.backdrop.StarlightSky(textInsets = null, skyBand = 160.dp)
        }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f * (1f - light.value))))

        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .systemBarsPadding()
                .padding(horizontal = 28.dp, vertical = 48.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.widthIn(max = 560.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(28.dp)) {
                Column(
                    Modifier.alpha(greeting.value).offset(y = (8 * (1 - greeting.value)).dp).semantics(mergeDescendants = true) {},
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    val pattern = android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "EEEEMMMMd")
                    Text(DateTimeFormatter.ofPattern(pattern).format(today), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
                    Text(
                        welcomeGreeting(Greeting.at(LocalTime.now().hour), name),
                        style = MaterialTheme.typography.displaySmall.copy(fontFamily = FontFamily.Serif),
                        color = colors.text,
                    )
                }
                verse?.let { (text, abbreviation, bibleLanguage) ->
                    Column(
                        Modifier.alpha(verseIn.value).offset(y = (12 * (1 - verseIn.value)).dp).semantics(mergeDescendants = true) {},
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(text, fontFamily = rememberFontFamily(preferences.font.available(Entitlements.isPremium)), fontSize = 22.sp, lineHeight = 32.sp, color = colors.text)
                        Text(
                            "${ReferenceParser.describe(daily.rawValue, language = bibleLanguage)} · $abbreviation",
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.SemiBold,
                            color = colors.accent,
                        )
                    }
                }
                Column(Modifier.alpha(rest.value), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    val enrollment = plans.firstOrNull { it.isActive && it.plan != null }
                        ?.takeIf { features.shows(OptionalFeature.PLANS, flags) }
                    val progress = enrollment?.progress
                    val day = progress?.takeIf { !it.isComplete }?.todaysDay(today)
                    val first = day?.spans?.firstOrNull()?.first
                    if (enrollment != null && day != null && first != null) {
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(colors.surface)
                                .clickable { finish { onReadChapter(first) } }.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                        ) {
                            Text("📅", fontSize = 20.sp)
                            Column(Modifier.weight(1f)) {
                                Text(stringResource(R.string.todays_reading), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.secondaryText)
                                Text(day.title(language), style = MaterialTheme.typography.titleMedium.copy(fontFamily = FontFamily.Serif), color = colors.text)
                                Text(enrollmentTitle(enrollment), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                            }
                            Text("›", style = MaterialTheme.typography.titleLarge, color = colors.secondaryText)
                        }
                    }
                    Button(
                        onClick = { finish(onContinue) },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text(stringResource(R.string.continue_reading_button), fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(vertical = 6.dp)) }
                    TextButton(onClick = { finish(null) }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.not_now), color = colors.secondaryText)
                    }
                }
            }
        }
    }
}

/** "Good morning, Jeovanni." by the hour; without a name, "Good morning." */
@Composable
private fun welcomeGreeting(greeting: Greeting, name: String?): String = when (greeting) {
    Greeting.MORNING -> if (name != null) stringResource(R.string.welcome_good_morning_name, name) else stringResource(R.string.welcome_good_morning)
    Greeting.AFTERNOON -> if (name != null) stringResource(R.string.welcome_good_afternoon_name, name) else stringResource(R.string.welcome_good_afternoon)
    Greeting.EVENING -> if (name != null) stringResource(R.string.welcome_good_evening_name, name) else stringResource(R.string.welcome_good_evening)
}
