package com.genesis.app

import androidx.activity.compose.BackHandler
import com.genesis.app.insights.InsightsScreen
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.genesis.app.home.HomeScreen
import com.genesis.app.onboarding.OnboardingFlow
import androidx.compose.ui.platform.LocalContext
import com.genesis.app.library.LibraryScreen
import com.genesis.app.library.LibraryShelf
import com.genesis.app.plans.PlansFlow
import com.genesis.app.prayer.JournalBible
import com.genesis.app.sermons.SermonNotesFlow
import com.genesis.app.churchsermons.ChurchSermonContext
import com.genesis.app.churchsermons.ChurchSermonScreen
import com.genesis.app.memorise.MemoriseScreen
import com.genesis.app.memorise.MemoryTexts
import com.genesis.app.prayer.PrayerJournalFlow
import com.genesis.app.account.AccountScreen
import com.genesis.app.reader.CrossReferencesSheet
import com.genesis.core.domain.link.GenesisLink
import com.genesis.app.features.shows
import com.genesis.core.domain.features.OptionalFeature
import com.genesis.app.reader.NoteEditorSheet
import com.genesis.app.reader.ReaderRoute
import com.genesis.app.reader.ReaderViewModel
import com.genesis.app.reader.SearchSheet
import com.genesis.app.reader.ReaderSettingsSheet
import com.genesis.app.settings.SettingsScreen
import com.genesis.app.notifications.NotificationSettingsScreen
import com.genesis.app.explore.ExploreScreen
import androidx.compose.runtime.produceState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import androidx.compose.foundation.layout.navigationBarsPadding
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.scriptureStyle
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.reader.ReaderPreferences
import com.genesis.app.together.TogetherScreen

/** The phone's tabs, as on iPhone. Together shows only while groups are switched on. */
enum class AppTab { HOME, READ, LIBRARY, EXPLORE, TOGETHER }

/**
 * The app's frame: Home, Read and Library in a bottom bar, with search and
 * the note editor over any of them. One reader model serves all three, so a
 * highlight made in the reader shows on Home at once.
 */
