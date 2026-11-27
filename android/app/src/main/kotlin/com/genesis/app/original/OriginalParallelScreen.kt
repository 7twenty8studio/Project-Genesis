package com.genesis.app.original

import android.content.Context
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.edit
import com.genesis.app.R
import com.genesis.app.reader.ReaderViewModel
import com.genesis.app.settings.Entitlements
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.original.GlossLanguage
import com.genesis.core.domain.original.GlossLanguageChoice
import com.genesis.core.domain.original.OriginalLanguage
import com.genesis.core.domain.original.OriginalParallel
import com.genesis.core.domain.original.OriginalParallelRow
import com.genesis.core.domain.original.OriginalText
import com.genesis.core.domain.original.OriginalWord

/** The reader's Original settings, kept as on iOS (reader.original.*). */
internal class OriginalPreferences(context: Context) {
    private val prefs = context.getSharedPreferences("reader", Context.MODE_PRIVATE)
    val interlinear = stored("reader.original.interlinear")
    val originalOnly = stored("reader.original.only")
    var glossChoice by mutableStateOf(GlossLanguageChoice.of(prefs.getString(GlossLanguage.STORAGE_KEY, null)))
        private set

    fun choose(choice: GlossLanguageChoice) {
        glossChoice = choice
        prefs.edit { putString(GlossLanguage.STORAGE_KEY, choice.raw) }
    }

    fun toggle(state: MutableState<Boolean>, key: String) {
        state.value = !state.value
        prefs.edit { putBoolean(key, state.value) }
    }

    private fun stored(key: String) = mutableStateOf(prefs.getBoolean(key, false))
}

@Composable
internal fun rememberOriginalPreferences(): OriginalPreferences {
    val context = LocalContext.current
    return remember { OriginalPreferences(context.applicationContext) }
}

