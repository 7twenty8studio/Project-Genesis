package com.genesis.app.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.core.bible.Chapter
import com.genesis.core.bible.InstalledBible
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.rememberFontFamily
import com.genesis.core.domain.reader.ParallelRow

/**
 * Two Bibles side by side, verse by verse, as ParallelChapterView on iOS:
 * rows line up by verse number, so where the two number a chapter
 * differently a verse simply has no partner on one side. Wide screens give
 * each Bible half the width; on a phone the second follows each verse, a
 * little smaller. Verse text is verbatim.
 */
@Composable
internal fun ParallelChapterScreen(
    viewModel: ReaderViewModel,
    primary: Chapter,
    secondaryBible: InstalledBible,
    playingVerse: Int?,
    onNext: (() -> Unit)?,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalReaderColors.current
    val preferences = LocalReaderPreferences.current
    val family = rememberFontFamily(preferences.font.available(Entitlements.isPremium))
    val secondary by produceState<Chapter?>(null, primary.id, secondaryBible) {
        value = viewModel.parallelChapter(secondaryBible, primary.id)
    }
    val other = secondary
    if (other == null) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = colors.accent) }
        return
    }
    val rows = remember(primary, other) {
        ParallelRow.merge(primary.verses.map { it.number to it.plainText }, other.verses.map { it.number to it.plainText })
    }
    val textSize = preferences.fontSize.toFloat()
    val lineHeight = textSize * 1.35f * preferences.lineSpacing.toFloat()
    fun style(emphasis: Boolean) = TextStyle(
        fontFamily = family,
        fontSize = (if (emphasis) textSize else textSize * 0.88f).sp,
        lineHeight = (if (emphasis) lineHeight else lineHeight * 0.88f).sp,
        color = if (emphasis) colors.text else colors.secondaryText,
    )
    fun numbered(text: String, number: Int?) = buildAnnotatedString {
        if (number != null) {
            withStyle(SpanStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.accent, baselineShift = BaselineShift(0.35f))) {
                append("$number ")
            }
        }
        append(com.genesis.core.domain.bible.ScriptureDirection.display(text))
    }

    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .background(colors.background)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onTap),
    ) {
        val sideBySide = maxWidth >= 600.dp
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            contentPadding = PaddingValues(start = if (sideBySide) 32.dp else 22.dp, end = if (sideBySide) 32.dp else 22.dp, top = 64.dp, bottom = 120.dp),
            verticalArrangement = Arrangement.spacedBy(if (sideBySide) 14.dp else 18.dp),
        ) {
            item {
                Box(Modifier.widthIn(max = if (sideBySide) 1100.dp else 640.dp).fillMaxWidth().padding(bottom = 6.dp)) {
                    if (sideBySide) {
                        Row {
                            ColumnTitle(primary, family, Modifier.weight(1f))
                            ColumnTitle(other, family, Modifier.weight(1f).padding(start = 25.dp))
                        }
                    } else {
                        Text(
                            stringResource(R.string.bible_and_language, primary.translation.abbreviation, other.translation.abbreviation),
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = colors.secondaryText,
                        )
                    }
                }
            }
            items(rows, key = { it.number }) { row ->
                val playing = row.number == playingVerse
                val mark = if (playing) Modifier.background(colors.accent.copy(alpha = 0.10f)) else Modifier
                SelectionContainer(Modifier.widthIn(max = if (sideBySide) 1100.dp else 640.dp).fillMaxWidth().then(mark)) {
                    if (sideBySide) {
                        Row {
                            Text(numbered(row.primary.orEmpty(), row.number), style = style(true), modifier = Modifier.weight(1f).padding(end = 24.dp))
                            val rule = colors.separator
                            Text(
                                numbered(row.secondary.orEmpty(), row.number),
                                style = style(true),
                                modifier = Modifier.weight(1f)
                                    .drawBehind { drawLine(rule, Offset(0f, 0f), Offset(0f, size.height), strokeWidth = 1.dp.toPx()) }
                                    .padding(start = 24.dp),
                            )
                        }
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(numbered(row.primary.orEmpty(), row.number), style = style(true))
                            row.secondary?.let { text ->
                                Row {
                                    Text(
                                        other.translation.abbreviation,
                                        style = MaterialTheme.typography.labelSmall,
                                        fontWeight = FontWeight.SemiBold,
                                        color = colors.accent,
                                        modifier = Modifier.padding(top = 3.dp).width(44.dp),
                                    )
                                    Text(numbered(text, null), style = style(false))
                                }
                            }
                        }
                    }
                }
            }
            // Licensed Bibles' notices, as their licences require.
            val notices = listOf(primary.translation, other.translation).filter { it.showsLicenseUnderChapters }.distinctBy { it.id }
            items(notices, key = { "notice-" + it.id }) { translation ->
                Text(
                    translation.license,
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.sp),
                    color = colors.secondaryText,
                    modifier = Modifier.widthIn(max = 640.dp).fillMaxWidth(),
                )
            }
            if (onNext != null) {
                item {
                    OutlinedButton(onClick = onNext, modifier = Modifier.padding(top = 20.dp)) {
                        Text(primary.id.next?.description(primary.translation.language)?.let { "$it  →" } ?: "→", color = colors.accent)
                    }
                }
            }
        }
    }
}

@Composable
private fun ColumnTitle(chapter: Chapter, family: androidx.compose.ui.text.font.FontFamily, modifier: Modifier) {
    val colors = LocalReaderColors.current
    Column(modifier) {
        Text(chapter.id.description(chapter.translation.language), fontFamily = family, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
        Text(chapter.translation.name, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
    }
}
