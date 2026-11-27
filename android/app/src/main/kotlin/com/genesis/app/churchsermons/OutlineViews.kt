package com.genesis.app.churchsermons

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.app.prayer.Segmented
import com.genesis.app.reader.ChurchPassage
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.core.cloud.community.ChurchPassageBible
import com.genesis.core.cloud.community.SermonBlanks
import com.genesis.core.cloud.community.SermonBlock
import com.genesis.core.cloud.community.SermonReference
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.rememberFontFamily
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId

/** One block of a church's outline, its words exactly as published. */
@Composable
internal fun OutlineBlock(block: SermonBlock, handout: HandoutState?, language: String, shownBible: String, onPassage: (SermonReference) -> Unit) {
    val colors = LocalReaderColors.current
    val serif = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Serif, fontSize = 18.sp, lineHeight = 27.sp)
    when (block) {
        is SermonBlock.Heading -> HandoutText(
            block.text,
            (if (block.level == 1) MaterialTheme.typography.headlineMedium else MaterialTheme.typography.headlineSmall)
                .copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
            handout,
            Modifier.padding(top = 8.dp).semantics { heading() },
        )
        is SermonBlock.Paragraph -> HandoutText(block.text, serif, handout)
        is SermonBlock.Quote -> Row(Modifier.fillMaxWidth()) {
            Box(Modifier.width(3.dp).heightIn(min = 24.dp).background(colors.accent.copy(alpha = 0.5f)))
            Text(block.text, style = serif.copy(fontStyle = FontStyle.Italic), color = colors.text, modifier = Modifier.padding(start = 14.dp))
        }
        is SermonBlock.ListBlock -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            block.items.forEachIndexed { index, item ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(if (block.ordered) "${index + 1}." else "•", style = serif, color = colors.secondaryText)
                    HandoutText(item, serif, handout, Modifier.weight(1f))
                }
            }
        }
        is SermonBlock.Scripture -> ReferenceRow(block.reference, language, shownBible) { onPassage(block.reference) }
    }
}

/** The church's words with each "[[n]]" as a blank, and a box under them for each one. */
@Composable
internal fun HandoutText(text: String, style: TextStyle, handout: HandoutState?, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    if (handout == null) {
        Text(text, style = style, color = colors.text, modifier = modifier)
        return
    }
    val pieces = SermonBlanks.pieces(text, handout.known::contains)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            buildAnnotatedString {
                pieces.forEach { piece ->
                    when (piece) {
                        is SermonBlanks.Piece.Text -> append(piece.words)
                        is SermonBlanks.Piece.Blank -> {
                            val words = handout.value(piece.n)
                            withStyle(SpanStyle(color = colors.accent, textDecoration = TextDecoration.Underline)) {
                                append(words.ifEmpty { " ".repeat(8) })
                            }
                            withStyle(SpanStyle(color = colors.secondaryText, fontSize = 11.sp, fontWeight = FontWeight.Bold, baselineShift = BaselineShift.Superscript)) {
                                append("${piece.n}")
                            }
                        }
                    }
                }
            },
            style = style,
            color = colors.text,
        )
        pieces.filterIsInstance<SermonBlanks.Piece.Blank>().forEach { BlankField(it.n, handout) }
    }
}

/** One blank's box: the member's words, then right or not yet once checked, and the key's word while shown. */
@Composable
private fun BlankField(n: Int, handout: HandoutState) {
    val colors = LocalReaderColors.current
    val blank = handout.blank(n) ?: return
    val grade = handout.grade(n)
    val label = if (blank.open) stringResource(R.string.blank_number_open, n) else stringResource(R.string.blank_number, n)
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        Text("$n", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = colors.secondaryText, modifier = Modifier.padding(top = 10.dp).widthIn(min = 18.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            val value = handout.value(n)
            BasicTextField(
                value = value,
                onValueChange = { handout.set(n, it) },
                singleLine = !blank.open,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.text),
                cursorBrush = SolidColor(colors.accent),
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(colors.surface)
                    .border(if (grade == true) 2.dp else 1.5.dp, if (grade == true) colors.accent else colors.accent.copy(alpha = 0.35f), RoundedCornerShape(10.dp))
                    .padding(horizontal = 10.dp, vertical = 9.dp)
                    .semantics { contentDescription = label },
                decorationBox = { field ->
                    Box {
                        if (value.isEmpty()) {
                            Text(
                                blank.hint ?: if (blank.open) stringResource(R.string.your_own_words) else stringResource(R.string.blank_number, n),
                                style = MaterialTheme.typography.bodyLarge,
                                color = colors.secondaryText,
                            )
                        }
                        field()
                    }
                },
            )
            if (grade != null) {
                Text(
                    (if (grade) "✓ " else "◌ ") + stringResource(if (grade) R.string.correct else R.string.memorise_not_yet),
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Medium,
                    color = if (grade) colors.accent else colors.secondaryText,
                )
            }
            handout.shownAnswer(n)?.let { Text(stringResource(R.string.answer_is, it), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText) }
        }
    }
}

