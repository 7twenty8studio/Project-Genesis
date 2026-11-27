package com.genesis.app.original

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.prayer.Segmented
import com.genesis.app.reader.ReaderViewModel
import com.genesis.app.settings.Entitlements
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.original.CommentaryPassage
import com.genesis.core.domain.original.GlossLanguage
import com.genesis.core.domain.original.OriginalLanguage
import com.genesis.core.domain.original.OriginalWord

/** Free accounts see this many words, then what Premium adds. */
private const val PREVIEW_WORDS = 2

/**
 * Word study for one verse, as VerseStudyView on iOS: the verse verbatim
 * from the Bible being read, the Hebrew or Greek words behind it (each
 * opening its Strong's entry) and Matthew Henry's commentary on the passage.
 * Premium; free accounts see two words.
 */
@Composable
fun VerseStudyScreen(verse: VerseId, viewModel: ReaderViewModel, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val colors = LocalReaderColors.current
    val app = context.applicationContext as VerselyApplication
    val preferences = rememberOriginalPreferences()
    val choice = preferences.glossChoice
    val stack = remember(verse) { mutableStateListOf<String>() }
    var commentaryTab by rememberSaveable { mutableStateOf(false) }
    var showsAbout by rememberSaveable { mutableStateOf(false) }
    val study by produceState<VerseStudy?>(null, verse, choice) {
        value = viewModel.verseStudy(context, verse) { GlossLanguage.code(choice, it.language) }
    }
    DisposableEffect(Unit) {
        app.pronouncer.prepare()
        onDispose { app.pronouncer.stop() }
    }
    BackHandler { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) else onDone() }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 4.dp, end = 8.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (stack.isNotEmpty()) TextButton(onClick = { stack.removeAt(stack.lastIndex) }) { Text("‹ " + stringResource(R.string.back), color = colors.accent) }
            val title = stack.lastOrNull() ?: study?.let { ReferenceParser.describe(verse.rawValue, verse.rawValue, it.language) } ?: ""
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                color = colors.text,
                modifier = Modifier.weight(1f).padding(start = if (stack.isEmpty()) 16.dp else 0.dp).semantics { heading() },
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 8.dp, bottom = 32.dp).navigationBarsPadding().widthIn(max = 680.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            val top = stack.lastOrNull()
            val loaded = study
            when {
                top != null -> LexiconContent(top, viewModel)
                loaded == null -> CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
                else -> {
                    Section {
                        Text(loaded.text, style = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Serif), color = colors.text)
                        Segmented(listOf(stringResource(R.string.original_words), stringResource(R.string.commentary)), selected = if (commentaryTab) 1 else 0) { commentaryTab = it == 1 }
                    }
                    if (commentaryTab) Commentary(loaded.commentary) { showsAbout = true } else Words(loaded.words) { stack.add(it) }
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        val englishApp = context.studyLanguage() == "en"
                        when {
                            loaded.glossesTranslated -> {
                                FooterText(stringResource(if (loaded.commentaryTranslated) R.string.grammar_in_english else R.string.commentary_grammar_english))
                                FooterText(stringResource(R.string.gloss_translated_note))
                                FooterText(stringResource(R.string.gloss_attribution))
                            }
                            loaded.language != "en" || !englishApp -> FooterText(
                                stringResource(
                                    when {
                                        loaded.commentaryTranslated -> R.string.verse_meanings_grammar_english
                                        loaded.lexiconTranslated -> R.string.commentary_meanings_english
                                        else -> R.string.definitions_commentary_english
                                    },
                                ),
                            )
                        }
                        FooterText(stringResource(R.string.word_study_attribution))
                    }
                }
            }
        }
    }
    if (showsAbout) CommentaryAboutSheet { showsAbout = false }
}

@Composable
private fun Words(words: List<OriginalWord>, onOpen: (String) -> Unit) {
    val colors = LocalReaderColors.current
    val unlocked = Entitlements.isPremium
    val language = words.firstOrNull()?.language ?: OriginalLanguage.HEBREW
    Section(
        languageName(language),
        footer = if (unlocked && words.isNotEmpty()) ({ FooterText(stringResource(R.string.original_words_footer)) }) else null,
    ) {
        if (words.isEmpty()) Text(stringResource(R.string.no_original_words), color = colors.secondaryText)
        val family = originalFont(language)
        for (word in if (unlocked) words else words.take(PREVIEW_WORDS)) {
            val strongs = word.strongs
            Row(
                Modifier.fillMaxWidth().then(if (unlocked && strongs != null) Modifier.clickable { onOpen(strongs) } else Modifier).padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(word.text, style = TextStyle(fontFamily = family, fontSize = 22.sp), color = colors.text)
                    Text(word.transliteration, style = MaterialTheme.typography.labelSmall.copy(fontStyle = FontStyle.Italic), color = colors.secondaryText)
                }
                Spacer(Modifier.padding(4.dp))
                Column(horizontalAlignment = Alignment.End, modifier = Modifier.weight(1f)) {
                    Text(word.shownGloss, style = MaterialTheme.typography.bodyMedium, color = colors.text, textAlign = TextAlign.End)
                    if (strongs != null) Text(strongs, style = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.Monospace), color = colors.accent)
                }
                if (unlocked && strongs != null) Text("  ›", color = colors.secondaryText)
            }
        }
        if (!unlocked && words.size > PREVIEW_WORDS) PremiumTeaser(stringResource(R.string.verse_study_premium_teaser))
    }
}

@Composable
private fun Commentary(passages: List<CommentaryPassage>, onAbout: () -> Unit) {
    val colors = LocalReaderColors.current
    when {
        passages.isEmpty() -> Section { Text(stringResource(R.string.no_commentary), color = colors.secondaryText) }
        !Entitlements.isPremium -> PremiumTeaser(stringResource(R.string.commentary_premium_teaser))
        else -> {
            Section {
                Text("ⓘ " + stringResource(R.string.about_this_commentary), color = colors.accent, modifier = Modifier.fillMaxWidth().clickable(onClick = onAbout).padding(vertical = 4.dp))
            }
            for (passage in passages) {
                val reference = ReferenceParser.describe(passage.start.rawValue, passage.end.rawValue, LocalContext.current.studyLanguage())
                Section(
                    passage.title ?: reference,
                    footer = {
                        FooterText(stringResource(R.string.matthew_henry_reference, reference))
                        FooterText(stringResource(R.string.matthew_henry_note))
                        if (passage.isTranslated) FooterText(stringResource(R.string.commentary_translated_note))
                        val credit = when (passage.quotationLanguage) {
                            "es" -> R.string.quotation_credit_es
                            "pt" -> R.string.quotation_credit_pt
                            else -> null
                        }
                        if (passage.quotations.isNotEmpty() && credit != null) FooterText(stringResource(credit))
                    },
                ) {
                    for (paragraph in passage.paragraphs) {
                        Text(
                            buildAnnotatedString {
                                append(paragraph)
                                for (range in passage.quotedRanges(paragraph)) addStyle(SpanStyle(fontStyle = FontStyle.Italic), range.first, range.last + 1)
                            },
                            style = MaterialTheme.typography.bodyLarge,
                            color = colors.text,
                        )
                    }
                }
            }
        }
    }
}
