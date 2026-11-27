package com.genesis.app.studylibrary

import android.text.format.Formatter
import androidx.activity.compose.BackHandler
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.original.FooterText
import com.genesis.app.original.Labeled
import com.genesis.app.original.PremiumTeaser
import com.genesis.app.original.Section
import com.genesis.app.original.studyLanguage
import com.genesis.app.prayer.Segmented
import com.genesis.app.reader.ReaderViewModel
import com.genesis.app.settings.Entitlements
import com.genesis.core.bible.Verse
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.OriginalVersification
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.studyresources.DownloadableStudyResource
import com.genesis.core.domain.studyresources.StudyArticle
import com.genesis.core.domain.studyresources.StudyArticleKind
import com.genesis.core.domain.studyresources.StudyArticleSummary
import com.genesis.core.domain.studyresources.StudyIntroduction
import com.genesis.core.domain.studyresources.StudyMarkup
import com.genesis.core.domain.studyresources.StudyNote
import com.genesis.core.domain.studyresources.StudyRange
import com.genesis.core.domain.studyresources.StudyResourceKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Where the Study Library flow is. */
sealed interface StudyPlace {
    data object Library : StudyPlace
    data class VerseResources(val verse: VerseId) : StudyPlace
    data class Detail(val pack: String) : StudyPlace
    data class Browse(val pack: String) : StudyPlace
    data class Article(val pack: String, val id: String) : StudyPlace
    data class Introduction(val pack: String, val book: Int) : StudyPlace
}

/**
 * The Study Library and what it opens, as StudyResourcesView,
 * VerseResourcesView and StudyArticleView on iOS: downloadable study notes,
 * commentaries, Bible dictionaries and lexicons; a verse's notes and
 * commentary; articles and book introductions. Verse links open the
 * passage verbatim from the Bible being read.
 */
@Composable
fun StudyFlow(
    root: StudyPlace,
    viewModel: ReaderViewModel,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
    /** Opens a verse in the reader (and closes the flow); null hides Open in Reader. */
    onOpenVerse: ((VerseId) -> Unit)? = null,
) {
    val colors = LocalReaderColors.current
    val stack = remember(root) { mutableStateListOf(root) }
    var passage by remember { mutableStateOf<StudyRange?>(null) }
    val place = stack.last()
    val open: (StudyPlace) -> Unit = { stack.add(it) }
    val onLink: (StudyMarkup.Link) -> Unit = { link ->
        when (link) {
            is StudyMarkup.Link.Verses -> passage = link.range
            is StudyMarkup.Link.Article -> stack.add(StudyPlace.Article(link.pack, link.id))
        }
    }
    BackHandler { if (stack.size > 1) stack.removeAt(stack.lastIndex) else onDone() }
    val app = LocalContext.current.applicationContext as VerselyApplication
    val library = app.studyResources

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 4.dp, end = 8.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (stack.size > 1) TextButton(onClick = { stack.removeAt(stack.lastIndex) }) { Text("‹ " + stringResource(R.string.back), color = colors.accent) }
            Text(
                title(place, library, viewModel),
                style = MaterialTheme.typography.titleMedium,
                color = colors.text,
                maxLines = 1,
                modifier = Modifier.weight(1f).padding(start = if (stack.size > 1) 0.dp else 16.dp).semantics { heading() },
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 8.dp, bottom = 32.dp).navigationBarsPadding().widthIn(max = 680.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            when (place) {
                StudyPlace.Library -> LibraryPage(library, open)
                is StudyPlace.VerseResources -> VerseResourcesPage(place.verse, library, viewModel, open, onLink)
                is StudyPlace.Detail -> library.resource(place.pack)?.let { DetailPage(it) }
                is StudyPlace.Browse -> BrowsePage(place.pack, library, open)
                is StudyPlace.Article -> ArticlePage(place.pack, place.id, library, onLink)
                is StudyPlace.Introduction -> IntroductionPage(place.pack, place.book, library, onLink)
            }
        }
    }
    passage?.let { range ->
        StudyPassageSheet(range, viewModel, onOpen = onOpenVerse?.let { open -> { verse: VerseId -> passage = null; open(verse) } }) { passage = null }
    }
}

