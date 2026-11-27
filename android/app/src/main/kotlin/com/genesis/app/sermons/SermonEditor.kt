package com.genesis.app.sermons

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.app.prayer.JournalBible
import com.genesis.app.prayer.Passages
import com.genesis.app.prayer.fieldColors
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.Footer
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.rememberFontFamily
import com.genesis.core.design.toColors
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.prayer.PrayerPassage
import com.genesis.core.domain.sermons.Sermon
import com.genesis.core.domain.sermons.SermonEditing
import com.genesis.core.domain.sermons.SermonMarkdown
import com.genesis.core.domain.sermons.SermonMarkdown.Format
import com.genesis.core.domain.theme.ReaderTheme
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Writes or edits one sermon's notes, as SermonEditorView on iOS: the title,
 * who preached where and when, the notes shown formatted (never the Markdown
 * marks) with a format bar, and the passages verbatim from the Bible being
 * read. Church Mode dims the screen to the Night palette, keeps it awake and
 * offers Look Up a Verse. Changes are kept when it closes; empty notes are
 * discarded.
 */
@Composable
internal fun SermonEditor(
    original: Sermon,
    bible: JournalBible,
    churchSuggestions: (String) -> List<String>,
    onClose: (Sermon, Boolean) -> Unit,
    modifier: Modifier,
    church: com.genesis.app.churchsermons.ChurchSermonContext? = null,
) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("sermons", Context.MODE_PRIVATE) }
    var churchMode by remember { mutableStateOf(prefs.getBoolean("churchMode", false)) }
    var largerText by remember { mutableStateOf(prefs.getBoolean("churchMode.largerText", true)) }
    var draft by remember(original.id) { mutableStateOf(original) }
    var body by remember(original.id) { mutableStateOf(TextFieldValue(original.body)) }
    var detailsOpen by remember(original.id) { mutableStateOf(original.preacher.isBlank() && original.church.isBlank()) }
    var confirmDelete by remember { mutableStateOf(false) }
    var lookingUp by remember { mutableStateOf(false) }
    val exportScope = rememberCoroutineScope()
    var openHandout by remember { mutableStateOf<com.genesis.core.cloud.community.SavedHandout?>(null) }
    fun close() = onClose(draft.copy(body = body.text), false)
    BackHandler { close() }
    openHandout?.let { handout ->
        com.genesis.app.churchsermons.SavedHandoutScreen(
            handout,
            church,
            onSave = { responses -> draft = com.genesis.app.churchsermons.ChurchSermonNotes.updating(draft, handout, responses) },
            onDone = { openHandout = null },
        )
        return
    }

    // Church Mode keeps the screen awake while the notes are open, and always lets go.
    val view = LocalView.current
    DisposableEffect(churchMode) {
        view.keepScreenOn = churchMode
        onDispose { view.keepScreenOn = false }
    }

    val colors = if (churchMode) ReaderTheme.NIGHT.palette.toColors(true) else LocalReaderColors.current
    val bodySize = if (churchMode && largerText) 21.sp else 17.sp
    val family = rememberFontFamily(LocalReaderPreferences.current.font.available(Entitlements.isPremium))

    fun setBody(edit: SermonMarkdown.Edit) {
        body = TextFieldValue(edit.text, TextRange(edit.selectionStart, edit.selectionEnd))
    }

    CompositionLocalProvider(LocalReaderColors provides colors) {
        Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding().imePadding()) {
            Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.sermon_notes),
                    style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                    color = colors.text,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                val star = stringResource(if (draft.isFavourite) R.string.remove_favorite else R.string.favorite)
                TextButton(onClick = { draft = draft.copy(isFavourite = !draft.isFavourite) }, modifier = Modifier.semantics { contentDescription = star }) {
                    Text(if (draft.isFavourite) "★" else "☆", style = MaterialTheme.typography.titleLarge, color = if (draft.isFavourite) colors.accent else colors.secondaryText)
                }
                com.genesis.app.journal.JournalExtrasMenu(
                    sermon = true,
                    onTemplate = { template ->
                        val inserted = com.genesis.core.domain.journal.JournalTemplate.inserting(template, body.text, body.selection.start)
                        body = TextFieldValue(inserted.text, TextRange(inserted.cursor))
                    },
                    onExport = {
                        val snapshot = draft.copy(body = body.text)
                        exportScope.launch {
                            val export = com.genesis.app.journal.JournalExportBuilder(context, bible).export(snapshot)
                            com.genesis.app.journal.JournalPdf.share(context, export)
                        }
                    },
                )
                TextButton(onClick = ::close) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
            }
            Row(
                Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Chip(stringResource(R.string.church_mode), churchMode) {
                    churchMode = !churchMode
                    prefs.edit().putBoolean("churchMode", churchMode).apply()
                }
                if (churchMode) {
                    Chip(stringResource(R.string.larger_text), largerText) {
                        largerText = !largerText
                        prefs.edit().putBoolean("churchMode.largerText", largerText).apply()
                    }
                    Chip(stringResource(R.string.look_up_verse), false) { lookingUp = true }
                }
            }

            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp)) {
                BasicTextField(
                    value = draft.title,
                    onValueChange = { draft = draft.copy(title = it.take(200)) },
                    textStyle = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, color = colors.text),
                    cursorBrush = SolidColor(colors.accent),
                    modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                    decorationBox = { field ->
                        Box {
                            if (draft.title.isEmpty()) {
                                Text(stringResource(R.string.sermon_title_hint), style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif), color = colors.secondaryText)
                            }
                            field()
                        }
                    },
                )
                Details(draft, open = detailsOpen, onToggle = { detailsOpen = !detailsOpen }, churchSuggestions = churchSuggestions) { draft = it }

                Spacer(Modifier.size(12.dp))
                FormatBar(body) { setBody(it) }
                Spacer(Modifier.size(8.dp))
                val transformation = remember(bodySize, colors) { MarkdownTransformation(headingSize = (bodySize.value + 4).sp, quoteColor = colors.secondaryText) }
                BasicTextField(
                    value = body,
                    onValueChange = { new ->
                        val carried = SermonEditing.afterReturn(body.text, new.text, new.selection.start)
                        body = if (carried != null) TextFieldValue(carried.text, TextRange(carried.selectionStart, carried.selectionEnd)) else new
                    },
                    textStyle = TextStyle(fontFamily = family, fontSize = bodySize, lineHeight = (bodySize.value * 1.45f).sp, color = colors.text),
                    cursorBrush = SolidColor(colors.accent),
                    visualTransformation = transformation,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 240.dp)
                        .clip(RoundedCornerShape(12.dp)).background(colors.surface).padding(14.dp),
                    decorationBox = { field ->
                        Box {
                            if (body.text.isEmpty()) {
                                Text(stringResource(R.string.notes), fontFamily = family, fontSize = bodySize, color = colors.secondaryText)
                            }
                            field()
                        }
                    },
                )
                if (churchMode) Footer(stringResource(R.string.church_mode_footer))

                Passages(
                    draft.passages,
                    bible,
                    Sermon.MAXIMUM_PASSAGES,
                    stringResource(R.string.sermon_passages_footer),
                    onAttach = { passage -> draft = draft.attaching(passage) },
                    onDetach = { passage -> draft = draft.copy(passages = draft.passages.filter { it.id != passage.id }) },
                )

                com.genesis.app.churchsermons.SavedHandoutsSection(draft.handoutsJson) { openHandout = it }

                Spacer(Modifier.size(28.dp))
                TextButton(onClick = { confirmDelete = true }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.sermon_delete), color = Destructive)
                }
                Spacer(Modifier.size(24.dp))
            }
        }

        if (lookingUp) {
            LookUpVerse(
                bible = bible,
                onInsert = { passage ->
                    lookingUp = false
                    setBody(SermonMarkdown.inserting(passage.reference(bible.language), body.text, body.selection.start))
                    draft = draft.attaching(passage)
                },
                onDismiss = { lookingUp = false },
            )
        }

        if (confirmDelete) {
            AlertDialog(
                onDismissRequest = { confirmDelete = false },
                title = { Text(stringResource(R.string.sermon_delete_question)) },
                confirmButton = {
                    TextButton(onClick = {
                        confirmDelete = false
                        onClose(draft, true)
                    }) { Text(stringResource(R.string.delete), color = Destructive) }
                },
                dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel), color = colors.accent) } },
                containerColor = colors.surface,
                titleContentColor = colors.text,
            )
        }
    }
}

