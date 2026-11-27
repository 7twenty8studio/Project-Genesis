package com.genesis.app

import android.app.Application
import com.genesis.app.account.AccountService
import com.genesis.app.account.SyncService
import kotlinx.coroutines.MainScope
import com.genesis.app.settings.ReaderSettingsStore
import com.genesis.app.settings.ReadingProgressStore
import com.genesis.core.data.UserDatabase
import com.genesis.core.bible.StudyRepository
import com.genesis.app.notifications.NotificationPreferences
import com.genesis.app.notifications.ReminderScheduler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The app process. Dependency injection (Hilt) arrives with accounts and sync. */
class VerselyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        com.genesis.app.settings.Entitlements.load(this)
    }

    val readerSettings: ReaderSettingsStore by lazy { ReaderSettingsStore(this) }

    /** The Bibles on this phone and those offered for download. */
    val bibles: com.genesis.app.bibles.BibleLibrary by lazy { com.genesis.app.bibles.BibleLibrary(this, account.client, scope) }

    /** The Bible the person reads (the default when theirs is gone). */
    val currentBible: com.genesis.core.bible.InstalledBible get() = bibles.current(readerSettings.currentBible)

    /** Opened off the main thread the first time (it reads the person's highlights). */
    val userData: UserDatabase by lazy { UserDatabase.open(this) }
    val progress: ReadingProgressStore by lazy { ReadingProgressStore(this).also { it.streakShieldsActive = goals.state.value.usesStreakShields } }
    val goals: com.genesis.app.goals.GoalPreferences by lazy { com.genesis.app.goals.GoalPreferences(this) }
    val features: com.genesis.app.features.FeaturePreferences by lazy { com.genesis.app.features.FeaturePreferences(this) { readerSettings.onboardingComplete.value || progress.position.value != null } }

    /** The process's own scope, for work that outlives a screen (sign-in). */
    val scope = MainScope()
    val account: AccountService by lazy { AccountService(this, scope) }

    /** Highlights, notes and bookmarks with the person's account; started by MainActivity. */
    val sync: SyncService by lazy { SyncService(this, userData, account, scope).also { it.start() } }

    /** Explore's people, places and events in the app's language (opened off the main thread). */
    private var studyRepository: Pair<String, StudyRepository?>? = null

    @Synchronized
    fun study(language: String): StudyRepository? {
        studyRepository?.let { (open, repository) -> if (open == language) return repository }
        studyRepository?.second?.close()
        val repository = runCatching { StudyRepository.open(this, language) }.getOrNull()
        studyRepository = language to repository
        return repository
    }

    /** The study database if it's already open in that language (no disk work). */
    fun studyIfOpen(language: String): StudyRepository? = studyRepository?.takeIf { it.first == language }?.second

    /** Hebrew and Greek words, the lexicon and Matthew Henry (WordStudy.sqlite), in the app's language. */
    private var wordStudyRepository: Pair<String, com.genesis.core.bible.WordStudyRepository?>? = null

    /** Opens the word study database (off the main thread: the first open copies it out of the app). */
    @Synchronized
    fun wordStudy(language: String): com.genesis.core.bible.WordStudyRepository? {
        wordStudyRepository?.let { (open, repository) -> if (open == language) return repository }
        wordStudyRepository?.second?.close()
        val repository = runCatching { com.genesis.core.bible.WordStudyRepository.open(this, language) }
            .onFailure { android.util.Log.e("WordStudy", "Couldn't open WordStudy.sqlite", it) }.getOrNull()
        wordStudyRepository = language to repository
        return repository
    }

    /** Says Hebrew and Greek words aloud. */
    val pronouncer: com.genesis.app.original.WordPronouncer by lazy { com.genesis.app.original.WordPronouncer(this) }
    val studyResources: com.genesis.app.studylibrary.StudyResourceLibrary by lazy { com.genesis.app.studylibrary.StudyResourceLibrary(this, account.client) }

    /** The server's switches (groups, community…). */
    val flags: FeatureFlags by lazy { FeatureFlags(this, account.client) }

    /** Churches whose sermons the person hid (on this phone only). */
    val hiddenChurches: com.genesis.app.churchsermons.HiddenChurches by lazy { com.genesis.app.churchsermons.HiddenChurches(this) }

    /** Church groups (Together). */
    val community: com.genesis.app.together.CommunityStore by lazy { com.genesis.app.together.CommunityStore(account, scope) }

    /** Chapters read aloud by the phone's voice. */
    val listening: com.genesis.app.audio.Listening by lazy {
        com.genesis.app.audio.Listening(this, com.genesis.app.audio.ListeningSettings(this))
    }

    /** Ambient sounds to read and pray with (Premium). */
    val welcome: com.genesis.app.welcome.MorningWelcome by lazy { com.genesis.app.welcome.MorningWelcome(this) }
    val ambient: com.genesis.app.audio.AmbientSounds by lazy { com.genesis.app.audio.AmbientSounds(this, listening) }

    /** Settings › Notifications. */
    val notifications: NotificationPreferences by lazy { NotificationPreferences(this) }
    private var remindersFollowed = false

    /**
     * Keeps the week of reminders in step with the settings, prayers and
     * plans (edited here or synced from another device). Started by MainActivity.
     */
    @OptIn(FlowPreview::class)
    fun followReminders() {
        if (remindersFollowed) return
        remindersFollowed = true
        // The Bible catalog: removes downloads that left it, updates old editions on Wi-Fi.
        scope.launch { bibles.refreshCatalog() }
        scope.launch {
            val data = withContext(Dispatchers.IO) { userData }
            // Also the goal and the features shown: a hidden feature's reminders stop.
            val choices = combine(goals.state, features.enabled) { goal, _ -> goal }
            combine(notifications.state, data.prayers.all, data.plans.all, data.memory.all, choices) { _, _, _, _, goal ->
                progress.streakShieldsActive = goal.usesStreakShields
            }
                .debounce(1_500)
                .collect { ReminderScheduler.refresh(this@VerselyApplication) }
        }
        // Every widget follows reading, plan days, prayers and Memorize reviews.
        scope.launch {
            val data = withContext(Dispatchers.IO) { userData }
            combine(progress.record, progress.position, data.prayers.all, data.plans.all, data.memory.all) { _, _, _, _, _ -> }
                .debounce(2_000)
                .collect { com.genesis.app.widget.VerselyWidgets.refresh(this@VerselyApplication) }
        }
    }

    fun refreshReminders() {
        scope.launch { ReminderScheduler.refresh(this@VerselyApplication) }
    }
}
