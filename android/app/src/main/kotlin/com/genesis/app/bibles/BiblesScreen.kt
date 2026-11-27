package com.genesis.app.bibles

import android.text.format.Formatter
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.settings.Entitlements
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.bible.BibleRepository
import com.genesis.core.bible.InstalledBible
import com.genesis.core.bible.Translation
import com.genesis.core.domain.bible.DownloadableBible
import com.genesis.core.domain.bible.ReadingLibrary
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

/**
 * The Bibles screen (Global Reading Library), as BibleDownloadsView on iOS:
 * Bibles by language, the most read first, those on the phone and those to
 * download together, with a language menu that opens on the current Bible's
 * language and never changes the app's own. Every Bible here is free,
 * except one whose publisher charges a licence fee (Premium).
 */
@Composable
fun BiblesScreen(currentBible: String, onRead: (InstalledBible) -> Unit, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val app = context.applicationContext as VerselyApplication
    val library = app.bibles
    val catalog by library.catalog.collectAsStateWithLifecycle()
    val loaded by library.catalogLoaded.collectAsStateWithLifecycle()
    val downloads by library.downloads.collectAsStateWithLifecycle()
    val downloading by library.downloading.collectAsStateWithLifecycle()
    val savedChanges by library.savedChanges.collectAsStateWithLifecycle()
    val problem by library.problem.collectAsStateWithLifecycle()
    val bookProgress by library.bookProgress.collectAsStateWithLifecycle()
    var tried by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf<Pair<String, String>?>(null) }
    val scope = rememberCoroutineScope()
    BackHandler(onBack = onDone)
    LaunchedEffect(Unit) {
        library.refreshCatalog()
        tried = true
    }

    // What each installed Bible's file says about itself (name, language, licence).
    val installedBibles = remember(downloads) { library.installed(downloads) }
    val translations by produceState(emptyMap<String, Translation>(), installedBibles) {
        value = withContext(Dispatchers.IO) {
            installedBibles.mapNotNull { bible -> runCatching { bible.id to BibleRepository.open(context, bible).use { it.translation } }.getOrNull() }.toMap()
        }
    }
    val offered = catalog.associateBy { it.id }
    val entries = buildList {
        installedBibles.forEachIndexed { index, bible ->
            val translation = translations[bible.id] ?: return@forEachIndexed
            add(ReadingLibrary.Entry(bible.id, translation.name, translation.language, offered[bible.id]?.popularity ?: builtInPopularity[bible.id], index, true))
        }
        catalog.forEachIndexed { index, item ->
            if (installedBibles.none { it.id == item.id }) add(ReadingLibrary.Entry(item.id, item.name, item.language, item.popularity, 100 + index, false))
        }
    }
    val appLanguage = Locale.getDefault().language
    val currentLanguage = translations[currentBible]?.language
    var chosenLanguage by rememberSaveable { mutableStateOf<String?>(null) }
    val language = chosenLanguage ?: ReadingLibrary.defaultLanguage(currentLanguage, appLanguage, entries)
    val languages = ReadingLibrary.languages(entries, appLanguage)
    var guideOpen by rememberSaveable { mutableStateOf(false) }
    if (guideOpen) {
        val guideLanguage = if (language == ReadingLibrary.ALL_LANGUAGES) ReadingLibrary.base(currentLanguage ?: appLanguage) else language
        val bibles = ReadingLibrary.sections(entries, guideLanguage, appLanguage).firstOrNull()?.second.orEmpty().map { entry ->
            GuideBible(
                entry.id,
                entry.name,
                translations[entry.id]?.abbreviation ?: entry.id,
                com.genesis.core.domain.bible.TranslationProfile.of(offered[entry.id], entry.id),
            )
        }
        TranslationGuideScreen(languageName(guideLanguage), bibles) { guideOpen = false }
        return
    }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.bibles),
                style = MaterialTheme.typography.titleMedium,
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 8.dp, bottom = 32.dp).navigationBarsPadding().widthIn(max = 680.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Text(stringResource(R.string.bibles_free_offline), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
            if (languages.size > 1) LanguageMenu(language, languages) { chosenLanguage = it }
            Text(
                "ⓘ  " + stringResource(R.string.guide_link),
                style = MaterialTheme.typography.bodyLarge,
                color = colors.accent,
                modifier = Modifier.clickable { guideOpen = true }.padding(vertical = 4.dp),
            )
            for ((code, list) in ReadingLibrary.sections(entries, language, appLanguage)) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(languageName(code), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = colors.secondaryText, modifier = Modifier.semantics { heading() })
                    Column(Modifier.clip(RoundedCornerShape(16.dp)).background(colors.surface).padding(horizontal = 16.dp, vertical = 6.dp)) {
                        list.forEachIndexed { index, entry ->
                            if (index > 0) HorizontalDivider(color = colors.separator)
                            val bible = installedBibles.firstOrNull { it.id == entry.id }
                            BibleCard(
                                entry = entry,
                                item = offered[entry.id],
                                translation = translations[entry.id],
                                isCurrent = entry.id == currentBible,
                                isDownloading = entry.id in downloading,
                                booksDone = bookProgress[entry.id],
                                savedBooks = savedChanges.let { offered[entry.id]?.takeIf { it.isYouVersion && entry.id !in downloading && entry.id !in downloads }?.let { library.savedBookCount(it) } ?: 0 },
                                toolsBible = offered[entry.id]?.takeIf { it.isYouVersion }?.let { toolsBibleName(it.baseLanguage, catalog, translations) },
                                onDiscard = { offered[entry.id]?.let { library.discard(it) } },
                                onPause = { library.pause(entry.id) },
                                onRead = bible?.let { { onRead(it) } },
                                onDownload = { offered[entry.id]?.let { item -> library.start(item, Entitlements.isPremium) } },
                                onRemove = if (entry.id in downloads) ({ removing = entry.id to entry.name }) else null,
                            )
                        }
                    }
                    Text(stringResource(R.string.most_read_first), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                }
            }
            if (!tried) CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
            else if (!loaded) Text(stringResource(R.string.connect_to_see_more_bibles), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
            Text(stringResource(R.string.bibles_rights_footer), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
            problem?.let { Text(stringResource(it.message), color = Color(0xFFC2410C)) }
        }
    }
    removing?.let { (id, name) ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text(stringResource(R.string.remove_pack_title, name)) },
            text = { Text(stringResource(R.string.remove_bible_message)) },
            confirmButton = { TextButton(onClick = { library.remove(id); removing = null }) { Text(stringResource(R.string.remove), color = Color(0xFFB3261E)) } },
            dismissButton = { TextButton(onClick = { removing = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

/**
 * The Bible Premium tools read beside a YouVersion one, by name: a free Bible
 * in its language (the Reina-Valera for Spanish, even while it's still to
 * come), else the King James Version.
 */
internal fun toolsBibleName(language: String, catalog: List<DownloadableBible>, installed: Map<String, Translation>): String =
    installed.values.firstOrNull { !it.isYouVersion && !it.showsLicenseUnderChapters && it.language.substringBefore('-') == language }?.name
        ?: installed.values.firstOrNull { it.id == "BLIVRE" && language == "pt" }?.name
        ?: catalog.firstOrNull { !it.isYouVersion && !it.premium && it.rights == "public_domain" && it.baseLanguage == language }?.name
        ?: "King James Version"

/** The bundled Bibles' places in "most read" (the catalog's popularity for downloads). */
private val builtInPopularity = mapOf("KJV" to 1, "BLIVRE" to 3, "WEB" to 4, "ASV" to 6)

@Composable
private fun LanguageMenu(language: String, languages: List<String>, onChoose: (String) -> Unit) {
    val colors = LocalReaderColors.current
    var open by remember { mutableStateOf(false) }
    Box {
        Text(
            (if (language == ReadingLibrary.ALL_LANGUAGES) stringResource(R.string.all_languages) else languageName(language)) + "  ▾",
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold,
            color = colors.accent,
            modifier = Modifier.clip(RoundedCornerShape(10.dp)).border(1.dp, colors.accent, RoundedCornerShape(10.dp)).clickable { open = true }.padding(horizontal = 12.dp, vertical = 7.dp),
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for (code in languages) DropdownMenuItem(text = { Text(languageName(code)) }, onClick = { open = false; onChoose(code) })
            HorizontalDivider()
            DropdownMenuItem(text = { Text(stringResource(R.string.all_languages)) }, onClick = { open = false; onChoose(ReadingLibrary.ALL_LANGUAGES) })
        }
    }
}

/** A language's own name ("Español", "Português"), as AppLanguage.displayName on iOS. */
internal fun languageName(code: String): String {
    val locale = Locale.forLanguageTag(code)
    return locale.getDisplayLanguage(locale).replaceFirstChar { it.uppercase(locale) }
}

@Composable
private fun BibleCard(
    entry: ReadingLibrary.Entry,
    item: DownloadableBible?,
    translation: Translation?,
    isCurrent: Boolean,
    isDownloading: Boolean,
    booksDone: Int?,
    savedBooks: Int,
    toolsBible: String?,
    onDiscard: () -> Unit,
    onPause: () -> Unit,
    onRead: (() -> Unit)?,
    onDownload: () -> Unit,
    onRemove: (() -> Unit)?,
) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val locked = item?.premium == true && !Entitlements.isPremium
    Column(Modifier.padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(entry.name, style = MaterialTheme.typography.titleMedium, color = colors.text)
                val parts = buildList {
                    add(translation?.abbreviation ?: entry.id)
                    (translation?.year ?: item?.year)?.takeIf { it.isNotEmpty() }?.let(::add)
                    if (entry.language.contains('-')) add(regionalName(entry.language))
                    when {
                        isCurrent -> add(stringResource(R.string.reading_now))
                        onRead != null -> add(stringResource(R.string.on_this_device))
                        item != null && item.fileBytes > 0 -> add(Formatter.formatShortFileSize(context, item.fileBytes))
                    }
                }
                Text(parts.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                val total = com.genesis.core.domain.bible.YouVersionBuild.BOOK_CODES.size.toLong()
                if (isDownloading && booksDone != null) {
                    Text(stringResource(R.string.downloading_books, booksDone.toLong(), total), style = MaterialTheme.typography.bodySmall, color = colors.accent)
                    androidx.compose.material3.LinearProgressIndicator(
                        progress = { booksDone / total.toFloat() },
                        color = colors.accent,
                        trackColor = colors.separator,
                        modifier = Modifier.fillMaxWidth().padding(top = 4.dp, end = 12.dp),
                    )
                } else if (!isDownloading && savedBooks > 0 && onRead == null) {
                    Text(stringResource(R.string.paused_books, savedBooks.toLong(), total), style = MaterialTheme.typography.bodySmall, color = colors.accent)
                }
            }
            when {
                // A YouVersion Bible comes book by book, so it can pause and carry on later.
                isDownloading && item?.isYouVersion == true -> Pill(stringResource(R.string.pause), onPause)
                isDownloading -> CircularProgressIndicator(color = colors.accent, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
                savedBooks > 0 && onRead == null -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.discard), style = MaterialTheme.typography.labelLarge, color = colors.secondaryText, modifier = Modifier.clickable(onClick = onDiscard).padding(4.dp))
                    Pill(stringResource(R.string.continue_download), onDownload)
                }
                onRead != null && !isCurrent -> Pill(stringResource(R.string.read_action), onRead)
                onRead != null -> Text("✓", style = MaterialTheme.typography.titleMedium, color = colors.accent)
                locked -> Pill("🔒 " + stringResource(R.string.premium)) {}
                else -> Pill("↓ " + stringResource(R.string.download), onDownload)
            }
        }
        item?.summary?.takeIf { it.isNotEmpty() }?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText) }
        if (toolsBible != null) {
            Text("🎁 " + stringResource(R.string.always_free), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.accent)
            Text(stringResource(R.string.youversion_card_note, toolsBible), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        }
        if (onRemove != null && !isCurrent) {
            Text(
                stringResource(R.string.remove_from_device),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = colors.accent,
                modifier = Modifier.clickable(onClick = onRemove).padding(vertical = 4.dp),
            )
        }
    }
}

/** "Português (Portugal)", as AppLanguage.regionalName on iOS. */
private fun regionalName(code: String): String {
    val locale = Locale.forLanguageTag(code)
    return locale.getDisplayName(locale).replaceFirstChar { it.uppercase(locale) }
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

private val BibleDownloadProblem.message: Int
    get() = when (this) {
        BibleDownloadProblem.NOT_CONFIGURED -> R.string.study_error_not_configured
        BibleDownloadProblem.OFFLINE -> R.string.offline_download_bibles
        BibleDownloadProblem.DAMAGED -> R.string.study_error_damaged
        BibleDownloadProblem.NOT_A_BIBLE -> R.string.not_a_bible
        BibleDownloadProblem.NEEDS_PREMIUM -> R.string.bible_needs_premium
        BibleDownloadProblem.BUSY -> R.string.bibles_busy
    }