private val Destructive = Color(0xFFC0392B)

private fun Sermon.attaching(passage: PrayerPassage): Sermon =
    if (passages.any { it.id == passage.id } || passages.size >= Sermon.MAXIMUM_PASSAGES) this else copy(passages = passages + passage)

@Composable
private fun Chip(title: String, selected: Boolean, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Text(
        title,
        style = MaterialTheme.typography.bodyMedium,
        color = if (selected) colors.background else colors.text,
        modifier = Modifier.clip(CircleShape).clickable(onClick = onClick)
            .background(if (selected) colors.accent else colors.surface)
            .padding(horizontal = 14.dp, vertical = 7.dp),
    )
}

/** Who preached, where and when, and the series: one line, opened to edit. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Details(sermon: Sermon, open: Boolean, onToggle: () -> Unit, churchSuggestions: (String) -> List<String>, onChange: (Sermon) -> Unit) {
    val colors = LocalReaderColors.current
    var picking by remember { mutableStateOf(false) }
    val summary = listOf(sermon.preacher.trim(), sermon.churchName, sermonDate(sermon.preachedAt)).filter { it.isNotEmpty() }.joinToString(" · ")
    Row(Modifier.fillMaxWidth().clickable(onClick = onToggle).padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(summary, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, modifier = Modifier.weight(1f))
        Text(stringResource(R.string.sermon_details) + if (open) " ▴" else " ▾", style = MaterialTheme.typography.bodyMedium, color = colors.accent)
    }
    if (!open) return
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value = sermon.preacher,
            onValueChange = { onChange(sermon.copy(preacher = it.take(120))) },
            label = { Text(stringResource(R.string.preacher)) },
            singleLine = true,
            colors = fieldColors(),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = sermon.church,
            onValueChange = { onChange(sermon.copy(church = it.take(120))) },
            label = { Text(stringResource(R.string.church)) },
            singleLine = true,
            colors = fieldColors(),
            modifier = Modifier.fillMaxWidth(),
        )
        val suggestions = remember(sermon.church) { churchSuggestions(sermon.church).filter { it != sermon.church.trim() } }
        if (suggestions.isNotEmpty()) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                suggestions.forEach { name -> Chip(name, false) { onChange(sermon.copy(church = name)) } }
            }
        }
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(4.dp)).clickable { picking = true }.background(colors.surface).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(stringResource(R.string.date), color = colors.text, modifier = Modifier.weight(1f))
            Text(sermonDate(sermon.preachedAt), color = colors.accent)
        }
        OutlinedTextField(
            value = sermon.series.orEmpty(),
            onValueChange = { onChange(sermon.copy(series = it.take(120).ifEmpty { null })) },
            label = { Text(stringResource(R.string.sermon_series)) },
            singleLine = true,
            colors = fieldColors(),
            modifier = Modifier.fillMaxWidth(),
        )
    }
    if (picking) {
        val zone = ZoneId.systemDefault()
        val preached = Instant.ofEpochMilli(sermon.preachedAt).atZone(zone)
        val state = rememberDatePickerState(initialSelectedDateMillis = preached.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { picking = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { millis ->
                        val day = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                        onChange(sermon.copy(preachedAt = day.atTime(preached.toLocalTime()).atZone(zone).toInstant().toEpochMilli()))
                    }
                    picking = false
                }) { Text(stringResource(R.string.done)) }
            },
            dismissButton = { TextButton(onClick = { picking = false }) { Text(stringResource(R.string.cancel)) } },
        ) { DatePicker(state) }
    }
}

/** Bold, italic, heading, lists and quote, on the selection or the line. */
@Composable
private fun FormatBar(value: TextFieldValue, onEdit: (SermonMarkdown.Edit) -> Unit) {
    val colors = LocalReaderColors.current
    val start = value.selection.min
    val end = value.selection.max
    val current = SermonEditing.lineFormat(value.text, start)
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(colors.surface).padding(4.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
    ) {
        @Composable
        fun button(symbol: String, label: Int, active: Boolean, style: TextStyle = MaterialTheme.typography.titleMedium, onClick: () -> Unit) {
            val description = stringResource(label)
            Text(
                symbol,
                style = style,
                color = if (active) colors.background else colors.text,
                modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(if (active) colors.accent else Color.Transparent)
                    .clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 6.dp)
                    .semantics { contentDescription = description },
            )
        }
        button("B", R.string.format_bold, false, MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)) {
            onEdit(SermonEditing.toggleInline(value.text, start, end, Format.BOLD))
        }
        button("I", R.string.format_italic, false, MaterialTheme.typography.titleMedium.copy(fontStyle = FontStyle.Italic, fontFamily = FontFamily.Serif)) {
            onEdit(SermonEditing.toggleInline(value.text, start, end, Format.ITALIC))
        }
        listOf(
            Triple("H", R.string.format_heading, Format.HEADING),
            Triple("•", R.string.format_bullet, Format.BULLET),
            Triple("1.", R.string.format_numbered, Format.NUMBERED),
            Triple("❝", R.string.format_quote, Format.QUOTE),
        ).forEach { (symbol, label, format) ->
            button(symbol, label, current == format) { onEdit(SermonEditing.toggleLine(value.text, start, end, format)) }
        }
    }
}

