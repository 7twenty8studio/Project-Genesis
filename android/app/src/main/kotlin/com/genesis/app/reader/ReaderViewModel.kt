package com.genesis.app.reader

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.genesis.core.bible.BibleRepository
import com.genesis.core.bible.BibleSearch
import com.genesis.core.bible.SearchResults
import com.genesis.core.bible.BundledBible
import com.genesis.core.bible.Chapter
import com.genesis.core.bible.CrossReference
import com.genesis.core.bible.CrossReferenceRepository
import com.genesis.core.bible.Translation
import com.genesis.core.bible.Verse
import com.genesis.app.VerselyApplication
import com.genesis.app.widget.VerseOfTheDayWidget
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.study.Bookmarks
import com.genesis.core.domain.study.HighlightColor
import com.genesis.core.domain.study.Note
import com.genesis.core.domain.study.NoteAnchor
import com.genesis.core.domain.study.ShareText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale
import java.util.UUID

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
    /** Every bookmarked verse (one per chapter). */
    val bookmarks: Set<VerseId> = emptySet(),
    /** Every note, newest first. */
    val notes: List<Note> = emptyList(),
    /** The note open in the editor, if any. */
    val editingNote: Note? = null,
    /** A verse to bring into view (from search), once per request. */
    val focus: ReaderFocus? = null,
    /** The last verse read in the reader, or null before the first chapter. */
    val position: VerseId? = null,
    /** The cross references sheet, while it's open. */
    val crossReferences: CrossReferencesUiState? = null,
    /** Original (Hebrew & Greek) is shown beside the Bible being read. */
    val showsOriginal: Boolean = false,
    /** The verse whose word study is open, if any. */
    val wordStudyVerse: VerseId? = null,
    /** The verse whose study notes and commentary are open (the selection bar's Study). */
    val studyVerse: VerseId? = null,
) {
    val hasStartedReading: Boolean get() = position != null

    val isChapterBookmarked: Boolean get() = Bookmarks.isBookmarked(bookmarks, chapterId)

    /** Notes on this chapter's verses, by the verse their mark follows. */
    val notedVerses: Map<VerseId, String>
        get() = notes.mapNotNull { note -> note.markedVerse?.takeIf { it.chapterId == chapterId }?.let { it to note.id } }.toMap()

    /** The note the selection bar's Note opens, if one ends on a selected verse. */
    val selectionNote: Note? get() = Note.forSelection(notes, selection)

    /** The selected verses as text to copy or share, verbatim with the reference. */
    val shareText: String
        get() {
            val chapter = chapter ?: return ""
            val verses = chapter.verses.filter { it.id in selection }.map { it.id to it.plainText }
            return ShareText.of(verses, chapter.translation.abbreviation, chapter.translation.language)
        }

    /** The selection's reference, as the selection bar shows it. */
    val selectionReference: String
        get() {
            val sorted = selection.sortedBy { it.rawValue }.ifEmpty { return "" }
            return ReferenceParser.describe(sorted.first().rawValue, sorted.last().rawValue, chapter?.translation?.language ?: "en")
        }
}

/** A verse the reader brings into view; a new token asks again for the same verse. */
data class ReaderFocus(val verse: VerseId, val token: Long = System.nanoTime())

/** A verse's related passages, strongest links first, each shown verbatim from the Bible being read. */
data class CrossReferencesUiState(
    val verse: VerseId,
    val language: String = "en",
    val sourceText: String = "",
    val items: List<CrossReferenceItem> = emptyList(),
    val loading: Boolean = true,
)

/** One related passage: its first three verses, with "…" when it runs on (as iOS). */
data class CrossReferenceItem(val reference: CrossReference, val title: String, val text: String)

/** What the search sheet shows. */
data class SearchUiState(
    val text: String = "",
    val results: SearchResults = SearchResults(),
    val translationAbbreviation: String = "",
    val language: String = "en",
)

class ReaderViewModel(application: Application) : AndroidViewModel(application) {
    private val repositories = mutableMapOf<BundledBible, BibleRepository>()
    private var crossReferenceOpened = false
    private val crossReferenceRepository by lazy {
        crossReferenceOpened = true
        CrossReferenceRepository.open(getApplication())
    }
    private val app = application as VerselyApplication