/**
 * The Bible being read beside the text it was translated from, verse by
 * verse, as OriginalParallelView on iOS: the Hebrew (Leningrad Codex) or the
 * Greek in the edition that Bible follows, every word verbatim and tappable.
 * Premium; free accounts see the first two verses of each chapter.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OriginalParallelScreen(
    viewModel: ReaderViewModel,
    chapter: ChapterId,
    bibleId: String,
    fontSize: Double,
    onNext: (() -> Unit)?,
    onWord: (OriginalWord) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val colors = LocalReaderColors.current
    val preferences = rememberOriginalPreferences()
    val unlocked = Entitlements.isPremium
    val choice = preferences.glossChoice
    val loaded by produceState<OriginalChapter?>(null, chapter, bibleId, unlocked, choice) {
        value = null
        value = viewModel.originalChapter(context, chapter, { GlossLanguage.code(choice, it.language) }, unlocked)
    }
    val language = OriginalLanguage.forBook(chapter.book)
    val data = loaded
    if (data == null || data.chapter != chapter) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = colors.accent) }
        return
    }
    val interlinear by preferences.interlinear
    val originalOnly by preferences.originalOnly
    val listState = rememberLazyListState()
    LaunchedEffect(chapter) { listState.scrollToItem(0) }

    BoxWithConstraints(modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        val sideBySide = maxWidth >= 600.dp
        LazyColumn(
            state = listState,
            modifier = Modifier.widthIn(max = if (sideBySide) 1100.dp else 680.dp).fillMaxSize(),
            contentPadding = PaddingValues(horizontal = if (sideBySide) 32.dp else 22.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(if (sideBySide) 16.dp else 20.dp),
        ) {
            item {
                OriginalHeader(
                    data = data,
                    language = language,
                    sideBySide = sideBySide,
                    marksEditions = data.rows.any { row -> row.words.any { it.isNotInComparison } },
                    glossCode = GlossLanguage.code(choice, data.translation.language),
                    preferences = preferences,
                )
            }
            itemsIndexed(data.rows, key = { _, row -> row.verse.rawValue }) { index, row ->
                Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    OriginalVerseRow(row, data.translation.language, language, sideBySide, interlinear, originalOnly, fontSize, onWord)
                    if (!unlocked && index == OriginalParallel.PREVIEW_VERSES - 1) PremiumTeaser(stringResource(R.string.original_premium_teaser))
                }
            }
            item {
                Column(Modifier.fillMaxWidth().padding(top = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    val next = chapter.next
                    if (next != null && onNext != null) {
                        TextButton(onClick = onNext) { Text(next.description(data.translation.language) + "  ›", color = colors.accent, fontWeight = FontWeight.SemiBold) }
                    }
                    Text(stringResource(R.string.word_study_attribution), style = MaterialTheme.typography.labelSmall, color = colors.secondaryText, textAlign = TextAlign.Center)
                }
            }
        }
    }
}

@Composable
private fun OriginalHeader(
    data: OriginalChapter,
    language: OriginalLanguage,
    sideBySide: Boolean,
    marksEditions: Boolean,
    glossCode: String,
    preferences: OriginalPreferences,
) {
    val colors = LocalReaderColors.current
    var showsSource by rememberSaveable { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    val source = sourceHeading(language, data.greek, data.translation.abbreviation)
    val name = languageName(language)
    val title = data.chapter.description(data.translation.language)
    Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(bottom = 6.dp)) {
        when {
            preferences.originalOnly.value -> Column {
                Text(title, style = MaterialTheme.typography.titleLarge, color = colors.text, modifier = Modifier.semantics { heading() })
                Text("$name · $source", style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
            }
            sideBySide -> Row {
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.titleLarge, color = colors.text, modifier = Modifier.semantics { heading() })
                    Text(data.translation.name, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                }
                Column(Modifier.weight(1f).padding(start = 25.dp)) {
                    Text(name, style = MaterialTheme.typography.titleLarge, color = colors.text)
                    Text(source, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                }
            }
            else -> Column {
                Text(stringResource(R.string.bible_and_language, data.translation.abbreviation, name), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = colors.secondaryText)
                Text(source, style = MaterialTheme.typography.labelSmall, color = colors.secondaryText)
            }
        }
        @OptIn(ExperimentalLayoutApi::class)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Toggle(stringResource(R.string.interlinear), preferences.interlinear.value) { preferences.toggle(preferences.interlinear, "reader.original.interlinear") }
            Toggle(stringResource(if (language == OriginalLanguage.GREEK) R.string.greek_only else R.string.hebrew_only), preferences.originalOnly.value) {
                preferences.toggle(preferences.originalOnly, "reader.original.only")
            }
            Box {
                Chip(
                    when (glossCode) {
                        "es" -> "Español"
                        "pt" -> "Português"
                        else -> "English"
                    },
                ) { menu = true }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    Text(stringResource(R.string.word_meanings), style = MaterialTheme.typography.labelLarge, color = colors.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                    val options = listOf(
                        GlossLanguageChoice.BIBLE to stringResource(R.string.same_as_the_bible, data.translation.abbreviation),
                        GlossLanguageChoice.ENGLISH to "English",
                        GlossLanguageChoice.SPANISH to "Español",
                        GlossLanguageChoice.PORTUGUESE to "Português",
                    )
                    for ((option, label) in options) {
                        DropdownMenuItem(
                            text = { Text((if (option == preferences.glossChoice) "✓ " else "") + label) },
                            onClick = {
                                menu = false
                                preferences.choose(option)
                            },
                        )
                    }
                }
            }
            Chip("ⓘ " + stringResource(if (language == OriginalLanguage.GREEK) R.string.about_the_greek else R.string.about_the_hebrew)) { showsSource = true }
        }
        if (marksEditions) {
            Text(data.greek.edition.dottedWords(), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        }
        val englishNote = data.translation.language != "en" || LocalContext.current.studyLanguage() != "en"
        if (data.glossesTranslated || englishNote) {
            Text(
                stringResource(if (data.glossesTranslated) R.string.gloss_translated_note else R.string.word_meanings_grammar_english),
                style = MaterialTheme.typography.bodySmall,
                color = colors.secondaryText,
            )
        }
    }
    if (showsSource) OriginalSourceSheet(language, data.greek, data.translation.abbreviation, data.glossesTranslated) { showsSource = false }
}

@Composable
private fun Toggle(title: String, on: Boolean, onClick: () -> Unit) = Chip((if (on) "● " else "○ ") + title, on, onClick)

@Composable
private fun Chip(title: String, on: Boolean = false, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = if (on) colors.accent else colors.secondaryText,
        modifier = Modifier.clip(RoundedCornerShape(10.dp)).border(1.dp, if (on) colors.accent else colors.separator, RoundedCornerShape(10.dp))
            .clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 8.dp),
    )
}

/** One verse beside its Hebrew or Greek: side by side on wide screens, beneath on a phone. */
@Composable
private fun OriginalVerseRow(
    row: OriginalParallelRow,
    bibleLanguage: String,
    language: OriginalLanguage,
    sideBySide: Boolean,
    interlinear: Boolean,
    originalOnly: Boolean,
    fontSize: Double,
    onWord: (OriginalWord) -> Unit,
) {
    val colors = LocalReaderColors.current
    val covered = row.covers?.let { ReferenceParser.describe(row.verse.withVerse(it.first), row.verse.withVerse(it.last), bibleLanguage) }
    val original: @Composable () -> Unit = {
        if (row.words.isNotEmpty()) OriginalVerse(row.words, language, covered, interlinear, fontSize, onWord)
    }
    when {
        originalOnly -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("${row.number}", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.accent)
            Box(Modifier.weight(1f)) { original() }
        }
        sideBySide -> Row(Modifier.fillMaxWidth()) {
            Box(Modifier.weight(1f).padding(end = 24.dp)) { VerseWithNumber(row, fontSize) }
            VerticalDivider(color = colors.separator)
            Box(Modifier.weight(1f).padding(start = 24.dp)) { original() }
        }
        else -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            VerseWithNumber(row, fontSize)
            original()
        }
    }
}

