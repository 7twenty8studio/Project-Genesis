package com.genesis.app.original

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.reader.ReaderViewModel
import com.genesis.app.settings.Entitlements
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.original.GreekEdition
import com.genesis.core.domain.original.Morphology
import com.genesis.core.domain.original.OriginalLanguage
import com.genesis.core.domain.original.OriginalSource
import com.genesis.core.domain.original.OriginalText
import com.genesis.core.domain.original.OriginalWord

/** A titled group of rows, as a List section on iOS. */
@Composable
internal fun Section(title: String? = null, footer: (@Composable ColumnScope.() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val colors = LocalReaderColors.current
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (title != null) Text(title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = colors.secondaryText, modifier = Modifier.padding(start = 4.dp).semantics { heading() })
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(colors.surface).padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            content = content,
        )
        if (footer != null) Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp), content = footer)
    }
}

@Composable
internal fun FooterText(text: String) = Text(text, style = MaterialTheme.typography.bodySmall, color = LocalReaderColors.current.secondaryText)

/** About the text in the Original parallel's second column. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun OriginalSourceSheet(language: OriginalLanguage, greek: OriginalSource.Greek, abbreviation: String, glossesTranslated: Boolean, onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = colors.background) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Text(sourceHeading(language, greek, abbreviation), style = MaterialTheme.typography.titleMedium, color = colors.text, modifier = Modifier.semantics { heading() })
            val edition = greek.edition
            Section(if (language == OriginalLanguage.GREEK) edition.fullName() else stringResource(R.string.leningrad_title)) {
                val lines = if (language != OriginalLanguage.GREEK) {
                    listOf(stringResource(R.string.leningrad_about), stringResource(R.string.leningrad_reading))
                } else buildList {
                    add(edition.about())
                    add(
                        when {
                            !greek.isKnownSource -> stringResource(R.string.greek_unknown_source, abbreviation)
                            greek.isExact -> stringResource(R.string.greek_exact_source, abbreviation)
                            else -> stringResource(R.string.greek_closest_source, abbreviation)
                        },
                    )
                    add(stringResource(if (edition == GreekEdition.NESTLE_ALAND) R.string.edition_spelling_na else R.string.edition_spelling_other))
                    if (edition != GreekEdition.NESTLE_ALAND) add(stringResource(R.string.greek_word_order))
                    add(stringResource(R.string.greek_punctuation))
                }
                lines.forEach { Text(it, style = MaterialTheme.typography.bodyLarge, color = colors.text) }
            }
            Section(stringResource(R.string.source)) {
                Text(stringResource(if (language == OriginalLanguage.GREEK) R.string.greek_credit else R.string.hebrew_credit), style = MaterialTheme.typography.bodyMedium, color = colors.text)
                if (glossesTranslated) Text(stringResource(R.string.gloss_attribution), style = MaterialTheme.typography.bodyMedium, color = colors.text)
            }
        }
    }
}

/**
 * One Hebrew or Greek word tapped in the Original parallel: the word
 * verbatim, its transliteration, Strong's number and gloss here, then
 * (Premium) its dictionary form, grammar, how editions differ, definition
 * and every verse that uses it. "Used n times" opens the lexicon entry in
 * the same sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OriginalWordSheet(word: OriginalWord, viewModel: ReaderViewModel, onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    val app = LocalContext.current.applicationContext as VerselyApplication
    DisposableEffect(Unit) {
        app.pronouncer.prepare()
        onDispose { app.pronouncer.stop() }
    }
    val stack = remember(word) { mutableStateListOf<String>() }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = colors.background) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (stack.isNotEmpty()) TextButton(onClick = { stack.removeAt(stack.lastIndex) }) { Text("‹ " + stringResource(R.string.back), color = colors.accent) }
                Text(
                    if (stack.isEmpty()) wordLanguageName(word) else stack.last(),
                    style = MaterialTheme.typography.titleMedium,
                    color = colors.text,
                    modifier = Modifier.weight(1f).padding(start = if (stack.isEmpty()) 4.dp else 0.dp).semantics { heading() },
                )
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
            }
            val top = stack.lastOrNull()
            if (top != null) LexiconContent(top, viewModel) else WordContent(word) { stack.add(it) }
        }
    }
}

@Composable
private fun wordLanguageName(word: OriginalWord): String {
    val aramaic = remember(word) { Morphology(word.morphology, word.language).isAramaic }
    return if (aramaic) stringResource(R.string.aramaic) else languageName(word.language)
}

@Composable
private fun ColumnScope.WordContent(word: OriginalWord, onUsage: (String) -> Unit) {
    val context = LocalContext.current
    val colors = LocalReaderColors.current
    val unlocked = Entitlements.isPremium
    val details by produceState<WordDetails?>(null, word) { value = context.wordDetails(word) }
    val morphology = remember(word) { Morphology(word.morphology, word.language) }
    val hebrew = word.language == OriginalLanguage.HEBREW
    Section(footer = { PronunciationNote(word.language) }) {
        OriginalHeadword(OriginalText.display(word.text), word.transliteration, word.language, if (hebrew) 44.0 else 38.0)
        Labeled(stringResource(R.string.in_this_verse), word.shownGloss)
        if (word.awaitsReview) FooterText(stringResource(R.string.gloss_awaiting_review))
        word.englishGloss?.let { Labeled(stringResource(R.string.in_english), it) }
        word.strongs?.let { Labeled(stringResource(R.string.strongs_number), it) }
    }
    if (!unlocked) {
        PremiumTeaser(stringResource(R.string.word_sheet_premium_teaser))
    } else {
        val loaded = details
        val entry = loaded?.entry
        if (entry != null) {
            Section(stringResource(R.string.dictionary_form)) {
                OriginalHeadword(entry.lemma, entry.transliteration, word.language, 28.0)
                if (entry.gloss.isNotEmpty()) Labeled(stringResource(R.string.meaning), entry.gloss)
            }
        }
        val grammar = morphology.details
        if (grammar.isNotEmpty()) {
            Section(stringResource(R.string.grammar)) {
                for (detail in grammar) {
                    val (label, value) = detail.line()
                    Labeled(label, value)
                }
            }
        }
        val compared = word.edition?.comparison
        if (word.isNotInComparison && compared != null) {
            Section(stringResource(R.string.greek_editions)) {
                Text(loaded?.alternative?.let { compared.readsInstead(it) } ?: compared.lacksWord(), style = MaterialTheme.typography.bodyLarge, color = colors.text)
            }
        }
        if (entry != null && entry.definition.isNotEmpty()) {
            Section(stringResource(R.string.definition), footer = if (entry.isTranslated) ({ FooterText(stringResource(R.string.lexicon_translated_note)) }) else null) {
                Text(entry.definition, style = MaterialTheme.typography.bodyLarge, color = colors.text)
            }
        }
        val strongs = word.strongs
        val count = loaded?.count ?: 0
        if (strongs != null && count > 0) {
            Section {
                Text(
                    if (count == 1) stringResource(R.string.used_once) else stringResource(R.string.used_times, count),
                    style = MaterialTheme.typography.bodyLarge,
                    color = colors.accent,
                    modifier = Modifier.fillMaxWidth().clickable { onUsage(strongs) },
                )
            }
        }
        if (loaded == null) CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (word.englishGloss != null) {
            FooterText(stringResource(R.string.grammar_in_english))
            FooterText(stringResource(R.string.gloss_translated_note))
            FooterText(stringResource(R.string.gloss_attribution))
        } else if (context.studyLanguage() != "en") {
            FooterText(stringResource(R.string.verse_meaning_grammar_english))
        }
        FooterText(stringResource(R.string.word_study_attribution))
    }
}

/** A word large, with its transliteration and the speaker beside it (Hebrew on the right). */
@Composable
private fun OriginalHeadword(text: String, transliteration: String, language: OriginalLanguage, size: Double) {
    val colors = LocalReaderColors.current
    val hebrew = language == OriginalLanguage.HEBREW
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (hebrew) PronounceButton(text, language)
        Column(Modifier.weight(1f), horizontalAlignment = if (hebrew) Alignment.End else Alignment.Start, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(text, style = TextStyle(fontFamily = originalFont(language), fontSize = size.sp), color = colors.text)
            Text(transliteration, style = MaterialTheme.typography.titleMedium.copy(fontStyle = FontStyle.Italic, fontWeight = FontWeight.Normal), color = colors.secondaryText)
        }
        if (!hebrew) PronounceButton(text, language)
    }
}