@Composable
private fun title(place: StudyPlace, library: StudyResourceLibrary, viewModel: ReaderViewModel): String {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val language = state.chapter?.translation?.language ?: "en"
    return when (place) {
        StudyPlace.Library -> stringResource(R.string.study_library)
        is StudyPlace.VerseResources -> ReferenceParser.describe(place.verse.rawValue, place.verse.rawValue, language)
        is StudyPlace.Detail -> library.resource(place.pack)?.name.orEmpty()
        is StudyPlace.Browse -> library.resource(place.pack)?.name.orEmpty()
        is StudyPlace.Article -> ""
        is StudyPlace.Introduction -> BibleBooks.withNumber(place.book).name(language)
    }
}

// The library

@Composable
private fun ColumnScope.LibraryPage(library: StudyResourceLibrary, open: (StudyPlace) -> Unit) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val catalog by library.catalog.collectAsStateWithLifecycle()
    val installed by library.installed.collectAsStateWithLifecycle()
    val downloading by library.downloading.collectAsStateWithLifecycle()
    val problem by library.problem.collectAsStateWithLifecycle()
    var loaded by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf<DownloadableStudyResource?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        library.refreshCatalog()
        loaded = true
    }
    FooterText(stringResource(R.string.study_library_intro))
    val appLanguage = context.studyLanguage()
    val all = library.all(catalog, installed)
    for (kind in StudyResourceKind.entries) {
        val items = all.filter { it.kind == kind }.let { list -> list.filter { it.language == appLanguage } + list.filter { it.language != appLanguage } }
        if (items.isEmpty()) continue
        Section(stringResource(kind.title)) {
            items.forEachIndexed { index, item ->
                if (index > 0) androidx.compose.material3.HorizontalDivider(color = colors.separator)
                ResourceCard(
                    item = item,
                    isInstalled = item.id in installed,
                    isDownloading = item.id in downloading,
                    onDownload = { scope.launch { library.download(item) } },
                    onRemove = { removing = item },
                    open = open,
                )
            }
        }
    }
    if (!loaded) CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
    else if (catalog.isEmpty()) FooterText(stringResource(R.string.study_library_offline))
    problem?.let { Text(stringResource(it.message), color = androidx.compose.ui.graphics.Color(0xFFC2410C)) }
    removing?.let { item ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text(stringResource(R.string.remove_pack_title, item.name)) },
            text = { Text(stringResource(R.string.remove_pack_message)) },
            confirmButton = { TextButton(onClick = { library.remove(item.id); removing = null }) { Text(stringResource(R.string.remove), color = androidx.compose.ui.graphics.Color(0xFFB3261E)) } },
            dismissButton = { TextButton(onClick = { removing = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@Composable
private fun ResourceCard(
    item: DownloadableStudyResource,
    isInstalled: Boolean,
    isDownloading: Boolean,
    onDownload: () -> Unit,
    onRemove: () -> Unit,
    open: (StudyPlace) -> Unit,
) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val locked = item.premium && !Entitlements.isPremium
    Column(Modifier.padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(item.name, style = MaterialTheme.typography.titleMedium, color = colors.text)
                val parts = buildList {
                    if (item.author.isNotEmpty()) add(item.author)
                    item.year?.takeIf { it.isNotEmpty() }?.let(::add)
                    item.tradition?.let { tradition(it) }?.let { add(stringResource(it)) }
                    if (item.language != context.studyLanguage()) add(java.util.Locale.forLanguageTag(item.language).getDisplayLanguage(java.util.Locale.getDefault()).replaceFirstChar { it.uppercase() })
                    add(if (isInstalled) stringResource(R.string.on_this_device) else Formatter.formatShortFileSize(context, item.fileBytes))
                }
                Text(parts.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
            }
            when {
                isDownloading -> CircularProgressIndicator(color = colors.accent, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
                isInstalled -> Text("✓", style = MaterialTheme.typography.titleMedium, color = colors.accent)
                locked -> Pill("🔒 " + stringResource(R.string.premium)) {}
                else -> Pill("↓ " + stringResource(R.string.download), onDownload)
            }
        }
        summary(item)?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText) }
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            if ((item.kind == StudyResourceKind.NOTES || item.kind == StudyResourceKind.DICTIONARY) && isInstalled && !locked) {
                Link(stringResource(R.string.browse)) { open(StudyPlace.Browse(item.id)) }
            }
            Link("ⓘ " + stringResource(R.string.about)) { open(StudyPlace.Detail(item.id)) }
            if (isInstalled) Link(stringResource(R.string.remove_from_device), onRemove)
        }
    }
}

