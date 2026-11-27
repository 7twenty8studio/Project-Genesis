package com.genesis.app

import android.app.Application
import com.genesis.app.settings.ReaderSettingsStore

/** The app process. Dependency injection (Hilt) arrives with accounts and sync. */
class VerselyApplication : Application() {
    val readerSettings: ReaderSettingsStore by lazy { ReaderSettingsStore(this) }
}
