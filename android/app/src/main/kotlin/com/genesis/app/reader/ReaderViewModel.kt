package com.genesis.app.reader

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.genesis.core.bible.BibleRepository
import com.genesis.core.bible.BundledBible
import com.genesis.core.bible.Chapter
import com.genesis.core.bible.Translation
import com.genesis.app.VerselyApplication
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.study.HighlightColor
import com.genesis.core.domain.study.ShareText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

/** What the reader shows. One immutable state; events go up, state comes down. */
data class ReaderUiState(
    val chapterId: ChapterId = ChapterId.john1,
    val bible: BundledBible = BundledBible.KJV,
    val chapter: Chapter? = null,
    val translations: List<Pair<BundledBible, Translation>> = emptyList(),
    /** True when the chapter couldn't be read; the reader says so instead of closing. */
    val failed: Boolean = false,
    /** Paged reading opens a chapter on its last page when going back into it. */
    val openAtEnd: Boolean = false,
    /** The verses the person has tapped, for highlighting, copying and sharing. */
    val selection: Set<VerseId> = emptySet(),
    /** Every highlight, by verse. */
    val highlights: Map<VerseId, HighlightColor> = emptyMap(),
) {
    /** The selected verses as text to copy or share, verbatim with the reference. */
    val shareText: String
        get() {
            val chapter = chapter ?: return ""
            val verses = chapter.verses.filter { it.id in selection }.map { it.id to it.text }
            return ShareText.of(verses, chapter.translation.abbreviation, chapter.translation.language)
        }

    /** The selection's reference, as the selection bar shows it. */
    val selectionReference: String
        get() {
            val sorted = selection.sortedBy { it.rawValue }.ifEmpty { return "" }
            return ReferenceParser.describe(sorted.first().rawValue, sorted.last().rawValue, chapter?.translation?.language ?: "en")
        }
}

class ReaderViewModel(application: Application) : AndroidViewModel(application) {
    private val repositories = mutableMapOf<BundledBible, BibleRepository>()
    private val _state = MutableStateFlow(ReaderUiState(bible = BundledBible.default(Locale.getDefault().language)))
    val state: StateFlow<ReaderUiState> = _state.asStateFlow()

    private val app = application as VerselyApplication

    init {
        viewModelScope.launch {
            val highlights = withContext(Dispatchers.IO) { app.userData.highlights }
            highlights.all.collect { all -> _state.update { it.copy(highlights = all) } }
        }
        viewModelScope.launch {
            val translations = withContext(Dispatchers.IO) {
                BundledBible.entries.mapNotNull { bible ->
                    runCatching { bible to repository(bible).translation }
                        .onFailure { Log.e(TAG, "Couldn't open ${bible.asset}", it) }
                        .getOrNull()
                }
            }
            _state.update { it.copy(translations = translations) }
            load()
        }
    }

    fun open(chapterId: ChapterId, atEnd: Boolean = false) {
        _state.update { it.copy(chapterId = chapterId, openAtEnd = atEnd, selection = emptySet()) }
        load()
    }

    fun choose(bible: BundledBible) {
        _state.update { it.copy(bible = bible) }
        load()
    }

    fun next() = state.value.chapterId.next?.let { open(it) }
    fun previous(atEnd: Boolean = false) = state.value.chapterId.previous?.let { open(it, atEnd) }

    /** A tap on a verse selects it, or lets it go if it was selected. */
    fun toggle(verse: VerseId) = _state.update {
        it.copy(selection = if (verse in it.selection) it.selection - verse else it.selection + verse)
    }

    fun clearSelection() = _state.update { it.copy(selection = emptySet()) }

    fun highlight(color: HighlightColor) {
        val verses = state.value.selection
        if (verses.isEmpty()) return
        app.readerSettings.used(color)
        viewModelScope.launch(Dispatchers.IO) { app.userData.highlights.set(verses, color) }
        clearSelection()
    }

    fun removeHighlight() {
        val verses = state.value.selection
        viewModelScope.launch(Dispatchers.IO) { app.userData.highlights.remove(verses) }
        clearSelection()
    }

    private fun load() {
        val (id, bible) = state.value.let { it.chapterId to it.bible }
        viewModelScope.launch {
            val chapter = withContext(Dispatchers.IO) {
                runCatching { repository(bible).chapter(id) }
                    .onFailure { Log.e(TAG, "Couldn't read $id from ${bible.asset}", it) }
                    .getOrNull()
            }
            _state.update {
                if (it.chapterId == id && it.bible == bible) it.copy(chapter = chapter, failed = chapter == null) else it
            }
        }
    }

    private fun repository(bible: BundledBible): BibleRepository = synchronized(repositories) {
        repositories.getOrPut(bible) { BibleRepository.open(getApplication(), bible) }
    }

    private companion object {
        const val TAG = "Reader"
    }

    override fun onCleared() {
        synchronized(repositories) { repositories.values.forEach { it.close() } }
    }
}
