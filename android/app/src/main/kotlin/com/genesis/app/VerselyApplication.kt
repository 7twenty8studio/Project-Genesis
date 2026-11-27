package com.genesis.app

import android.app.Application
import com.genesis.app.settings.ReaderSettingsStore
import com.genesis.app.settings.ReadingProgressStore
import com.genesis.core.data.UserDatabase

/** The app process. Dependency injection (Hilt) arrives with accounts and sync. */
class VerselyApplication : Application() {
    val readerSettings: ReaderSettingsStore by lazy { ReaderSettingsStore(this) }

    /** Opened off the main thread the first time (it reads the person's highlights). */
    val userData: UserDatabase by lazy { UserDatabase.open(this) }
    val progress: ReadingProgressStore by lazy { ReadingProgressStore(this) }
}