/** Under the handout: whether the answers are out, then Check, Show and Practice Again (once the key is there). */
@Composable
internal fun HandoutBar(handout: HandoutState) {
    val colors = LocalReaderColors.current
    val score = handout.score
    val status = when {
        handout.isPracticing -> stringResource(R.string.handout_practicing)
        score != null -> stringResource(R.string.handout_score, score.first, score.second)
        handout.canCheck -> stringResource(R.string.handout_ready)
        handout.answers == com.genesis.core.cloud.community.SermonAnswers.NEVER -> stringResource(R.string.handout_never)
        else -> stringResource(R.string.handout_waiting)
    }
    Column(
        Modifier.fillMaxWidth().padding(top = 24.dp).clip(RoundedCornerShape(16.dp)).background(colors.surface).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(stringResource(R.string.your_handout), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text, modifier = Modifier.semantics { heading() })
        Text(status, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
        if (handout.canCheck) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Pill(stringResource(R.string.check_answers), filled = true) { handout.check() }
                Pill(stringResource(if (handout.showing) R.string.hide_answers else R.string.show_answers)) { handout.toggleShowing() }
                if (handout.isPracticing) Pill(stringResource(R.string.back_to_my_answers)) { handout.endPractice() }
                else Pill(stringResource(R.string.practice_again)) { handout.startPractice() }
            }
        }
    }
}

@Composable
internal fun Pill(title: String, filled: Boolean = false, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = if (filled) colors.background else colors.accent,
        modifier = Modifier.clip(RoundedCornerShape(20.dp))
            .background(if (filled) colors.accent else colors.accent.copy(alpha = 0.12f))
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 9.dp),
    )
}

/** A Scripture reference: a verified one opens the passage; others stay as the pastor wrote them. */
@Composable
private fun ReferenceRow(reference: SermonReference, language: String, shown: String, onOpen: () -> Unit) {
    val colors = LocalReaderColors.current
    val range = reference.range
    if (range == null) {
        Text(
            buildAnnotatedString {
                withStyle(SpanStyle(fontWeight = FontWeight.Medium, color = colors.text)) { append(reference.raw) }
                reference.label?.let { withStyle(SpanStyle(color = colors.secondaryText)) { append(" · $it") } }
            },
            modifier = Modifier.padding(vertical = 4.dp),
        )
        return
    }
    val other = reference.label?.takeUnless { ChurchPassageBible.labelNames(it, shown) }
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(colors.surface).clickable(onClick = onOpen).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("📖", color = colors.accent)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(buildAnnotatedString {
                withStyle(SpanStyle(color = colors.accent, fontWeight = FontWeight.SemiBold)) { append(reference.raw) }
                withStyle(SpanStyle(color = colors.secondaryText)) { append(" · $shown") }
            })
            val named = ReferenceParser.describe(range.first, range.second, language)
            if (named != reference.raw) Text(named, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
            if (other != null) Text(stringResource(R.string.sermons_bible, other), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        }
        Text("›", style = MaterialTheme.typography.titleLarge, color = colors.secondaryText)
    }
}

/**
 * A passage from a church's sermon, verbatim from a Bible on this phone,
 * as ChurchPassageSheet on iOS: the person's Bible, the one picked for the
 * sermon, or the one the pastor quoted (KJV numbering, mapped to each Bible's own).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ChurchPassageSheet(
    reference: SermonReference,
    context: ChurchSermonContext,
    chosen: String?,
    onChoose: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalReaderColors.current
    val range = reference.range ?: return
    val start = VerseId(range.first)
    val end = VerseId(range.second)
    val base = ChurchPassageBible.options(context.currentBible, chosen, reference.translation) { it in context.bibles }
    val shownId = ChurchPassageBible.shown(base, chosen) ?: context.currentBible
    val passage by produceState<ChurchPassage?>(null, shownId, range) { value = context.passage(shownId, start, end) }
    // When no offered Bible has the passage, the KJV does.
    val options = if (passage != null && passage!!.verses.isEmpty() && "KJV" !in base && "KJV" in context.bibles) base + "KJV" else base
    val own by produceState<ChurchPassage?>(null, context.currentBible, range) { value = context.passage(context.currentBible, start, end) }
    val family = rememberFontFamily(LocalReaderPreferences.current.font.available(Entitlements.isPremium))

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false), containerColor = colors.background) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            val language = passage?.language ?: context.language
            Text(
                ReferenceParser.describe(range.first, range.second, language),
                style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
            )
            if (options.size > 1) {
                Segmented(options, options.indexOf(shownId).coerceAtLeast(0)) { onChoose(options[it]) }
                Text(stringResource(R.string.passage_bible_footer), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
            }
            val shown = passage
            if (shown != null) {
                if (shown.verses.isEmpty()) {
                    Text(stringResource(R.string.passage_not_in, shown.name), color = colors.secondaryText)
                }
                shown.verses.forEach { verse ->
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(ReferenceParser.describe(verse.id.rawValue, verse.id.rawValue, shown.language), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = colors.accent)
                        Text(verse.plainText, fontFamily = family, fontSize = 17.sp, lineHeight = 25.sp, color = colors.text)
                    }
                }
                Text(shown.name, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                reference.label?.takeUnless { ChurchPassageBible.labelNames(it, shown.bibleId) }?.let {
                    Text(stringResource(R.string.sermons_bible, it), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                }
            }
            Spacer(Modifier.size(4.dp))
            own?.verses?.firstOrNull()?.let { first ->
                TextButton(onClick = { context.onRead(first.id) }) { Text(stringResource(R.string.open_in_reader), color = colors.accent, fontWeight = FontWeight.SemiBold) }
            }
        }
    }
}

