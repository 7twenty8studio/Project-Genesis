package com.genesis.app

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.genesis.app.home.HomeScreen
import com.genesis.app.library.LibraryScreen
import com.genesis.app.library.LibraryShelf
import com.genesis.app.reader.NoteEditorSheet
import com.genesis.app.reader.ReaderRoute
import com.genesis.app.reader.ReaderViewModel
import com.genesis.app.reader.SearchSheet
import com.genesis.app.reader.ReaderSettingsSheet
import com.genesis.app.settings.SettingsScreen
import androidx.compose.foundation.layout.navigationBarsPadding
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.scriptureStyle
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.reader.ReaderPreferences

/** The phone's tabs, as on iPhone (Explore and Together join later). */
enum class AppTab { HOME, READ, LIBRARY }

/**
 * The app's frame: Home, Read and Library in a bottom bar, with search and
 * the note editor over any of them. One reader model serves all three, so a
 * highlight made in the reader shows on Home at once.
 */
@Composable
fun AppShell(onChangeSettings: ((ReaderPreferences) -> ReaderPreferences) -> Unit) {
    val reader: ReaderViewModel = viewModel()
    val state by reader.state.collectAsStateWithLifecycle()
    val search by reader.search.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    var tab by rememberSaveable { mutableStateOf(AppTab.HOME) }
    var shelf by rememberSaveable { mutableStateOf(LibraryShelf.HIGHLIGHTS) }
    var searching by rememberSaveable { mutableStateOf(false) }
    var settingsOpen by rememberSaveable { mutableStateOf(false) }
    var readingSettings by rememberSaveable { mutableStateOf(false) }

    fun read(verse: VerseId) {
        reader.openVerse(verse)
        tab = AppTab.READ
    }

    // Back from Read or Library goes Home before it leaves the app.
    BackHandler(enabled = tab != AppTab.HOME && !settingsOpen) { tab = AppTab.HOME }
    BackHandler(enabled = settingsOpen) { settingsOpen = false }

    if (settingsOpen) {
        SettingsScreen(
            onReading = { readingSettings = true },
            onDone = { settingsOpen = false },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        if (readingSettings) {
            ReaderSettingsSheet(
                preferences = LocalReaderPreferences.current,
                onChange = onChangeSettings,
                onDismiss = { readingSettings = false },
            )
        }
        return
    }

    Scaffold(
        containerColor = colors.background,
        bottomBar = {
            NavigationBar(containerColor = colors.surface) {
                for (item in AppTab.entries) {
                    NavigationBarItem(
                        selected = tab == item,
                        onClick = { tab = item },
                        icon = { TabIcon(item, if (tab == item) colors.accent else colors.secondaryText) },
                        label = { Text(stringResource(item.title)) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedTextColor = colors.accent,
                            unselectedTextColor = colors.secondaryText,
                            indicatorColor = colors.accent.copy(alpha = 0.14f),
                        ),
                    )
                }
            }
        },
    ) { padding ->
        val content = Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)
        when (tab) {
            AppTab.HOME -> HomeScreen(
                state = state,
                verses = reader::verses,
                onRead = ::read,
                onContinue = { tab = AppTab.READ },
                onSearch = { searching = true },
                onSettings = { settingsOpen = true },
                onOpenNote = reader::openNote,
                onSeeAll = {
                    shelf = it
                    tab = AppTab.LIBRARY
                },
                modifier = content,
            )
            AppTab.READ -> androidx.compose.foundation.layout.Box(content) {
                ReaderRoute(onChangeSettings = onChangeSettings, onSearchClick = { searching = true }, viewModel = reader)
            }
            AppTab.LIBRARY -> LibraryScreen(
                state = state,
                shelf = shelf,
                onShelf = { shelf = it },
                verses = reader::verses,
                onRead = ::read,
                onOpenNote = reader::openNote,
                onNewNote = reader::newNote,
                onSearch = { searching = true },
                modifier = content,
            )
        }
    }

    if (searching) {
        SearchSheet(
            search = search,
            scripture = scriptureStyle(LocalReaderPreferences.current, Entitlements.isPremium),
            onText = reader::search,
            onOpen = {
                searching = false
                read(it)
            },
            onDismiss = { searching = false },
        )
    }

    state.editingNote?.let { note ->
        NoteEditorSheet(
            note = note,
            language = state.chapter?.translation?.language ?: "en",
            onChange = reader::editNote,
            onClose = reader::closeNote,
            onDelete = reader::deleteNote,
        )
    }
}

private val AppTab.title: Int
    get() = when (this) {
        AppTab.HOME -> R.string.tab_home
        AppTab.READ -> R.string.tab_read
        AppTab.LIBRARY -> R.string.tab_library
    }