@Composable
private fun Pill(title: String, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = colors.accent,
        modifier = Modifier.clip(RoundedCornerShape(10.dp)).border(1.dp, colors.accent, RoundedCornerShape(10.dp)).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 7.dp),
    )
}

@Composable
private fun Link(title: String, onClick: () -> Unit) {
    Text(title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = LocalReaderColors.current.accent, modifier = Modifier.clickable(onClick = onClick).padding(vertical = 4.dp))
}

@Composable
private fun DetailPage(item: DownloadableStudyResource) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    Section {
        summary(item)?.let { Text(it, color = colors.text) }
        if (item.author.isNotEmpty()) Labeled(stringResource(R.string.author), item.author)
        item.year?.takeIf { it.isNotEmpty() }?.let { Labeled(stringResource(R.string.published), it) }
        item.tradition?.let { tradition(it) }?.let { Labeled(stringResource(R.string.tradition), stringResource(it)) }
        Labeled(stringResource(R.string.language), java.util.Locale.forLanguageTag(item.language).getDisplayLanguage(java.util.Locale.getDefault()).replaceFirstChar { it.uppercase() })
        Labeled(stringResource(R.string.download_size), Formatter.formatShortFileSize(context, item.fileBytes))
        Labeled(stringResource(R.string.access), stringResource(if (item.premium) R.string.premium else R.string.free))
    }
    Section(stringResource(R.string.license), footer = if (item.kind == StudyResourceKind.COMMENTARY) ({ FooterText(stringResource(R.string.commentary_detail_footer)) }) else null) {
        Text(item.license, color = colors.text)
        if (item.attribution.isNotEmpty()) Text(item.attribution, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
    }
}

// A verse's notes and commentary

private data class PackResult(val resource: DownloadableStudyResource, val hasIntroduction: Boolean, val notes: List<StudyNote>, val articles: List<StudyArticleSummary>) {
    val isEmpty: Boolean get() = notes.isEmpty() && articles.isEmpty() && !hasIntroduction
}

