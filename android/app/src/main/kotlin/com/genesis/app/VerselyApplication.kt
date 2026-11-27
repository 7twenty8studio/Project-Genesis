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
    val readerSettings: ReaderSettingsStore by lazy { ReaderSettingsStore(this) }

    /** Opened off the main thread the first time (it reads the person's highlights). */
    val userData: UserDatabase by lazy { UserDatabase.open(this) }
    val progress: ReadingProgressStore by lazy { ReadingProgressStore(this) }

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
        scope.launch {
            val data = withContext(Dispatchers.IO) { userData }
            combine(notifications.state, data.prayers.all, data.plans.all) { _, _, _ -> }
                .debounce(1_500)
                .collect { ReminderScheduler.refresh(this@VerselyApplication) }
        }
    }

    fun refreshReminders() {
        scope.launch { ReminderScheduler.refresh(this@VerselyApplication) }
    }
}
