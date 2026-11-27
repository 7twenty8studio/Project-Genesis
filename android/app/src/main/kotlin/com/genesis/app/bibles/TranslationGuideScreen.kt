package com.genesis.app.bibles

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.settings.Footer
import com.genesis.app.settings.Group
import com.genesis.app.settings.Header
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ReadingLevel
import com.genesis.core.domain.bible.ReadingPurpose
import com.genesis.core.domain.bible.TranslationApproach
import com.genesis.core.domain.bible.TranslationProfile

/** A Bible as the guide shows it. */
data class GuideBible(val id: String, val name: String, val abbreviation: String, val profile: TranslationProfile)

/**
 * "Which Bible is right for me?", as TranslationGuideView.swift: how
 * translations differ, where each Bible in a language sits, and a
 * suggestion for each way of reading. `bibles` are most read first.
 */
@Composable
fun TranslationGuideScreen(languageName: String, bibles: List<GuideBible>, onDone: () -> Unit) {
    val colors = LocalReaderColors.current
    BackHandler(onBack = onDone)
    Column(Modifier.fillMaxSize().background(colors.background).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.guide_title),
                style = MaterialTheme.typography.titleMedium,
                color = colors.text,
                modifier = Modifier.weight(1f).padding(start = 12.dp).semantics { heading() },
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp).widthIn(max = 680.dp)) {
            Group { Text(stringResource(R.string.guide_intro), color = colors.text, modifier = Modifier.padding(16.dp)) }

            if (bibles.size == 1) {
                Header(stringResource(R.string.guide_suggestions_in, languageName))
                Group { Text(stringResource(R.string.guide_only_bible, languageName, bibles.first().name), color = colors.text, modifier = Modifier.padding(16.dp)) }
            } else if (bibles.size > 1) {
                Header(stringResource(R.string.guide_suggestions_in, languageName))
                Group {
                    val pairs = bibles.map { it to it.profile }
                    var first = true
                    for (purpose in ReadingPurpose.entries) {
                        val bible = TranslationProfile.suggestion(purpose, pairs) ?: continue
                        if (!first) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                        first = false
                        val reason = listOfNotNull(bible.profile.approach?.let { stringResource(it.title) }, bible.profile.readingLevel?.let { stringResource(it.title) }).joinToString(" · ")
                        Explanation(purpose.symbol, stringResource(purpose.title), bible.name, reason.ifEmpty { null }, labelFirst = true)
                    }
                }
            }

            Header(stringResource(R.string.guide_how_translated))
            Group {
                Spectrum(bibles)
                for (approach in TranslationApproach.entries) {
                    HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                    Explanation(approach.symbol, stringResource(approach.title), stringResource(approach.detail))
                }
            }

            Header(stringResource(R.string.guide_how_reads))
            Group {
                ReadingLevel.entries.forEachIndexed { index, level ->
                    if (index > 0) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                    Explanation("Aa", stringResource(level.title), stringResource(level.detail))
                }
            }

            Header(stringResource(R.string.guide_rights_audio))
            Group {
                Explanation("✓", stringResource(R.string.guide_public_domain), stringResource(R.string.guide_public_domain_detail))
                HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                Explanation("📄", stringResource(R.string.guide_licensed), stringResource(R.string.guide_licensed_detail))
                HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                Explanation("〰", stringResource(R.string.guide_audio), stringResource(R.string.guide_audio_detail))
            }
            Footer("")
        }
    }
}

/** The three approaches left to right, with this language's Bibles under each. */
@Composable
private fun Spectrum(bibles: List<GuideBible>) {
    val colors = LocalReaderColors.current
    Column(Modifier.fillMaxWidth().padding(16.dp).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (approach in TranslationApproach.entries) {
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(stringResource(approach.title), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.text, textAlign = TextAlign.Center)
                    for (bible in bibles.filter { it.profile.approach == approach }) {
                        Text(
                            bible.abbreviation,
                            style = MaterialTheme.typography.labelMedium.copy(fontFamily = FontFamily.Serif),
                            fontWeight = FontWeight.Bold,
                            color = colors.accent,
                            modifier = Modifier.background(colors.accent.copy(alpha = 0.14f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 3.dp),
                        )
                    }
                }
            }
        }
        Text("←———————————→", color = colors.separator, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        Row {
            Text(stringResource(R.string.guide_closer_original), style = MaterialTheme.typography.labelSmall, color = colors.secondaryText, modifier = Modifier.weight(1f))
            Text(stringResource(R.string.guide_closer_everyday), style = MaterialTheme.typography.labelSmall, color = colors.secondaryText, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun Explanation(symbol: String, title: String, detail: String, extra: String? = null, labelFirst: Boolean = false) {
    val colors = LocalReaderColors.current
    Row(Modifier.fillMaxWidth().padding(16.dp).semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(symbol, color = colors.accent, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.width(24.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (labelFirst) {
                Text(title, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.secondaryText)
                Text(detail, style = MaterialTheme.typography.bodyLarge, color = colors.text)
            } else {
                Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = colors.text)
                Text(detail, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
            }
            if (extra != null) Text(extra, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        }
    }
}

private val ReadingPurpose.title: Int
    get() = when (this) {
        ReadingPurpose.STUDY -> R.string.purpose_study
        ReadingPurpose.EVERYDAY -> R.string.purpose_everyday
        ReadingPurpose.CLASSIC -> R.string.purpose_classic
    }

private val ReadingPurpose.symbol: String
    get() = when (this) {
        ReadingPurpose.STUDY -> "🔍"
        ReadingPurpose.EVERYDAY -> "📖"
        ReadingPurpose.CLASSIC -> "♫"
    }

internal val TranslationApproach.title: Int
    get() = when (this) {
        TranslationApproach.WORD_FOR_WORD -> R.string.approach_word_for_word
        TranslationApproach.BALANCED -> R.string.approach_balanced
        TranslationApproach.THOUGHT_FOR_THOUGHT -> R.string.approach_thought_for_thought
    }

private val TranslationApproach.detail: Int
    get() = when (this) {
        TranslationApproach.WORD_FOR_WORD -> R.string.approach_word_for_word_detail
        TranslationApproach.BALANCED -> R.string.approach_balanced_detail
        TranslationApproach.THOUGHT_FOR_THOUGHT -> R.string.approach_thought_for_thought_detail
    }

private val TranslationApproach.symbol: String
    get() = when (this) {
        TranslationApproach.WORD_FOR_WORD -> "⟷"
        TranslationApproach.BALANCED -> "⚖"
        TranslationApproach.THOUGHT_FOR_THOUGHT -> "💬"
    }

internal val ReadingLevel.title: Int
    get() = when (this) {
        ReadingLevel.TRADITIONAL -> R.string.level_traditional
        ReadingLevel.FORMAL -> R.string.level_formal
        ReadingLevel.EVERYDAY -> R.string.level_everyday
    }

private val ReadingLevel.detail: Int
    get() = when (this) {
        ReadingLevel.TRADITIONAL -> R.string.level_traditional_detail
        ReadingLevel.FORMAL -> R.string.level_formal_detail
        ReadingLevel.EVERYDAY -> R.string.level_everyday_detail
    }
