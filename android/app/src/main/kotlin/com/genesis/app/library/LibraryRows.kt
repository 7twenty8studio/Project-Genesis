package com.genesis.app.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.app.reader.title
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.core.bible.Verse
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.rememberFontFamily
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.study.HighlightColor
import com.genesis.core.domain.study.Note
import com.genesis.core.domain.study.NoteAnchor
import com.genesis.core.domain.study.NoteKind
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Verses looked up from the Bible being read, refreshed when the ids or the Bible change. */
@Composable
internal fun rememberVerses(
    ids: List<VerseId>,
    bibleKey: Any,
    verses: suspend (Collection<VerseId>) -> Map<VerseId, Verse>,
): State<Map<VerseId, Verse>> = produceState(emptyMap(), ids, bibleKey) { value = verses(ids) }

/** A rounded surface, as `.card()` on iOS. */
internal fun Modifier.card(color: Color): Modifier =
    background(color, RoundedCornerShape(18.dp)).padding(16.dp)

/** A verse in a list: its reference (and highlight colour), then the words verbatim. */
@Composable
internal fun VerseSnippet(
    reference: String,
    text: String,
    highlight: HighlightColor? = null,
    maxLines: Int = 3,
    modifier: Modifier = Modifier,
) {
    val colors = LocalReaderColors.current
    val font = rememberFontFamily(LocalReaderPreferences.current.font.available(Entitlements.isPremium))
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (highlight != null) {
                val label = stringResource(R.string.color_highlight, stringResource(highlight.title))
                Spacer(
                    Modifier.size(8.dp)
                        .background(Color(0xFF000000 or highlight.hex.toLong()), CircleShape)
                        .semantics { contentDescription = label },
                )
                Spacer(Modifier.size(6.dp))
            }
            Text(reference, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = colors.accent)
        }
        Text(
            text,
            fontFamily = font,
            fontSize = 17.sp,
            lineHeight = 24.sp,
            color = colors.text,
            maxLines = maxLines,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** A note in Home's and Library's lists, as NoteRow on iOS. */
@Composable
internal fun NoteRow(note: Note, language: String, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val kind = stringResource(note.kind.titleRes)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row {
            val anchor = note.anchor.title(language)
            Text(
                if (anchor.isEmpty()) kind else "$kind · $anchor",
                style = MaterialTheme.typography.labelMedium,
                color = colors.secondaryText,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(shortDate(note.updatedAt), style = MaterialTheme.typography.labelMedium, color = colors.secondaryText)
        }
        Text(
            note.displayTitle(kind),
            style = MaterialTheme.typography.titleMedium,
            color = colors.text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (note.title.isNotBlank() && note.body.isNotBlank()) {
            Text(note.body, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** The note's title, else its first line, else its kind (as `displayTitle` on iOS). */
private fun Note.displayTitle(kind: String): String =
    title.takeIf { it.isNotBlank() } ?: body.lineSequence().firstOrNull()?.takeIf { it.isNotBlank() } ?: kind

internal fun NoteAnchor.title(language: String): String = when (this) {
    is NoteAnchor.Verses -> ReferenceParser.describe(start.rawValue, end.rawValue, language)
    is NoteAnchor.Chapter -> chapter.description(language)
    is NoteAnchor.Book -> BibleBooks.withNumber(book).name(language)
    is NoteAnchor.Theme -> theme
    NoteAnchor.None -> ""
}

internal val NoteKind.titleRes: Int
    get() = when (this) {
        NoteKind.STUDY -> R.string.note_kind_study
        NoteKind.JOURNAL -> R.string.note_kind_journal
        else -> R.string.note
    }

private fun shortDate(millis: Long): String {
    if (millis == 0L) return ""
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "MMMd")
    return DateTimeFormatter.ofPattern(pattern).format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))
}

/** A quiet message for an empty shelf, as QuietEmptyState on iOS. */
@Composable
internal fun QuietEmptyState(title: String, message: String, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    Column(modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, color = colors.text)
        Text(message, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}