    private val _state = MutableStateFlow(
        ReaderUiState(
            bible = app.readerSettings.currentBible?.let { id -> BundledBible.entries.firstOrNull { it.id == id } }
                ?: BundledBible.default(Locale.getDefault().language),
            chapterId = app.progress.position.value?.chapterId ?: ChapterId.john1,
        ),
    )
    val state: StateFlow<ReaderUiState> = _state.asStateFlow()

    private val _search = MutableStateFlow(SearchUiState())
    val search: StateFlow<SearchUiState> = _search.asStateFlow()
    private var searchJob: Job? = null

    init {
        viewModelScope.launch {
            val highlights = withContext(Dispatchers.IO) { app.userData.highlights }
            highlights.all.collect { all -> _state.update { it.copy(highlights = all) } }
        }
        viewModelScope.launch {
            app.progress.position.collect { position -> _state.update { it.copy(position = position) } }
        }
        viewModelScope.launch {
            val bookmarks = withContext(Dispatchers.IO) { app.userData.bookmarks }
            bookmarks.all.collect { all -> _state.update { it.copy(bookmarks = all) } }
        }
        viewModelScope.launch {
            val notes = withContext(Dispatchers.IO) { app.userData.notes }
            notes.all.collect { all -> _state.update { it.copy(notes = all) } }
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
        _state.update { it.copy(chapterId = chapterId, openAtEnd = atEnd, selection = emptySet(), focus = null) }
        load()
    }

    /** Opens a verse's chapter with the verse in view (search results, references). */
    fun openVerse(verse: VerseId) {
        val sameChapter = state.value.chapterId == verse.chapterId
        _state.update { it.copy(chapterId = verse.chapterId, openAtEnd = false, selection = emptySet(), focus = ReaderFocus(verse)) }
        if (!sameChapter) load()
    }

    /** Searches the Bible being read as the person types, after a short pause. */
    fun search(text: String) {
        _search.update { it.copy(text = text) }
        searchJob?.cancel()
        val bible = state.value.bible
        searchJob = viewModelScope.launch {
            if (text.isBlank()) {
                _search.update { it.copy(results = SearchResults()) }
                return@launch
            }
            // A brief pause so fast typists don't search on every keystroke.
            delay(90)
            val found = withContext(Dispatchers.IO) {
                runCatching {
                    val repository = repository(bible)
                    Triple(BibleSearch.run(text, repository), repository.translation.abbreviation, repository.translation.language)
                }.onFailure { Log.e(TAG, "Search failed", it) }.getOrNull()
            } ?: return@launch
            _search.update { it.copy(results = found.first, translationAbbreviation = found.second, language = found.third) }
        }
    }

    fun choose(bible: BundledBible) {
        app.readerSettings.currentBible = bible.id
        viewModelScope.launch { VerseOfTheDayWidget.refresh(getApplication()) }
        _state.update { it.copy(bible = bible) }
        load()
        if (_search.value.text.isNotBlank()) search(_search.value.text)
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

    /** Bookmarks the first selected verse, or takes the chapter's bookmark away. */
    fun toggleBookmark() {
        val verse = state.value.selection.minOrNull() ?: state.value.chapterId.firstVerse
        viewModelScope.launch(Dispatchers.IO) { app.userData.bookmarks.toggle(verse) }
        clearSelection()
    }

    /**
     * Adds the selection to Memorize (Premium), as memoriseSelection on iOS:
     * one chapter, at most 15 verses, in the Bible being read.
     */
    fun memoriseSelection() {
        val selection = state.value.selection.sorted()
        val first = selection.firstOrNull() ?: return
        val last = selection.last().takeIf { it.chapterId == first.chapterId } ?: first
        val max = com.genesis.core.domain.memorise.MemoriseSuggestions.MAXIMUM_VERSES
        val end = if (last.verse - first.verse < max) last else VerseId(first.book, first.chapter, first.verse + max - 1)
        val bible = state.value.bible.id
        viewModelScope.launch(Dispatchers.IO) { app.userData.memory.memorise(first, end, bible) }
        clearSelection()
    }

    /** Opens the selection's note, or a new one on the selected verses. */
    fun openNoteForSelection() {
        val current = state.value
        val sorted = current.selection.sorted().ifEmpty { return }
        val note = current.selectionNote
            ?: Note(id = UUID.randomUUID().toString(), anchor = NoteAnchor.Verses(sorted.first(), sorted.last()))
        _state.update { it.copy(editingNote = note, selection = emptySet()) }
    }

    /** The mark after a verse opens its note. */
    fun openNote(id: String) {
        val note = state.value.notes.firstOrNull { it.id == id } ?: return
        _state.update { it.copy(editingNote = note) }
    }

    /** Keeps the editor's copy current; the note is saved when the editor closes. */
    fun editNote(change: (Note) -> Note) = _state.update { it.copy(editingNote = it.editingNote?.let(change)) }

    /** Saves what was written (an untouched new note leaves nothing behind). */
    fun closeNote() {
        val note = state.value.editingNote ?: return
        _state.update { it.copy(editingNote = null) }
        val saved = state.value.notes.firstOrNull { it.id == note.id }
        viewModelScope.launch(Dispatchers.IO) {
            when {
                saved == null && note.isEmpty -> Unit
                saved == note -> Unit
                else -> app.userData.notes.save(note)
            }
        }
    }

    fun deleteNote() {
        val note = state.value.editingNote ?: return
        _state.update { it.copy(editingNote = null) }
        viewModelScope.launch(Dispatchers.IO) { app.userData.notes.delete(note.id) }
    }

    /** Setup's last step: the chosen Bible, opened at the chosen chapter. */
    fun begin(bible: BundledBible, chapter: ChapterId) {
        app.readerSettings.currentBible = bible.id
        viewModelScope.launch { VerseOfTheDayWidget.refresh(getApplication()) }
        _state.update { it.copy(bible = bible, chapterId = chapter, openAtEnd = false, selection = emptySet(), focus = null) }
        load()
    }

    /** The reader is showing the chapter: remember the place (as ReadingProgress on iOS). */
    fun recordPosition() {
        val current = state.value
        if (current.chapter?.id != current.chapterId) return
        val focus = current.focus?.verse?.takeIf { it.chapterId == current.chapterId }
        app.progress.record(focus ?: current.chapterId.firstVerse)
    }

    /** Verses of the Bible being read, verbatim, for Home's and Library's lists. */
    suspend fun verses(ids: Collection<VerseId>): Map<VerseId, Verse> {
        val bible = state.value.bible
        return withContext(Dispatchers.IO) {
            runCatching { repository(bible).verses(ids) }.onFailure { Log.e(TAG, "Couldn't read verses", it) }.getOrDefault(emptyMap())
        }
    }

    /**
     * A Memorize passage's verses, verbatim, as BibleLibrary.memoryTranslation
     * on iOS: the Bible being read, except that a passage keeps the Bible it
     * was added in while that one is in the same language; the saved Bible
     * when the one being read doesn't have it. `nearby`: two verses either
     * side too, only as decoy words for Fill the Gaps.
     */
    suspend fun memoryPassage(savedBibleId: String, from: VerseId, through: VerseId, nearby: Boolean = false): MemoryPassage? {
        val reading = state.value.bible
        return withContext(Dispatchers.IO) {
            runCatching {
                val saved = BundledBible.entries.firstOrNull { it.id == savedBibleId }
                fun base(bible: BundledBible) = repository(bible).translation.language.substringBefore('-')
                val chosen = if (saved != null && base(saved) == base(reading)) saved else reading
                var bible = chosen
                var verses = repository(chosen).passage(from, through)
                if (verses.isEmpty() && saved != null && saved != chosen) {
                    bible = saved
                    verses = repository(saved).passage(from, through)
                }
                if (verses.isEmpty()) return@runCatching null
                val repository = repository(bible)
                val around = if (nearby) {
                    repository.passage(VerseId(from.rawValue - 2), VerseId(from.rawValue - 1)) + repository.passage(VerseId(through.rawValue + 1), VerseId(through.rawValue + 2))
                } else emptyList()
                MemoryPassage(bible.id, repository.translation.abbreviation, repository.translation.language, verses.map { it.plainText }, around.map { it.plainText })
            }.onFailure { Log.e(TAG, "Couldn't read a Memorize passage", it) }.getOrNull()
        }
    }

    /**
     * A church sermon's passage (KJV numbering) in one Bible on this phone,
     * verbatim, through that Bible's verse map; a chapter's worth at most.
     */
    suspend fun churchPassage(bibleId: String, start: VerseId, end: VerseId): ChurchPassage? {
        val bible = BundledBible.entries.firstOrNull { it.id == bibleId } ?: return null
        return withContext(Dispatchers.IO) {
            runCatching {
                val repository = repository(bible)
                val (first, last) = com.genesis.core.domain.bible.OriginalVersification.parallelMap(bible.id).ownRange(start, end)
                ChurchPassage(bible.id, repository.translation.name, repository.translation.abbreviation, repository.translation.language, repository.passage(first, last, limit = 60))
            }.onFailure { Log.e(TAG, "Couldn't read a sermon passage", it) }.getOrNull()
        }
    }

    /** True when the Bible being read has this verse (Memorize's Add Verse). */
    suspend fun hasVerse(verse: VerseId): Boolean {
        val bible = state.value.bible
        return withContext(Dispatchers.IO) { runCatching { repository(bible).verses(listOf(verse)).isNotEmpty() }.getOrDefault(false) }
    }

    /** Related passages for the first selected verse (the selection bar's Related). */
    fun openCrossReferences() {
        val verse = state.value.selection.minByOrNull { it.rawValue } ?: return
        val bible = state.value.bible
        _state.update { it.copy(crossReferences = CrossReferencesUiState(verse)) }
        viewModelScope.launch {
            val loaded = withContext(Dispatchers.IO) {
                runCatching {
                    val repository = repository(bible)
                    val language = repository.translation.language
                    val items = crossReferenceRepository.references(verse).map { reference ->
                        val passage = repository.passage(reference.target, reference.targetEnd, limit = 4)
                        val text = passage.take(3).joinToString(" ") { it.plainText } + if (passage.size > 3) " \u2026" else ""
                        CrossReferenceItem(reference, reference.description(language), text)
                    }.filter { it.text.isNotEmpty() }
                    val source = repository.verses(listOf(verse))[verse]?.plainText.orEmpty()
                    CrossReferencesUiState(verse, language, source, items, loading = false)
                }.onFailure { Log.e(TAG, "Couldn't read cross references for $verse", it) }.getOrNull()
            }
            _state.update { current ->
                if (current.crossReferences?.verse != verse) current
                else current.copy(crossReferences = loaded ?: current.crossReferences.copy(loading = false))
            }
        }
    }

    fun closeCrossReferences() = _state.update { it.copy(crossReferences = null) }

    /** Opens a related passage in the reader. */
    fun openCrossReference(verse: VerseId) {
        _state.update { it.copy(crossReferences = null) }
        openVerse(verse)
    }

    /** Starts a note that isn't on a passage (Library's New Note). */
    fun newNote() = _state.update { it.copy(editingNote = Note(id = UUID.randomUUID().toString())) }

    /** Shows or leaves the Original (Hebrew & Greek) beside the Bible being read. */
    fun setOriginal(on: Boolean) = _state.update { it.copy(showsOriginal = on, selection = emptySet()) }

    /** Opens word study for the first selected verse. */
    fun openWordStudy() = _state.update { state ->
        state.copy(wordStudyVerse = state.selection.minByOrNull { it.rawValue }, selection = emptySet())
    }

    fun closeWordStudy() = _state.update { it.copy(wordStudyVerse = null) }

    /** Opens the Study Library's notes and commentary for the first selected verse. */
    fun openStudy() = _state.update { state ->
        state.copy(studyVerse = state.selection.minByOrNull { it.rawValue }, selection = emptySet())
    }

    fun closeStudy() = _state.update { it.copy(studyVerse = null) }

    /** Runs [block] with the Bible being read, off the main thread; null if it fails. */
    internal suspend fun <T> withBible(block: (BibleRepository) -> T): T? {
        val bible = state.value.bible
        return withContext(Dispatchers.IO) {
            runCatching { block(repository(bible)) }.onFailure { Log.e(TAG, "Couldn't read ${bible.asset}", it) }.getOrNull()
        }
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
        if (crossReferenceOpened) crossReferenceRepository.close()
    }
}

/** A church sermon's passage as shown, verbatim from one Bible. */
data class ChurchPassage(val bibleId: String, val name: String, val abbreviation: String, val language: String, val verses: List<Verse>)

/** A Memorize passage as shown: each verse's text verbatim, and the Bible it comes from. */
data class MemoryPassage(
    val bibleId: String,
    val abbreviation: String,
    val language: String,
    val verses: List<String>,
    val nearby: List<String> = emptyList(),
) {
    /** The whole passage, the verses joined with a space (as iOS). */
    val text: String get() = verses.joinToString(" ")
}