@Composable
private fun ColumnScope.VerseResourcesPage(verse: VerseId, library: StudyResourceLibrary, viewModel: ReaderViewModel, open: (StudyPlace) -> Unit, onLink: (StudyMarkup.Link) -> Unit) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val installed by library.installed.collectAsStateWithLifecycle()
    val chosen by library.chosenCommentary.collectAsStateWithLifecycle()
    var commentaryTab by rememberSaveable { mutableStateOf(false) }
    val premium = Entitlements.isPremium
    val state by viewModel.state.collectAsStateWithLifecycle()
    val translation = state.chapter?.translation
    val language = translation?.language ?: "en"
    val notePacks = (library.installedResources(StudyResourceKind.NOTES, installed) + library.installedResources(StudyResourceKind.DICTIONARY, installed)).filter { premium || !it.premium }
    val commentaries = library.installedResources(StudyResourceKind.COMMENTARY, installed)
    val current = remember(installed, chosen, premium) { library.commentary(premium) }
    // Packs number verses as the KJV does.
    val target = translation?.let { OriginalVersification.map(it.id)?.alignment(verse)?.kjv?.firstOrNull() } ?: verse
    val text by produceState("", verse, state.bible) { value = viewModel.withBible { it.verses(listOf(verse))[verse]?.plainText }.orEmpty() }
    val notes by produceState<List<PackResult>?>(null, target, notePacks.map { it.id }) {
        value = withContext(Dispatchers.IO) {
            notePacks.mapNotNull { item ->
                val repository = library.repository(item.id) ?: return@mapNotNull null
                runCatching {
                    PackResult(item, repository.introduction(target.book) != null, repository.notes(target), repository.articles(target))
                }.getOrNull()
            }
        }
    }
    val commentary by produceState<PackResult?>(null, target, current?.id) {
        val item = current ?: return@produceState
        value = withContext(Dispatchers.IO) {
            library.repository(item.id)?.let { runCatching { PackResult(item, false, it.notes(target), emptyList()) }.getOrNull() }
        }
    }

    Section {
        Text(text, style = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Serif), color = colors.text)
        Segmented(listOf(stringResource(R.string.notes_tab), stringResource(R.string.commentary)), selected = if (commentaryTab) 1 else 0) { commentaryTab = it == 1 }
    }
    if (!commentaryTab) {
        val loaded = notes
        when {
            notePacks.isEmpty() -> GetStarted(stringResource(R.string.study_get_notes)) { open(StudyPlace.Library) }
            loaded == null -> CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
            else -> {
                if (loaded.all { it.isEmpty }) Section { Text(stringResource(R.string.no_notes_on_verse), color = colors.secondaryText) }
                for (result in loaded.filter { !it.isEmpty }) {
                    for (note in result.notes) NoteSection(note, result.resource, language, onLink)
                    if (result.hasIntroduction || result.articles.isNotEmpty()) {
                        Section(if (result.resource.kind == StudyResourceKind.DICTIONARY) result.resource.name else stringResource(R.string.more_from, result.resource.name)) {
                            if (result.hasIntroduction) {
                                Row(Modifier.fillMaxWidth().clickable { open(StudyPlace.Introduction(result.resource.id, target.book)) }.padding(vertical = 4.dp)) {
                                    Text(stringResource(R.string.introduction_to, BibleBooks.withNumber(target.book).name(language)), color = colors.text, modifier = Modifier.weight(1f))
                                    Text("›", color = colors.secondaryText)
                                }
                            }
                            for (article in result.articles) ArticleRow(article) { open(StudyPlace.Article(result.resource.id, article.id)) }
                        }
                    }
                }
            }
        }
    } else {
        when {
            commentaries.isEmpty() -> GetStarted(stringResource(R.string.study_get_commentary)) { open(StudyPlace.Library) }
            current == null -> PremiumTeaser(stringResource(R.string.commentaries_premium_teaser))
            else -> {
                var menu by remember { mutableStateOf(false) }
                Section {
                    Box {
                        Text("${current.name}  ▾", color = colors.accent, fontWeight = FontWeight.SemiBold, modifier = Modifier.fillMaxWidth().clickable { menu = true }.padding(vertical = 4.dp))
                        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            for (item in commentaries.filter { premium || !it.premium }) {
                                DropdownMenuItem(text = { Text((if (item.id == current.id) "✓ " else "") + item.name) }, onClick = { menu = false; library.chooseCommentary(item.id) })
                            }
                        }
                    }
                }
                val loaded = commentary
                if (loaded == null || loaded.resource.id != current.id) {
                    CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
                } else {
                    if (loaded.notes.isEmpty()) Section { Text(stringResource(R.string.no_comment_on_verse, current.name), color = colors.secondaryText) }
                    for (note in loaded.notes) NoteSection(note, current, language, onLink)
                    FooterText(stringResource(R.string.commentary_apart))
                }
            }
        }
    }
    Section(footer = if (context.studyLanguage() != "en" || language != "en") ({ FooterText(stringResource(R.string.study_mostly_english)) }) else null) {
        Text(stringResource(R.string.study_library), color = colors.accent, modifier = Modifier.fillMaxWidth().clickable { open(StudyPlace.Library) }.padding(vertical = 4.dp))
    }
}

@Composable
private fun GetStarted(message: String, onOpen: () -> Unit) {
    val colors = LocalReaderColors.current
    Section {
        Text(message, color = colors.secondaryText)
        Text(stringResource(R.string.open_study_library), color = colors.accent, modifier = Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(vertical = 4.dp))
    }
}

@Composable
private fun NoteSection(note: StudyNote, resource: DownloadableStudyResource, language: String, onLink: (StudyMarkup.Link) -> Unit) {
    val reference = note.range.description(language)
    Section(
        note.title?.let { "$reference · $it" } ?: reference,
        footer = { FooterText(if (resource.author.isEmpty()) resource.name else "${resource.name} · ${resource.author}") },
    ) {
        StudyText(note.text, onLink)
    }
}

@Composable
private fun ArticleRow(article: StudyArticleSummary, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(article.title, color = colors.text)
            StudyArticleKind.of(article.kind)?.let { Text(stringResource(it.title), style = MaterialTheme.typography.labelSmall, color = colors.secondaryText) }
        }
        Text("›", color = colors.secondaryText)
    }
}

// Articles

