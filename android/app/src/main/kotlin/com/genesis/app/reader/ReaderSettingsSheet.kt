package com.genesis.app.reader

import androidx.annotation.StringRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.app.settings.Entitlements
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.rememberFontFamily
import com.genesis.core.design.toColors
import com.genesis.core.domain.reader.ReaderFont
import com.genesis.core.domain.reader.ReaderPreferences
import com.genesis.core.domain.reader.ReadingMode
import com.genesis.core.domain.theme.ReaderTheme
import kotlin.math.roundToInt
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.genesis.app.audio.summary
import com.genesis.core.domain.reader.NightReadingSchedule
import com.genesis.core.domain.reader.NightReadingTiming
import com.genesis.core.domain.reader.NightTheme
import com.genesis.core.domain.reader.PageTurnStyle
import com.genesis.core.domain.reader.ReaderMargins
import com.genesis.core.domain.reader.TextLayout

/**
 * The "Aa" sheet, as ReaderSettingsSheet.swift: theme, brightness and the
 * theme's motion; ambient sounds; night reading; text (font, size, line and
 * paragraph spacing, margins, the phone's font size); layout (pages or
 * scroll, page turn, two-page spread, paragraphs or verse by verse, verse
 * numbers, large first letter, page-turn sound and haptic, left-handed);
 * and Reset to Defaults. Premium themes and faces show their tag and can't
 * be chosen without Premium.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReaderSettingsSheet(
    preferences: ReaderPreferences,
    onChange: ((ReaderPreferences) -> ReaderPreferences) -> Unit,
    onDismiss: () -> Unit,
    onAmbient: (() -> Unit)? = null,
) {
    val colors = LocalReaderColors.current
    val premium = Entitlements.isPremium
    var fonts by remember { mutableStateOf(false) }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = colors.background,
    ) {
        Row(Modifier.fillMaxWidth().padding(start = 8.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (fonts) {
                androidx.compose.material3.TextButton(onClick = { fonts = false }) { Text("‹ " + stringResource(R.string.reading), color = colors.accent) }
            } else Spacer(Modifier.width(72.dp))
            Text(
                stringResource(if (fonts) R.string.font else R.string.reading),
                style = MaterialTheme.typography.titleMedium,
                color = colors.text,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            androidx.compose.material3.TextButton(onClick = onDismiss) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        if (fonts) {
            Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(bottom = 24.dp)) {
                for (font in ReaderFont.offered) {
                    FontRow(
                        font = font,
                        selected = font == preferences.font,
                        locked = font.isPremium && !premium,
                        onClick = { onChange { it.copy(font = font) } },
                    )
                }
            }
            return@ModalBottomSheet
        }
        Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(bottom = 24.dp)) {
            // Theme, brightness and the theme's motion.
            LazyRow(
                contentPadding = PaddingValues(horizontal = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.padding(top = 8.dp),
            ) {
                items(ReaderTheme.entries) { theme ->
                    ThemeSwatch(
                        theme = theme,
                        selected = theme == preferences.theme,
                        locked = theme.isPremium && !premium,
                        onClick = { onChange { it.copy(theme = theme) } },
                    )
                }
            }
            BrightnessRow()
            val shown = preferences.theme.resolved(androidx.compose.foundation.isSystemInDarkTheme())
            if (shown.season != null || shown.isScene) {
                val season = shown.season != null
                SwitchRow(stringResource(if (season) R.string.seasonal_touches else R.string.gentle_motion), preferences.seasonalEffects) { on -> onChange { it.copy(seasonalEffects = on) } }
                Footer(stringResource(if (season) R.string.seasonal_touches_footer else R.string.gentle_motion_footer))
            }

            if (onAmbient != null) {
                Divider()
                val ambient = (androidx.compose.ui.platform.LocalContext.current.applicationContext as com.genesis.app.VerselyApplication).ambient
                val ambientState by ambient.state.collectAsState()
                val context = androidx.compose.ui.platform.LocalContext.current
                NavRow(
                    stringResource(R.string.ambient_title),
                    value = if (ambientState.isPlaying) ambientState.summary(context) else null,
                    locked = !premium,
                    onClick = onAmbient,
                )
                Footer(stringResource(R.string.feature_ambient_detail))
            }

            NightReadingSection(preferences, premium, onChange)

            SectionTitle(R.string.text)
            NavRow(stringResource(R.string.font), value = preferences.font.available(premium).title, onClick = { fonts = true })
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                val smaller = stringResource(R.string.smaller_text)
                val larger = stringResource(R.string.larger_text)
                OutlinedButton(
                    onClick = { onChange { it.smaller() } },
                    enabled = preferences.fontSize > ReaderPreferences.FONT_SIZE_RANGE.start,
                    modifier = Modifier.semantics { contentDescription = smaller },
                ) { Text("A", fontSize = 14.sp, color = colors.text) }
                Text(stringResource(R.string.font_size_points, preferences.fontSize.roundToInt()), color = colors.secondaryText, style = MaterialTheme.typography.bodyMedium)
                OutlinedButton(
                    onClick = { onChange { it.larger() } },
                    enabled = preferences.fontSize < ReaderPreferences.FONT_SIZE_RANGE.endInclusive,
                    modifier = Modifier.semantics { contentDescription = larger },
                ) { Text("A", fontSize = 22.sp, color = colors.text) }
            }
            LabeledSlider(stringResource(R.string.line_spacing), preferences.lineSpacing, ReaderPreferences.LINE_SPACING_RANGE) { v -> onChange { it.copy(lineSpacing = v) } }
            LabeledSlider(stringResource(R.string.paragraph_spacing), preferences.paragraphSpacing, ReaderPreferences.PARAGRAPH_SPACING_RANGE) { v -> onChange { it.copy(paragraphSpacing = v) } }
            ChoiceRow(stringResource(R.string.margins), ReaderMargins.entries, preferences.margins, { stringResource(it.title) }) { m -> onChange { it.copy(margins = m) } }
            SwitchRow(stringResource(R.string.follow_system_font_size), preferences.followsDynamicType) { on -> onChange { it.copy(followsDynamicType = on) } }

            SectionTitle(R.string.layout)
            Segmented(ReadingMode.entries, preferences.readingMode, { stringResource(if (it == ReadingMode.PAGE) R.string.reading_mode_pages else R.string.reading_mode_scroll) }) { mode -> onChange { it.copy(readingMode = mode) } }
            if (preferences.readingMode == ReadingMode.PAGE) {
                Text(stringResource(R.string.page_turn), color = colors.secondaryText, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(start = 24.dp, top = 14.dp, bottom = 6.dp))
                Segmented(PageTurnStyle.entries, preferences.pageTurn, { stringResource(if (it == PageTurnStyle.SLIDE) R.string.page_turn_slide else R.string.page_turn_curl) }) { turn -> onChange { it.copy(pageTurn = turn) } }
                SwitchRow(stringResource(R.string.two_page_spread), preferences.twoPageSpread, detail = stringResource(R.string.two_page_spread_detail)) { on -> onChange { it.copy(twoPageSpread = on) } }
            }
            ChoiceRow(stringResource(R.string.text), TextLayout.entries, preferences.layout, { stringResource(if (it == TextLayout.PARAGRAPHS) R.string.text_layout_paragraphs else R.string.text_layout_verse_by_verse) }) { l -> onChange { it.copy(layout = l) } }
            SwitchRow(stringResource(R.string.verse_numbers), preferences.showsVerseNumbers) { on -> onChange { it.copy(showsVerseNumbers = on) } }
            SwitchRow(stringResource(R.string.large_first_letter), preferences.largeInitial) { on -> onChange { it.copy(largeInitial = on) } }
            if (preferences.readingMode == ReadingMode.PAGE) {
                SwitchRow(stringResource(R.string.page_turn_sound), preferences.pageTurnSound) { on -> onChange { it.copy(pageTurnSound = on) } }
                if (preferences.pageTurnSound) {
                    LabeledSlider(stringResource(R.string.page_turn_volume), preferences.pageTurnVolume, 0.0..1.0, steps = 3) { v -> onChange { it.copy(pageTurnVolume = v) } }
                }
                SwitchRow(stringResource(R.string.page_turn_haptic), preferences.pageTurnHaptic) { on -> onChange { it.copy(pageTurnHaptic = on) } }
                if (preferences.pageTurnHaptic) {
                    LabeledSlider(stringResource(R.string.page_turn_strength), preferences.pageTurnHapticStrength, ReaderPreferences.HAPTIC_STRENGTH_RANGE) { v -> onChange { it.copy(pageTurnHapticStrength = v) } }
                }
            }
            SwitchRow(stringResource(R.string.left_handed_mode), preferences.leftHanded, detail = stringResource(R.string.left_handed_detail)) { on -> onChange { it.copy(leftHanded = on) } }

            Divider()
            androidx.compose.material3.TextButton(onClick = { onChange { ReaderPreferences() } }, modifier = Modifier.padding(horizontal = 12.dp)) {
                Text(stringResource(R.string.reset_to_defaults), color = androidx.compose.ui.graphics.Color(0xFFC0392B))
            }
        }
    }
}

/** Aa › Night Reading, as NightReadingSettings.swift. */
@Composable
private fun NightReadingSection(preferences: ReaderPreferences, premium: Boolean, onChange: ((ReaderPreferences) -> ReaderPreferences) -> Unit) {
    val schedule = preferences.nightReading
    fun update(change: (NightReadingSchedule) -> NightReadingSchedule) = onChange { it.copy(nightReading = change(it.nightReading)) }
    SectionTitle(R.string.night_reading)
    ChoiceRow(
        stringResource(R.string.night_switch_to),
        NightTheme.entries,
        schedule.theme,
        { theme ->
            when (theme) {
                NightTheme.OFF -> stringResource(R.string.off)
                NightTheme.NIGHT -> stringResource(R.string.theme_night)
                NightTheme.STARLIGHT -> stringResource(R.string.theme_starlight) + if (!premium) " · " + stringResource(R.string.premium) else ""
            }
        },
        enabled = { !it.isPremium || premium },
    ) { theme -> update { it.copy(theme = theme) } }
    if (schedule.theme != NightTheme.OFF) {
        ChoiceRow(
            stringResource(R.string.`when`),
            NightReadingTiming.entries,
            schedule.timing,
            { stringResource(if (it == NightReadingTiming.DARK_MODE) R.string.night_with_dark_mode else R.string.night_at_set_hours) },
        ) { timing -> update { it.copy(timing = timing) } }
        if (schedule.timing == NightReadingTiming.HOURS) {
            ChoiceRow(stringResource(R.string.night_from), (0..23).toList(), schedule.startHour, { hourLabel(it) }) { h -> update { it.copy(startHour = h) } }
            ChoiceRow(stringResource(R.string.night_until), (0..23).toList(), schedule.endHour, { hourLabel(it) }) { h -> update { it.copy(endHour = h) } }
        }
    }
    Footer(
        stringResource(
            when {
                schedule.theme == NightTheme.OFF -> R.string.night_footer_off
                schedule.theme.isPremium && !premium -> R.string.night_footer_locked
                schedule.timing == NightReadingTiming.DARK_MODE -> R.string.night_footer_dark_mode
                schedule.startHour == schedule.endHour -> R.string.night_footer_same_hours
                else -> R.string.night_footer_hours
            },
        ),
    )
}

