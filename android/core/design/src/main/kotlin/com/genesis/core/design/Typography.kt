package com.genesis.core.design

import android.content.res.AssetManager
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.genesis.core.domain.reader.ReaderFont
import com.genesis.core.domain.reader.ReaderPreferences

/** Screens use the system sans, as iOS uses SF Pro. */
val VerselyTypography = Typography(
    titleLarge = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 22.sp, lineHeight = 28.sp),
    titleMedium = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 22.sp),
    bodyLarge = TextStyle(fontSize = 17.sp, lineHeight = 24.sp),
    bodyMedium = TextStyle(fontSize = 15.sp, lineHeight = 20.sp),
    labelLarge = TextStyle(fontWeight = FontWeight.Medium, fontSize = 15.sp, lineHeight = 20.sp),
)

/**
 * A reader typeface as a font family. Bundled faces load from the fonts
 * shared with iOS (Genesis/Resources/Fonts, this module's assets); New York,
 * Georgia and Baskerville read as the system serif, SF Pro as the system sans.
 */
fun ReaderFont.fontFamily(assets: AssetManager): FontFamily {
    val faces = faces ?: return if (isSans) FontFamily.SansSerif else FontFamily.Serif
    return FontFamily(
        Font("${faces.regular}.ttf", assets, FontWeight.Normal, FontStyle.Normal),
        Font("${faces.bold}.ttf", assets, FontWeight.SemiBold, FontStyle.Normal),
        Font("${faces.italic}.ttf", assets, FontWeight.Normal, FontStyle.Italic),
    )
}

private const val NATURAL_LINE_HEIGHT = 1.15

/** The family for a face, made once per face. */
@Composable
fun rememberFontFamily(font: ReaderFont): FontFamily {
    val assets = LocalContext.current.assets
    return remember(font) { font.fontFamily(assets) }
}

/**
 * The reader's body text from the person's settings: their face and size.
 * iOS multiplies the face's natural line height (about 1.15 × the size) by
 * the spacing, so the same 1.45 looks the same on both phones.
 */
@Composable
fun scriptureStyle(preferences: ReaderPreferences, premium: Boolean): TextStyle {
    val family = rememberFontFamily(preferences.font.available(premium))
    return TextStyle(
        fontFamily = family,
        fontSize = preferences.fontSize.sp,
        lineHeight = (preferences.lineSpacing * NATURAL_LINE_HEIGHT).em,
    )
}