@Composable
private fun ColumnScope.BrowsePage(pack: String, library: StudyResourceLibrary, open: (StudyPlace) -> Unit) {
    val colors = LocalReaderColors.current
    var query by rememberSaveable { mutableStateOf("") }
    val results by produceState<List<StudyArticleSummary>>(emptyList(), query) {
        if (query.isNotEmpty()) delay(200)
        value = withContext(Dispatchers.IO) { runCatching { library.repository(pack)?.searchArticles(query, 200) }.getOrNull().orEmpty() }
    }
    OutlinedTextField(
        value = query,
        onValueChange = { query = it },
        placeholder = { Text(stringResource(R.string.search)) },
        singleLine = true,
        colors = com.genesis.app.prayer.fieldColors(),
        modifier = Modifier.fillMaxWidth(),
    )
    if (results.isNotEmpty()) {
        Section {
            for (summary in results) ArticleRow(summary) { open(StudyPlace.Article(pack, summary.id)) }
        }
    }
}

@Composable
private fun ColumnScope.ArticlePage(pack: String, id: String, library: StudyResourceLibrary, onLink: (StudyMarkup.Link) -> Unit) {
    val colors = LocalReaderColors.current
    val installed by library.installed.collectAsStateWithLifecycle()
    val resource = library.resource(pack)
    val locked = resource?.premium == true && !Entitlements.isPremium
    var loaded by remember(id) { mutableStateOf(false) }
    val article by produceState<StudyArticle?>(null, pack, id, installed) {
        value = withContext(Dispatchers.IO) { runCatching { library.repository(pack)?.article(id) }.getOrNull() }
        loaded = true
    }
    when {
        pack !in installed -> Section { Text(stringResource(R.string.download_to_read_article, resource?.name ?: stringResource(R.string.this_resource)), color = colors.secondaryText) }
        locked -> PremiumTeaser(stringResource(R.string.resource_premium_teaser))
        article != null -> {
            val current = article!!
            Text(current.title, style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif), color = colors.text, modifier = Modifier.semantics { heading() })
            Section(footer = resource?.let { { FooterText(it.attribution.ifEmpty { it.name }) } }) { StudyText(current.text, onLink) }
        }
        loaded -> Section { Text(stringResource(R.string.article_missing), color = colors.secondaryText) }
        else -> CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
    }
}

@Composable
private fun ColumnScope.IntroductionPage(pack: String, book: Int, library: StudyResourceLibrary, onLink: (StudyMarkup.Link) -> Unit) {
    val colors = LocalReaderColors.current
    val introduction by produceState<StudyIntroduction?>(null, pack, book) {
        value = withContext(Dispatchers.IO) { runCatching { library.repository(pack)?.introduction(book) }.getOrNull() }
    }
    val current = introduction
    if (current == null) {
        CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
        return
    }
    current.title?.let { Text(it, style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif), color = colors.text) }
    val resource = library.resource(pack)
    Section(footer = resource?.let { { FooterText(it.attribution.ifEmpty { it.name }) } }) { StudyText(current.text, onLink) }
}

/** A study pack's text: headings, list items and paragraphs, with verse and article links. */
@Composable
internal fun StudyText(text: String, onLink: (StudyMarkup.Link) -> Unit) {
    val colors = LocalReaderColors.current
    val blocks = remember(text) { StudyMarkup.blocks(text) }
    for (block in blocks) {
        val styled = remember(block, colors) { styled(block.inline, colors.accent, onLink) }
        when (block) {
            is StudyMarkup.Block.Heading -> Text(styled, style = MaterialTheme.typography.titleMedium, color = colors.text, modifier = Modifier.semantics { heading() })
            is StudyMarkup.Block.ListItem -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("•", color = colors.accent)
                Text(styled, style = MaterialTheme.typography.bodyLarge, color = colors.text)
            }
            is StudyMarkup.Block.Paragraph -> Text(styled, style = MaterialTheme.typography.bodyLarge, color = colors.text)
        }
    }
}

private fun styled(inline: String, accent: androidx.compose.ui.graphics.Color, onLink: (StudyMarkup.Link) -> Unit): AnnotatedString = buildAnnotatedString {
    for (run in StudyMarkup.runs(inline)) {
        val style = SpanStyle(fontWeight = if (run.bold) FontWeight.SemiBold else null, fontStyle = if (run.italic) FontStyle.Italic else null)
        val link = run.url?.let(StudyMarkup::link)
        if (link != null) {
            withLink(LinkAnnotation.Clickable(run.url!!, TextLinkStyles(style.merge(SpanStyle(color = accent)))) { onLink(link) }) { append(run.text) }
        } else {
            withStyle(style) { append(run.text) }
        }
    }
}