/** "8 PM" or "20:00", as the phone's clock prefers. */
@Composable
private fun hourLabel(hour: Int): String {
    val context = androidx.compose.ui.platform.LocalContext.current
    val format = android.text.format.DateFormat.getTimeFormat(context)
    val calendar = java.util.Calendar.getInstance().apply { set(2001, 5, 15, hour, 0, 0) }
    return format.format(calendar.time)
}

/** The screen's brightness while Versely is open, as iOS's brightness slider. */
@Composable
private fun BrightnessRow() {
    val colors = LocalReaderColors.current
    val view = androidx.compose.ui.platform.LocalView.current
    val window = remember(view) { (view.context as? android.app.Activity)?.window ?: (view.context as? android.content.ContextWrapper)?.baseContext.let { it as? android.app.Activity }?.window }
    var value by remember {
        val current = window?.attributes?.screenBrightness ?: -1f
        mutableStateOf(if (current < 0f) runCatching { android.provider.Settings.System.getInt(view.context.contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS) / 255f }.getOrDefault(0.5f) else current)
    }
    val label = stringResource(R.string.brightness)
    Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("☼", color = colors.secondaryText, fontSize = 14.sp)
        Slider(
            value = value,
            onValueChange = { v ->
                value = v
                window?.let { w -> w.attributes = w.attributes.apply { screenBrightness = v.coerceIn(0.02f, 1f) } }
            },
            colors = SliderDefaults.colors(thumbColor = colors.accent, activeTrackColor = colors.accent),
            modifier = Modifier.weight(1f).padding(horizontal = 10.dp).semantics { contentDescription = label },
        )
        Text("☀", color = colors.secondaryText, fontSize = 20.sp)
    }
}

