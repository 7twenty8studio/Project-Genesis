package com.genesis.core.design

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import com.genesis.core.domain.theme.ReaderTheme
import com.genesis.core.domain.theme.ThemePalette

/** The brand's own colours (BrandColors.swift): cream, sand, copper, walnut, ink. */
object BrandColors {
    val cream = Color(0xFFF9EBD7)
    val sand = Color(0xFFE0B48D)
    val copper = Color(0xFFB9825A)
    val walnut = Color(0xFF7A4E2D)
    val ink = Color(0xFF4A2E1A)
}

/** A palette's colours for Compose. */
data class ReaderColors(
    val background: Color,
    val surface: Color,
    val text: Color,
    val secondaryText: Color,
    val accent: Color,
    val separator: Color,
    val isDark: Boolean,
)

fun ThemePalette.toColors(isDark: Boolean) = ReaderColors(
    background = Color(0xFF000000 or background.toLong()),
    surface = Color(0xFF000000 or surface.toLong()),
    text = Color(0xFF000000 or text.toLong()),
    secondaryText = Color(0xFF000000 or secondaryText.toLong()),
    accent = Color(0xFF000000 or accent.toLong()),
    separator = Color(0xFF000000 or separator.toLong()),
    isDark = isDark,
)

val LocalReaderColors = staticCompositionLocalOf { ReaderTheme.PAPER.palette.toColors(false) }

/**
 * Versely's theme: the reading theme sets every screen's colours (as on
 * iOS, where the app's colour scheme follows the theme), never the
 * wallpaper's dynamic colours.
 */
@Composable
fun VerselyTheme(theme: ReaderTheme = ReaderTheme.AUTOMATIC, content: @Composable () -> Unit) {
    val resolved = theme.resolved(systemIsDark = isSystemInDarkTheme())
    val colors = resolved.palette.toColors(resolved.isDark)
    CompositionLocalProvider(LocalReaderColors provides colors) {
        MaterialTheme(colorScheme = colors.toColorScheme(), typography = VerselyTypography, content = content)
    }
}

private fun ReaderColors.toColorScheme(): ColorScheme {
    val base = if (isDark) darkColorScheme() else lightColorScheme()
    return base.copy(
        primary = accent,
        onPrimary = background,
        secondary = accent,
        onSecondary = background,
        background = background,
        onBackground = text,
        surface = background,
        onSurface = text,
        surfaceVariant = surface,
        onSurfaceVariant = secondaryText,
        surfaceContainer = surface,
        surfaceContainerLow = surface,
        surfaceContainerHigh = surface,
        surfaceContainerHighest = surface,
        outline = separator,
        outlineVariant = separator,
    )
}
