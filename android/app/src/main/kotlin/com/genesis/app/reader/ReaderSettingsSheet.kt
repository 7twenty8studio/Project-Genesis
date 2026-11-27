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
import com.genesis.core.domain.theme.ReaderTheme
import kotlin.math.roundToInt

/**
 * The "Aa" sheet, as ReaderSettingsSheet.swift: theme, text size, line
 * spacing and typeface. Premium themes and faces show their tag and can't
 * be chosen without Premium. Margins, page turns and the rest follow with
 * the paged reader.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReaderSettingsSheet(
    preferences: ReaderPreferences,
    onChange: ((ReaderPreferences) -> ReaderPreferences) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalReaderColors.current
    val premium = Entitlements.isPremium
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = colors.background,
    ) {
        Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(bottom = 24.dp)) {
            Text(
                stringResource(R.string.reading),
                style = MaterialTheme.typography.titleLarge,
                color = colors.text,
                modifier = Modifier.padding(horizontal = 24.dp).semantics { heading() },
            )

            SectionTitle(R.string.theme)
            LazyRow(
                contentPadding = PaddingValues(horizontal = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
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

            SectionTitle(R.string.text)
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 24.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                val smaller = stringResource(R.string.smaller_text)
                val larger = stringResource(R.string.larger_text)
                OutlinedButton(
                    onClick = { onChange { it.smaller() } },
                    enabled = preferences.fontSize > ReaderPreferences.FONT_SIZE_RANGE.start,
                    modifier = Modifier.semantics { contentDescription = smaller },
                ) { Text("A", fontSize = 14.sp) }
                Text(
                    stringResource(R.string.font_size_points, preferences.fontSize.roundToInt()),
                    color = colors.text,
                    style = MaterialTheme.typography.bodyLarge,
                )
                OutlinedButton(
                    onClick = { onChange { it.larger() } },
                    enabled = preferences.fontSize < ReaderPreferences.FONT_SIZE_RANGE.endInclusive,
                    modifier = Modifier.semantics { contentDescription = larger },
                ) { Text("A", fontSize = 22.sp) }
            }
            Text(
                stringResource(R.string.line_spacing),
                color = colors.secondaryText,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(start = 24.dp, top = 16.dp),
            )
            Slider(
                value = preferences.lineSpacing.toFloat(),
                onValueChange = { value -> onChange { it.copy(lineSpacing = value.toDouble()) } },
                valueRange = ReaderPreferences.LINE_SPACING_RANGE.start.toFloat()..ReaderPreferences.LINE_SPACING_RANGE.endInclusive.toFloat(),
                modifier = Modifier.padding(horizontal = 24.dp),
            )

            SectionTitle(R.string.font)
            for (font in ReaderFont.offered) {
                FontRow(
                    font = font,
                    selected = font == preferences.font,
                    locked = font.isPremium && !premium,
                    onClick = { onChange { it.copy(font = font) } },
                )
            }
        }
    }
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
private fun PremiumTag() {
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
