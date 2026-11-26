package com.genesis.core.design

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * Screens use the system sans; Scripture uses a serif, as the iOS reader's
 * New York. The bundled Premium fonts (Crimson Pro, Source Serif 4,
 * Spectral) and EB Garamond / Noto Serif Hebrew arrive with the reader
 * settings in phase 2.
 */
val ScriptureFont: FontFamily = FontFamily.Serif

val VerselyTypography = Typography(
    titleLarge = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 22.sp, lineHeight = 28.sp),
    titleMedium = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 22.sp),
    bodyLarge = TextStyle(fontSize = 17.sp, lineHeight = 24.sp),
    bodyMedium = TextStyle(fontSize = 15.sp, lineHeight = 20.sp),
    labelLarge = TextStyle(fontWeight = FontWeight.Medium, fontSize = 15.sp, lineHeight = 20.sp),
)

/** The reader's body text: serif, roomy line height. */
val ScriptureText = TextStyle(fontFamily = ScriptureFont, fontSize = 19.sp, lineHeight = 31.sp)