/** Shows the notes formatted: marks hidden, headings larger, quotes in italics. */
private data class MarkdownTransformation(val headingSize: TextUnit, val quoteColor: Color) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val display = SermonEditing.display(text.text)
        val styled = AnnotatedString.Builder(display.text)
        display.styles.forEach { range ->
            val style = when (range.style) {
                SermonEditing.Style.BOLD -> SpanStyle(fontWeight = FontWeight.Bold)
                SermonEditing.Style.ITALIC -> SpanStyle(fontStyle = FontStyle.Italic)
                SermonEditing.Style.HEADING -> SpanStyle(fontWeight = FontWeight.SemiBold, fontSize = headingSize)
                SermonEditing.Style.QUOTE -> SpanStyle(fontStyle = FontStyle.Italic, color = quoteColor)
            }
            styled.addStyle(style, range.start, range.end)
        }
        val shownLength = display.text.length
        val mapping = object : OffsetMapping {
            override fun originalToTransformed(offset: Int): Int = display.toShown[offset.coerceIn(0, display.toShown.size - 1)].coerceIn(0, shownLength)
            override fun transformedToOriginal(offset: Int): Int = display.toMarkdown[offset.coerceIn(0, display.toMarkdown.size - 1)].coerceIn(0, text.length)
        }
        return TransformedText(styled.toAnnotatedString(), mapping)
    }
}