@Composable
fun AppShell(
    onChangeSettings: ((ReaderPreferences) -> ReaderPreferences) -> Unit,
    link: GenesisLink? = null,
    onLinkHandled: () -> Unit = {},
) {
    val reader: ReaderViewModel = viewModel()
    val state by reader.state.collectAsStateWithLifecycle()
    val app = LocalContext.current.applicationContext as VerselyApplication
    val onboarded by app.readerSettings.onboardingComplete.collectAsStateWithLifecycle()
    val search by reader.search.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    var tab by rememberSaveable { mutableStateOf(AppTab.HOME) }
    val tabStates = androidx.compose.runtime.saveable.rememberSaveableStateHolder()
    var shelf by rememberSaveable { mutableStateOf(LibraryShelf.HIGHLIGHTS) }
    var searching by rememberSaveable { mutableStateOf(false) }
    var settingsOpen by rememberSaveable { mutableStateOf(false) }
    var readingSettings by rememberSaveable { mutableStateOf(false) }
    var notificationsOpen by rememberSaveable { mutableStateOf(false) }
    var insightsOpen by rememberSaveable { mutableStateOf(false) }
    var yearOpen by rememberSaveable { mutableStateOf(false) }
    var goalsOpen by rememberSaveable { mutableStateOf(false) }
    var featuresOpen by rememberSaveable { mutableStateOf(false) }
    val readingRecord by app.progress.record.collectAsStateWithLifecycle()
    var accountOpen by rememberSaveable { mutableStateOf(false) }
    // Reading plans over the tabs: the list, or one plan (its id).
    var plansOpen by rememberSaveable { mutableStateOf(false) }
    var planToOpen by rememberSaveable { mutableStateOf<String?>(null) }
    val plans by app.userData.plans.all.collectAsStateWithLifecycle()
    var journalOpen by rememberSaveable { mutableStateOf(false) }
    var memoriseOpen by rememberSaveable { mutableStateOf(false) }
    var sermonsOpen by rememberSaveable { mutableStateOf(false) }
    var studyLibraryOpen by rememberSaveable { mutableStateOf(false) }
    var biblesOpen by rememberSaveable { mutableStateOf(false) }
    var feedbackOpen by rememberSaveable { mutableStateOf(false) }
    var settingsAmbient by rememberSaveable { mutableStateOf(false) }
    var groupToOpen by rememberSaveable { mutableStateOf<String?>(null) }
    var sermonsNew by rememberSaveable { mutableStateOf(false) }
    // A church sermon over any tab (its link's slug), and notes opened from it.
    var churchSermon by rememberSaveable { mutableStateOf<String?>(null) }
    var sermonNotesId by rememberSaveable { mutableStateOf<String?>(null) }
    val memoryVerses by app.userData.memory.all.collectAsStateWithLifecycle()
    val prayers by app.userData.prayers.all.collectAsStateWithLifecycle()
    val account by app.account.state.collectAsStateWithLifecycle()
    val syncState by app.sync.state.collectAsStateWithLifecycle()
    val flags by app.flags.values.collectAsStateWithLifecycle()
    val features by app.features.enabled.collectAsStateWithLifecycle()
    // Explore and Together show only when chosen (Settings › Features); Together also needs its server switch.
    val tabs = AppTab.entries.filter {
        when (it) {
            AppTab.EXPLORE -> features.shows(OptionalFeature.EXPLORE, flags)
            AppTab.TOGETHER -> flags[FeatureFlags.GROUPS] == true && features.shows(OptionalFeature.TOGETHER, flags)
            else -> true
        }
    }
    LaunchedEffect(tabs) { if (tab !in tabs) tab = AppTab.HOME }

    fun read(verse: VerseId) {
        reader.openVerse(verse)
        tab = AppTab.READ
    }

    // The Premium morning welcome: the first open each day (skipped, and counted, when a link opened Versely).
    var welcomeShown by rememberSaveable { mutableStateOf(false) }
    var welcomePreview by rememberSaveable { mutableStateOf(false) }
    var welcomeSettingsOpen by rememberSaveable { mutableStateOf(false) }
    androidx.lifecycle.compose.LifecycleResumeEffect(Unit) {
        if (link != null) app.welcome.markShown()
        else if (app.welcome.shouldShow(com.genesis.app.settings.Entitlements.isPremium)) welcomeShown = true
        onPauseOrDispose {}
    }
    if (welcomeShown || welcomePreview) {
        val preview = welcomePreview
        com.genesis.app.welcome.MorningWelcomeScreen(
            reader = reader,
            plans = plans,
            signInName = account.user?.name,
            isPreview = preview,
            onReadChapter = { read(it.firstVerse) },
            onContinue = { settingsOpen = false; tab = AppTab.READ },
            onClose = { if (preview) welcomePreview = false else welcomeShown = false },
        )
        return
    }

    // A versely:// link (a widget tap) opens its place over whatever was showing.
    LaunchedEffect(link) {
        when (link) {
            is GenesisLink.Read -> {
                settingsOpen = false
                read(link.verse)
            }
            GenesisLink.ContinueReading -> {
                settingsOpen = false
                tab = AppTab.READ
            }
            GenesisLink.Home -> {
                settingsOpen = false
                tab = AppTab.HOME
            }
            GenesisLink.Plans -> {
                settingsOpen = false
                journalOpen = false
                planToOpen = null
                plansOpen = true
            }
            GenesisLink.Prayer -> {
                settingsOpen = false
                plansOpen = false
                journalOpen = true
            }
            is GenesisLink.Group -> {
                settingsOpen = false
                groupToOpen = link.id
                tab = AppTab.TOGETHER
            }
            GenesisLink.Memorise -> {
                settingsOpen = false
                plansOpen = false
                journalOpen = false
                memoriseOpen = true
            }
            GenesisLink.Sermons -> {
                settingsOpen = false
                sermonsNew = false
                sermonsOpen = true
            }
            GenesisLink.Insights -> {
                settingsOpen = false
                insightsOpen = true
            }
            is GenesisLink.Sermon -> {
                settingsOpen = false
                sermonNotesId = null
                churchSermon = link.slug
            }
            null -> return@LaunchedEffect
        }
        onLinkHandled()
    }

    // First launch: setup, then the reader at the chosen Bible and chapter.
    // Someone who has already read (an earlier build) isn't sent through it.
    if (!onboarded && app.progress.position.value == null) {
        OnboardingFlow(state.translations) { bible, chapter ->
            reader.begin(bible, chapter)
            app.readerSettings.completeOnboarding()
            tab = AppTab.READ
        }
        return
    }

    // Back from Read or Library goes Home before it leaves the app.
    BackHandler(enabled = tab != AppTab.HOME && !settingsOpen) { tab = AppTab.HOME }
    BackHandler(enabled = settingsOpen && !accountOpen) { settingsOpen = false }
    BackHandler(enabled = accountOpen) { accountOpen = false }
    BackHandler(enabled = plansOpen) { plansOpen = false }

    if (journalOpen) {
        // Before the journal, so the editor's own back (save and close) comes first.
        BackHandler { journalOpen = false }
        val translation = state.chapter?.translation
        PrayerJournalFlow(
            store = app.userData.prayers,
            bible = JournalBible(
                key = state.bible,
                language = translation?.language ?: "en",
                abbreviation = translation?.abbreviation ?: state.bible.id,
                verses = reader::verses,
            ),
            onDone = { journalOpen = false },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        return
    }

    val translationNow = state.chapter?.translation
    val churchContext = ChurchSermonContext(
        api = app.community.sermons,
        hidden = app.hiddenChurches,
        sermons = app.userData.sermons,
        currentBible = state.bible.id,
        bibles = state.translations.map { it.first.id }.ifEmpty { listOf(state.bible.id) },
        language = translationNow?.language ?: "en",
        isSignedIn = account.user != null,
        isAvailable = features.shows(OptionalFeature.CHURCH_SERMONS, flags),
        passage = reader::churchPassage,
        onRead = { verse ->
            churchSermon = null
            sermonNotesId = null
            sermonsOpen = false
            read(verse)
        },
        onOpenNotes = { sermonNotesId = it },
        onSignIn = {
            churchSermon = null
            settingsOpen = true
            accountOpen = true
        },
    )

    if (sermonNotesId != null) {
        BackHandler { sermonNotesId = null }
        SermonNotesFlow(
            store = app.userData.sermons,
            bible = JournalBible(
                key = state.bible,
                language = translationNow?.language ?: "en",
                abbreviation = translationNow?.abbreviation ?: state.bible.id,
                verses = reader::verses,
            ),
            startNew = false,
            openId = sermonNotesId,
            church = churchContext,
            onDone = { sermonNotesId = null },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        return
    }

    churchSermon?.let { slug ->
        ChurchSermonScreen(slug, churchContext, onDone = { churchSermon = null }, modifier = Modifier.fillMaxSize().navigationBarsPadding())
        return
    }

    if (biblesOpen) {
        com.genesis.app.bibles.BiblesScreen(
            currentBible = state.bible.id,
            onRead = { bible -> biblesOpen = false; reader.choose(bible); tab = AppTab.READ },
            onDone = { biblesOpen = false },
            modifier = Modifier.fillMaxSize(),
        )
        return
    }

    if (studyLibraryOpen) {
        com.genesis.app.studylibrary.StudyFlow(
            com.genesis.app.studylibrary.StudyPlace.Library,
            reader,
            onDone = { studyLibraryOpen = false },
            onOpenVerse = { studyLibraryOpen = false; read(it) },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        return
    }

    if (sermonsOpen) {
        // Before the notes, so the editor's own back (save and close) comes first.
        BackHandler { sermonsOpen = false }
        val translation = state.chapter?.translation
        SermonNotesFlow(
            store = app.userData.sermons,
            bible = JournalBible(
                key = state.bible,
                language = translation?.language ?: "en",
                abbreviation = translation?.abbreviation ?: state.bible.id,
                verses = reader::verses,
            ),
            startNew = sermonsNew,
            church = churchContext,
            onDone = { sermonsOpen = false },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        return
    }

    if (memoriseOpen) {
        val translation = state.chapter?.translation
        MemoriseScreen(
            store = app.userData.memory,
            texts = MemoryTexts(
                bibleId = reader.premiumToolsBible().id,
                language = translation?.language ?: "en",
                passage = { verse, nearby -> reader.memoryPassage(verse.translationId, verse.start, verse.end, nearby) },
                hasVerse = reader::hasVerse,
            ),
            onDone = { memoriseOpen = false },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        return
    }

    if (plansOpen) {
        PlansFlow(
            store = app.userData.plans,
            openPlanId = planToOpen,
            onRead = {
                plansOpen = false
                read(it.firstVerse)
            },
            onDone = { plansOpen = false },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        return
    }

    if (yearOpen) {
        com.genesis.app.insights.YearInReviewScreen(
            year = com.genesis.core.domain.insights.YearInReview.reviewedYear(),
            language = state.chapter?.translation?.language ?: "en",
            onDone = { yearOpen = false },
        )
        return
    }

    if (insightsOpen) {
        InsightsScreen(
            language = state.chapter?.translation?.language ?: "en",
            onDone = { insightsOpen = false },
            onYearInReview = { yearOpen = true },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        return
    }

    if (featuresOpen) {
        BackHandler { featuresOpen = false }
        com.genesis.app.features.FeaturesScreen(onDone = { featuresOpen = false }, modifier = Modifier.fillMaxSize().navigationBarsPadding())
        return
    }

    if (goalsOpen) {
        BackHandler { goalsOpen = false }
        com.genesis.app.goals.GoalsScreen(
            onDone = { goalsOpen = false },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        return
    }

    if (notificationsOpen) {
        NotificationSettingsScreen(
            onDone = { notificationsOpen = false },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        return
    }

    if (accountOpen) {
        AccountScreen(
            account = app.account,
            state = account,
            sync = app.sync,
            syncState = syncState,
            onDone = { accountOpen = false },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        return
    }

    if (feedbackOpen) {
        androidx.activity.compose.BackHandler { feedbackOpen = false }
        com.genesis.app.settings.FeedbackScreen(
            readingContext = "${state.bible.id} ${state.chapterId.description("en")}",
            onDone = { feedbackOpen = false },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        return
    }

    if (welcomeSettingsOpen) {
        androidx.activity.compose.BackHandler { welcomeSettingsOpen = false }
        com.genesis.app.welcome.MorningWelcomeSettingsScreen(
            showsAmbient = features.shows(OptionalFeature.AMBIENT_SOUNDS, flags),
            onPreview = { welcomePreview = true },
            onDone = { welcomeSettingsOpen = false },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        return
    }

    if (settingsOpen) {
        val offersYouVersion = app.bibles.catalog.collectAsStateWithLifecycle().value.any { it.isYouVersion }
        SettingsScreen(
            accountTitle = account.user?.let { it.email ?: it.name },
            onAccount = { accountOpen = true },
            onReading = { readingSettings = true },
            onNotifications = { notificationsOpen = true },
            onGoals = { goalsOpen = true },
            onFeatures = { featuresOpen = true },
            showsGoals = features.shows(OptionalFeature.GOALS, flags),
            onBibles = { biblesOpen = true },
            onFeedback = { feedbackOpen = true },
            showsListening = features.shows(OptionalFeature.LISTEN, flags),
            onAmbient = if (features.shows(OptionalFeature.AMBIENT_SOUNDS, flags)) ({ settingsAmbient = true }) else null,
            offersYouVersionBibles = offersYouVersion,
            onMorningWelcome = { welcomeSettingsOpen = true },
            onDone = { settingsOpen = false },
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
        if (readingSettings) {
            ReaderSettingsSheet(
                preferences = com.genesis.app.settings.LocalChosenReaderPreferences.current,
                onChange = onChangeSettings,
                onDismiss = { readingSettings = false },
            )
        }
        if (settingsAmbient) com.genesis.app.audio.AmbientSoundsSheet(app.ambient) { settingsAmbient = false }
        return
    }

    Scaffold(
        containerColor = colors.background,
        bottomBar = {
            // In the reader the tab bar comes and goes with the controls (iOS), over the page.
            val readerState by reader.state.collectAsStateWithLifecycle()
            androidx.compose.animation.AnimatedVisibility(
                visible = tab != AppTab.READ || (readerState.showsControls && readerState.selection.isEmpty()),
                enter = androidx.compose.animation.fadeIn(androidx.compose.animation.core.tween(150)),
                exit = androidx.compose.animation.fadeOut(androidx.compose.animation.core.tween(120)),
            ) {
            NavigationBar(containerColor = if (tab == AppTab.READ) colors.surface.copy(alpha = 0.94f) else colors.surface) {
                for (item in tabs) {
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
            }
        },
    ) { padding ->
        val content = Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)
        // Each tab keeps where it was (an open group, an Explore page) while another tab is shown.
        tabStates.SaveableStateProvider(tab.name) { when (tab) {
            AppTab.HOME -> androidx.compose.foundation.layout.Box(content) { HomeScreen(
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
                plans = plans,
                onPlans = {
                    planToOpen = it
                    plansOpen = true
                },
                onReadChapter = { read(it.firstVerse) },
                onMarkPlanDay = { enrollment, day, done ->
                    if (done && day !in enrollment.completedDays) {
                        com.genesis.app.moments.ChapterMoments.planDayCompleted(app, day, enrollment.id, com.genesis.app.moments.ChapterMoments.Place.HOME)
                    }
                    app.userData.plans.setDay(day, done, enrollment.id)
                },
                greetingName = account.user?.let { user ->
                    val welcomeName = app.welcome.settings.collectAsStateWithLifecycle().value.name
                    com.genesis.core.domain.welcome.MorningWelcomeRules.firstName(welcomeName)
                        ?: com.genesis.core.domain.welcome.MorningWelcomeRules.firstName(user.name)
                },
                activePrayers = prayers.count { it.hasContent && !it.isAnswered },
                onPrayerJournal = { journalOpen = true },
                memorise = memoryVerses.size to memoryVerses.count { it.isDue() },
                onMemorise = { memoriseOpen = true },
                onSermons = {
                    sermonsNew = true
                    sermonsOpen = true
                },
                record = readingRecord,
                onInsights = { insightsOpen = true },
                onYearInReview = { yearOpen = true },
                onGoals = { goalsOpen = true },
                modifier = Modifier.fillMaxSize(),
            )
                // Drawn edge to edge, so the ribbon hangs from the very top.
                com.genesis.app.moments.ChapterMomentOverlay(com.genesis.app.moments.ChapterMoments.Place.HOME, language = com.genesis.app.plans.appLanguage())
            }
            // The reader reads edge to edge, under the status bar and the tab bar, and keeps its own insets.
            AppTab.READ -> androidx.compose.foundation.layout.Box(Modifier.fillMaxSize()) {
                ReaderRoute(onChangeSettings = onChangeSettings, onSearchClick = { searching = true }, onMoreBibles = { biblesOpen = true }, viewModel = reader)
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
                onSermons = {
                    sermonsNew = false
                    sermonsOpen = true
                },
                onStudyLibrary = { studyLibraryOpen = true },
                onBibles = { biblesOpen = true },
                modifier = content,
            )
            AppTab.EXPLORE -> {
                val language = LocalContext.current.resources.configuration.locales[0].language
                val study by produceState(app.studyIfOpen(language), language) { value = withContext(Dispatchers.IO) { app.study(language) } }
                val translation = state.chapter?.translation
                ExploreScreen(
                    study = study,
                    bibleLanguage = translation?.language ?: "en",
                    abbreviation = translation?.abbreviation ?: state.bible.id,
                    verses = reader::verses,
                    onRead = ::read,
                    modifier = content,
                )
            }
            AppTab.TOGETHER -> TogetherScreen(
                bible = JournalBible(
                    key = state.bible,
                    language = state.chapter?.translation?.language ?: "en",
                    abbreviation = state.chapter?.translation?.abbreviation ?: state.bible.id,
                    verses = reader::verses,
                ),
                bibleId = state.bible.id,
                onSignIn = { accountOpen = true }, onRead = { read(it.firstVerse) }, modifier = content,
                startGroup = groupToOpen, onStartGroupHandled = { groupToOpen = null },
                onOpenSermon = { churchSermon = it })
        } }
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

    // On a wide screen the reader's study panel shows them beside the text instead.
    val panelShowsRelated = tab == AppTab.READ && androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp >= 800 && state.companionShown(LocalReaderPreferences.current.twoPageSpread)
    state.crossReferences?.takeIf { !panelShowsRelated }?.let { crossReferences ->
        CrossReferencesSheet(
            crossReferences = crossReferences,
            scripture = scriptureStyle(LocalReaderPreferences.current, Entitlements.isPremium),
            onOpen = {
                reader.openCrossReference(it)
                tab = AppTab.READ
            },
            onDismiss = reader::closeCrossReferences,
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
        AppTab.EXPLORE -> R.string.tab_explore
        AppTab.TOGETHER -> R.string.tab_together
    }