@Composable
private fun SwitchRow(title: String, checked: Boolean, detail: String? = null, onChange: (Boolean) -> Unit) {
    val colors = LocalReaderColors.current
    Row(
        Modifier.fillMaxWidth().clickable(role = Role.Switch) { onChange(!checked) }.padding(horizontal = 24.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, color = colors.text, style = MaterialTheme.typography.bodyLarge)
            if (detail != null) Text(detail, color = colors.secondaryText, style = MaterialTheme.typography.bodySmall)
        }
        Switch(checked = checked, onCheckedChange = onChange, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent))
    }
}

@Composable
private fun NavRow(title: String, value: String? = null, locked: Boolean = false, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Row(
        Modifier.fillMaxWidth().clickable(enabled = !locked, role = Role.Button, onClick = onClick).padding(horizontal = 24.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = colors.text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        if (locked) PremiumTag() else if (value != null) Text(value, color = colors.secondaryText, maxLines = 1, modifier = Modifier.padding(end = 6.dp).widthIn(max = 180.dp))
        Text("›", color = colors.secondaryText, fontSize = 20.sp)
    }
}

/** A setting with a few choices, its value on the right opening a menu (iOS's menu picker). */
@Composable
private fun <T> ChoiceRow(title: String, choices: List<T>, selected: T, label: @Composable (T) -> String, enabled: (T) -> Boolean = { true }, onPick: (T) -> Unit) {
    val colors = LocalReaderColors.current
    var open by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().clickable(role = Role.DropdownList) { open = true }.padding(horizontal = 24.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = colors.text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Box {
            Text(label(selected) + "  ⌄", color = colors.accent)
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                for (choice in choices) {
                    DropdownMenuItem(
                        text = { Text((if (choice == selected) "✓ " else "") + label(choice)) },
                        enabled = enabled(choice),
                        onClick = { open = false; onPick(choice) },
                    )
                }
            }
        }
    }
}