/** One Strong's entry: the word, its definition, how often it's used and the verses that use it. */
@Composable
internal fun ColumnScope.LexiconContent(strongs: String, viewModel: ReaderViewModel) {
    val context = LocalContext.current
    val colors = LocalReaderColors.current
    val page by produceState<LexiconPage?>(null, strongs) { value = viewModel.lexiconPage(context, strongs) }
    var loaded by androidx.compose.runtime.remember(strongs) { androidx.compose.runtime.mutableStateOf(false) }
    androidx.compose.runtime.LaunchedEffect(page) { if (page != null) loaded = true }
    androidx.compose.runtime.LaunchedEffect(strongs) { kotlinx.coroutines.delay(4_000); loaded = true }
    val current = page
    if (current == null) {
        if (loaded) Text(stringResource(R.string.not_in_dictionary), color = colors.secondaryText)
        else CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
        return
    }
    val entry = current.entry
    Section(footer = { PronunciationNote(entry.language) }) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(entry.lemma, style = TextStyle(fontFamily = originalFont(entry.language), fontSize = 34.sp), color = colors.text)
                Text(entry.transliteration, style = MaterialTheme.typography.bodyMedium.copy(fontStyle = FontStyle.Italic), color = colors.secondaryText)
                Text(entry.gloss, style = MaterialTheme.typography.titleMedium, color = colors.accent)
            }
            PronounceButton(entry.lemma, entry.language)
        }
        when {
            current.count == 1 -> Text(stringResource(R.string.used_once), color = colors.secondaryText)
            current.count > 1 -> Text(stringResource(R.string.used_times, current.count), color = colors.secondaryText)
        }
    }
    if (entry.definition.isNotEmpty()) {
        Section(stringResource(R.string.definition), footer = if (entry.isTranslated) ({ FooterText(stringResource(R.string.lexicon_translated_note)) }) else null) {
            Text(entry.definition, style = MaterialTheme.typography.bodyLarge, color = colors.text)
        }
    }
    if (entry.derivation.isNotEmpty() || entry.usage.isNotEmpty()) {
        Section(stringResource(R.string.from_strongs)) {
            if (entry.derivation.isNotEmpty()) Labeled(stringResource(R.string.origin), entry.derivation)
            if (entry.usage.isNotEmpty()) Labeled(stringResource(R.string.in_the_kjv), entry.usage)
        }
    }
    com.genesis.app.studylibrary.StudyLexiconSections(strongs)
    if (current.verses.isNotEmpty()) {
        Section(
            stringResource(R.string.where_its_used),
            footer = if (current.count > current.verses.size) ({ FooterText(stringResource(R.string.first_verses, current.verses.size)) }) else null,
        ) {
            for (verse in current.verses) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.padding(vertical = 4.dp)) {
                    Text(ReferenceParser.describe(verse.id.rawValue, verse.id.rawValue, current.language), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.accent)
                    Text(verse.displayText, style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Serif), color = colors.text)
                }
            }
        }
    }
}

/** About Matthew Henry's Concise Commentary: who, when, which edition, and that it isn't Scripture. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CommentaryAboutSheet(onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.background) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(stringResource(R.string.about_this_commentary), style = MaterialTheme.typography.titleMedium, color = colors.text, modifier = Modifier.semantics { heading() })
            Section(stringResource(R.string.matthew_henry_years)) {
                val s = listOf(R.string.henry_about_1, R.string.henry_about_2, R.string.henry_about_3, R.string.henry_about_4, R.string.henry_about_5, R.string.henry_about_6).map { stringResource(it) }
                for (pair in s.chunked(2)) Text(pair.joinToString(" "), style = MaterialTheme.typography.bodyLarge, color = colors.text, textAlign = TextAlign.Start)
            }
        }
    }
}