/** The verses a link points to, verbatim from the Bible being read (long links show their opening verses). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StudyPassageSheet(range: StudyRange, viewModel: ReaderViewModel, onOpen: ((VerseId) -> Unit)?, onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    val state by viewModel.state.collectAsStateWithLifecycle()
    val translation = state.chapter?.translation
    val language = translation?.language ?: "en"
    val verses by produceState<List<Verse>?>(null, range, state.bible) {
        value = viewModel.withBible { bible ->
            val map = OriginalVersification.parallelMap(bible.translation.id)
            val (first, last) = map.ownRange(range.start.takeIf { it.verse > 0 } ?: VerseId(range.start.book, range.start.chapter, 1), range.end)
            bible.passage(first, last, limit = 40)
        }.orEmpty()
    }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.background) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(range.description(language), style = MaterialTheme.typography.titleMedium, color = colors.text, modifier = Modifier.weight(1f).semantics { heading() })
                val first = verses?.firstOrNull()
                if (onOpen != null && first != null) TextButton(onClick = { onOpen(first.id) }) { Text(stringResource(R.string.open_in_reader), color = colors.accent) }
            }
            val loaded = verses
            when {
                loaded == null -> CircularProgressIndicator(color = colors.accent)
                loaded.isEmpty() -> Text(stringResource(R.string.study_passage_missing, translation?.name.orEmpty()), color = colors.secondaryText)
                else -> for (verse in loaded) {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(ReferenceParser.describe(verse.id.rawValue, verse.id.rawValue, language), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.accent)
                        Text(verse.plainText, style = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Serif), color = colors.text)
                    }
                }
            }
            translation?.let { FooterText(it.name) }
        }
    }
}

@get:StringRes
private val StudyResourceKind.title: Int
    get() = when (this) {
        StudyResourceKind.NOTES -> R.string.kind_notes
        StudyResourceKind.COMMENTARY -> R.string.kind_commentaries
        StudyResourceKind.DICTIONARY -> R.string.kind_dictionaries
        StudyResourceKind.LEXICON -> R.string.kind_lexicons
    }

@get:StringRes
private val StudyArticleKind.title: Int
    get() = when (this) {
        StudyArticleKind.PROFILE -> R.string.article_profile
        StudyArticleKind.THEME -> R.string.article_theme
        StudyArticleKind.KEY_TERM -> R.string.article_key_term
        StudyArticleKind.NAME -> R.string.article_name
        StudyArticleKind.TERM -> R.string.article_term
    }

@get:StringRes
private val StudyDownloadProblem.message: Int
    get() = when (this) {
        StudyDownloadProblem.NOT_CONFIGURED -> R.string.study_error_not_configured
        StudyDownloadProblem.OFFLINE -> R.string.study_error_offline
        StudyDownloadProblem.DAMAGED -> R.string.study_error_damaged
        StudyDownloadProblem.NOT_A_STUDY_PACK -> R.string.study_error_not_pack
    }

@StringRes
private fun tradition(raw: String): Int? = when (raw) {
    "evangelical" -> R.string.tradition_evangelical
    "presbyterian" -> R.string.tradition_presbyterian
    "puritan" -> R.string.tradition_puritan
    "reformed_baptist" -> R.string.tradition_reformed_baptist
    "wesleyan" -> R.string.tradition_wesleyan
    "reformed" -> R.string.tradition_reformed
    "lutheran" -> R.string.tradition_lutheran
    "anglican" -> R.string.tradition_anglican
    else -> null
}

/** The app's own summary in the app's language where it has one; the server's otherwise. */
@Composable
private fun summary(item: DownloadableStudyResource): String? {
    val own = when (item.id) {
        "tyndale-notes" -> R.string.pack_tyndale_notes
        "tyndale-dictionary" -> R.string.pack_tyndale_dictionary
        "es-palabras" -> R.string.pack_es_palabras
        "jfb" -> R.string.pack_jfb
        "mhc" -> R.string.pack_mhc
        "barnes" -> R.string.pack_barnes
        "gill" -> R.string.pack_gill
        "clarke" -> R.string.pack_clarke
        "wesley" -> R.string.pack_wesley
        "calvin" -> R.string.pack_calvin
        "keil-delitzsch" -> R.string.pack_keil_delitzsch
        "treasury-of-david" -> R.string.pack_treasury_of_david
        "burkitt" -> R.string.pack_burkitt
        "lexicons" -> R.string.pack_lexicons
        else -> null
    }
    return own?.let { stringResource(it) } ?: item.summary.takeIf { it.isNotEmpty() }
}