@Composable
private fun <T> Segmented(choices: List<T>, selected: T, label: @Composable (T) -> String, onPick: (T) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 24.dp)) {
        choices.forEachIndexed { index, choice ->
            SegmentedButton(
                selected = choice == selected,
                onClick = { onPick(choice) },
                shape = SegmentedButtonDefaults.itemShape(index, choices.size),
            ) { Text(label(choice)) }
        }
    }
}

@Composable
private fun LabeledSlider(title: String, value: Double, range: ClosedFloatingPointRange<Double>, steps: Int = 0, onChange: (Double) -> Unit) {
    val colors = LocalReaderColors.current
    Text(title, color = colors.secondaryText, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(start = 24.dp, top = 12.dp))
    Slider(
        value = value.toFloat(),
        onValueChange = { onChange(it.toDouble()) },
        valueRange = range.start.toFloat()..range.endInclusive.toFloat(),
        steps = steps,
        colors = SliderDefaults.colors(thumbColor = colors.accent, activeTrackColor = colors.accent),
        modifier = Modifier.padding(horizontal = 24.dp).semantics { contentDescription = title },
    )
}

@Composable
private fun Footer(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = LocalReaderColors.current.secondaryText,
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp),
    )
}

@Composable
private fun Divider() {
    androidx.compose.material3.HorizontalDivider(Modifier.padding(vertical = 12.dp), color = LocalReaderColors.current.separator)
}

@get:StringRes
private val ReaderMargins.title: Int
    get() = when (this) {
        ReaderMargins.NARROW -> R.string.margins_narrow
        ReaderMargins.REGULAR -> R.string.margins_regular
        ReaderMargins.WIDE -> R.string.margins_wide
    }

@Composable
private fun SectionTitle(@StringRes title: Int) {
    Text(
        stringResource(title),
        style = MaterialTheme.typography.titleMedium,
        color = LocalReaderColors.current.text,
        modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 24.dp, bottom = 12.dp).semantics { heading() },
    )
}

@Composable
private fun ThemeSwatch(theme: ReaderTheme, selected: Boolean, locked: Boolean, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    val swatch = theme.resolved(systemIsDark = colors.isDark).let { it.palette.toColors(it.isDark) }
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .width(64.dp)
            .selectable(selected = selected, enabled = !locked, role = Role.RadioButton, onClick = onClick)
            .alpha(if (locked) 0.55f else 1f),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(52.dp)
                .background(swatch.background, CircleShape)
                .border(
                    if (selected) BorderStroke(2.5.dp, colors.accent) else BorderStroke(1.dp, colors.separator),
                    CircleShape,
                ),
        ) {
            Text("Aa", color = swatch.text, fontSize = 17.sp, fontWeight = FontWeight.Medium)
        }
        Spacer(Modifier.height(6.dp))
        Text(stringResource(theme.title), style = MaterialTheme.typography.bodyMedium, color = colors.text, maxLines = 1)
        if (locked) PremiumTag()
    }
}