/** Church Mode's Look Up a Verse: the passage verbatim, then Insert into Notes. */
@Composable
private fun LookUpVerse(bible: JournalBible, onInsert: (PrayerPassage) -> Unit, onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf("") }
    var found by remember { mutableStateOf<Pair<PrayerPassage, String>?>(null) }
    var problem by remember { mutableStateOf<Int?>(null) }
    val family = rememberFontFamily(LocalReaderPreferences.current.font.available(Entitlements.isPremium))

    fun lookUp() {
        val passage = PrayerPassage.parse(text, portugueseFirst = bible.language.startsWith("pt")) { chapter ->
            BibleBooks.withNumber(chapter.book).verses.getOrNull(chapter.chapter - 1)
        }
        if (passage == null) {
            problem = R.string.passage_unreadable
            found = null
            return
        }
        scope.launch {
            val ids = (passage.start.verse..passage.end.verse).map { VerseId(passage.start.book, passage.start.chapter, it) }
            val verses = bible.verses(ids)
            val words = ids.mapNotNull { verses[it]?.plainText }
            if (words.isEmpty()) {
                problem = R.string.passage_not_in_bible
                found = null
            } else {
                problem = null
                found = passage to words.joinToString(" ")
            }
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.look_up_verse)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = text,
                        onValueChange = {
                            text = it
                            problem = null
                        },
                        placeholder = { Text(stringResource(R.string.passage_hint)) },
                        singleLine = true,
                        colors = fieldColors(),
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(enabled = text.isNotBlank(), onClick = ::lookUp) { Text(stringResource(R.string.search), color = colors.accent) }
                }
                found?.let { (passage, words) ->
                    Text(
                        "${passage.reference(bible.language)} · ${bible.abbreviation}",
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = colors.accent,
                    )
                    Text(words, fontFamily = family, fontSize = 17.sp, color = colors.text)
                }
                problem?.let { Text(stringResource(it), style = MaterialTheme.typography.bodySmall, color = Destructive) }
                Text(stringResource(R.string.look_up_footer), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
            }
        },
        confirmButton = {
            TextButton(enabled = found != null, onClick = { found?.let { onInsert(it.first) } }) {
                Text(stringResource(R.string.insert_into_notes), color = if (found != null) colors.accent else colors.secondaryText)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = colors.accent) } },
        containerColor = colors.surface,
        titleContentColor = colors.text,
        textContentColor = colors.text,
    )
}
