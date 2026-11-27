package com.genesis.app.reader

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.genesis.core.bible.BibleRepository
import com.genesis.core.bible.BundledBible
import com.genesis.core.bible.Chapter
import com.genesis.core.bible.Translation
import com.genesis.core.domain.bible.ChapterId
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
)

class ReaderViewModel(application: Application) : AndroidViewModel(application) {
    private val repositories = mutableMapOf<BundledBible, BibleRepository>()
    private val _state = MutableStateFlow(ReaderUiState(bible = BundledBible.default(Locale.getDefault().language)))
    val state: StateFlow<ReaderUiState> = _state.asStateFlow()

    init {
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

    fun open(chapterId: ChapterId) {
        _state.update { it.copy(chapterId = chapterId) }
        load()
    }

    fun choose(bible: BundledBible) {
        _state.update { it.copy(bible = bible) }
        load()
    }

    fun next() = state.value.chapterId.next?.let(::open)
    fun previous() = state.value.chapterId.previous?.let(::open)

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