@Composable
private fun FontRow(font: ReaderFont, selected: Boolean, locked: Boolean, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .selectable(selected = selected, enabled = !locked, role = Role.RadioButton, onClick = onClick)
            .background(if (selected) colors.surface else colors.background)
            .padding(horizontal = 24.dp, vertical = 12.dp)
            .alpha(if (locked) 0.55f else 1f),
    ) {
        Column(Modifier.weight(1f)) {
            Text(font.title, fontFamily = rememberFontFamily(font), fontSize = 20.sp, color = colors.text)
            Text(stringResource(font.caption), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
        }
        when {
            locked -> PremiumTag()
            selected -> Text("✓", color = colors.accent, fontSize = 20.sp)
        }
    }
}

@Composable
internal fun PremiumTag() {
    val colors = LocalReaderColors.current
    Text(
        stringResource(R.string.premium),
        style = MaterialTheme.typography.labelLarge.copy(fontSize = 11.sp),
        color = colors.accent,
        modifier = Modifier
            .padding(top = 2.dp)
            .border(1.dp, colors.accent, RoundedCornerShape(50))
            .padding(horizontal = 6.dp, vertical = 1.dp),
    )
}

/** The theme's name, as iOS's ReaderTheme.title. */
@get:StringRes
internal val ReaderTheme.title: Int
    get() = when (this) {
        ReaderTheme.AUTOMATIC -> R.string.theme_automatic
        ReaderTheme.PAPER -> R.string.theme_paper
        ReaderTheme.CREAM -> R.string.theme_cream
        ReaderTheme.SEPIA -> R.string.theme_sepia
        ReaderTheme.PARCHMENT -> R.string.theme_parchment
        ReaderTheme.SLATE -> R.string.theme_slate
        ReaderTheme.HIGH_CONTRAST -> R.string.theme_high_contrast
        ReaderTheme.NIGHT -> R.string.theme_night
        ReaderTheme.MIDNIGHT -> R.string.theme_midnight
        ReaderTheme.STARLIGHT -> R.string.theme_starlight
        ReaderTheme.SAGE -> R.string.theme_sage
        ReaderTheme.SEASONS -> R.string.theme_seasons
        ReaderTheme.AUTUMN -> R.string.theme_autumn
        ReaderTheme.WINTER -> R.string.theme_winter
        ReaderTheme.SPRING -> R.string.theme_spring
        ReaderTheme.SUMMER -> R.string.theme_summer
        ReaderTheme.FOREST -> R.string.theme_forest
        ReaderTheme.OCEAN -> R.string.theme_ocean
        ReaderTheme.HEARTH -> R.string.theme_hearth
    }

/** A face's name: Android's own faces by their real names, the bundled ones as on iOS. */
internal val ReaderFont.title: String
    get() = when (this) {
        ReaderFont.NEW_YORK, ReaderFont.GEORGIA, ReaderFont.BASKERVILLE -> "Noto Serif"
        ReaderFont.SF_PRO -> "Roboto"
        ReaderFont.ATKINSON_HYPERLEGIBLE -> "Atkinson Hyperlegible"
        ReaderFont.LITERATA -> "Literata"
        ReaderFont.EB_GARAMOND -> "EB Garamond"
        ReaderFont.CRIMSON_PRO -> "Crimson Pro"
        ReaderFont.SOURCE_SERIF -> "Source Serif"
        ReaderFont.SPECTRAL -> "Spectral"
    }

@get:StringRes
private val ReaderFont.caption: Int
    get() = when (this) {
        ReaderFont.NEW_YORK, ReaderFont.GEORGIA, ReaderFont.BASKERVILLE -> R.string.font_caption_new_york
        ReaderFont.SF_PRO -> R.string.font_caption_sf_pro
        ReaderFont.ATKINSON_HYPERLEGIBLE -> R.string.font_caption_atkinson
        ReaderFont.LITERATA -> R.string.font_caption_literata
        ReaderFont.EB_GARAMOND -> R.string.font_caption_eb_garamond
        ReaderFont.CRIMSON_PRO -> R.string.font_caption_crimson_pro
        ReaderFont.SOURCE_SERIF -> R.string.font_caption_source_serif
        ReaderFont.SPECTRAL -> R.string.font_caption_spectral
    }