private fun com.genesis.core.domain.bible.VerseId.withVerse(verse: Int) = com.genesis.core.domain.bible.VerseId(book, chapter, verse).rawValue

@Composable
private fun VerseWithNumber(row: OriginalParallelRow, fontSize: Double) {
    val colors = LocalReaderColors.current
    val scripture = com.genesis.core.design.scriptureStyle(com.genesis.app.settings.LocalReaderPreferences.current, Entitlements.isPremium)
    Text(
        buildAnnotatedString {
            withStyle(SpanStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.accent, baselineShift = BaselineShift(0.4f))) { append("${row.number} ") }
            append(row.text)
        },
        style = scripture.copy(fontSize = fontSize.sp),
        color = colors.text,
    )
}

/**
 * A verse's Hebrew or Greek, every word verbatim and tappable: running text
 * (joined as `OriginalText` describes) or interlinear. Hebrew reads right to
 * left; Greek words the compared edition lacks are underlined.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun OriginalVerse(words: List<OriginalWord>, language: OriginalLanguage, reference: String?, interlinear: Boolean, fontSize: Double, onWord: (OriginalWord) -> Unit) {
    val colors = LocalReaderColors.current
    val family = originalFont(language)
    val size = originalReadingSize(fontSize, language)
    val rtl = language.isRightToLeft
    Column(Modifier.fillMaxWidth(), horizontalAlignment = if (rtl) Alignment.End else Alignment.Start, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (reference != null) Text(reference, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = colors.secondaryText)
        if (interlinear) {
            CompositionLocalProvider(LocalLayoutDirection provides if (rtl) LayoutDirection.Rtl else LayoutDirection.Ltr) {
                FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    for (word in words) {
                        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                            Column(
                                Modifier.widthIn(max = 150.dp).clip(RoundedCornerShape(6.dp)).clickable { onWord(word) }.padding(vertical = 2.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(2.dp),
                            ) {
                                Text(
                                    OriginalText.display(word.text),
                                    style = TextStyle(fontFamily = family, fontSize = size.sp, textDecoration = if (word.isNotInComparison) TextDecoration.Underline else null),
                                    color = colors.text,
                                )
                                Text(word.transliteration, style = MaterialTheme.typography.labelSmall.copy(fontStyle = FontStyle.Italic), color = colors.secondaryText, textAlign = TextAlign.Center)
                                Text(word.shownGloss, style = MaterialTheme.typography.labelSmall, color = colors.accent, textAlign = TextAlign.Center)
                            }
                        }
                    }
                }
            }
        } else {
            val text = remember(words, colors) { runningText(words, colors.accent, onWord) }
            Text(
                text,
                style = TextStyle(
                    fontFamily = family,
                    fontSize = size.sp,
                    lineHeight = (size * 1.6).sp,
                    textAlign = if (rtl) TextAlign.Right else TextAlign.Left,
                    textDirection = if (rtl) TextDirection.Rtl else TextDirection.Ltr,
                ),
                color = colors.text,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

private fun runningText(words: List<OriginalWord>, accent: androidx.compose.ui.graphics.Color, onWord: (OriginalWord) -> Unit): AnnotatedString = buildAnnotatedString {
    OriginalText.segments(words.map { it.text }).forEachIndexed { index, segment ->
        val word = words[index]
        val style = if (word.isNotInComparison) SpanStyle(textDecoration = TextDecoration.Underline, color = accent) else SpanStyle()
        withLink(LinkAnnotation.Clickable("word-$index", TextLinkStyles(style)) { onWord(word) }) { append(segment.text) }
        append(segment.separator)
    }
}
