package com.genesis.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.app.settings.LocalRecentColors
import com.genesis.core.design.VerselyTheme

class MainActivity : ComponentActivity() {
    override fun attachBaseContext(newBase: android.content.Context) {
        super.attachBaseContext(com.genesis.app.settings.AppLanguageChoice.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val settings = (application as VerselyApplication).readerSettings
        setContent {
            val preferences by settings.preferences.collectAsStateWithLifecycle()
            val recentColors = settings.recentColors.collectAsStateWithLifecycle()
            VerselyTheme(theme = preferences.theme) {
                CompositionLocalProvider(LocalReaderPreferences provides preferences, LocalRecentColors provides recentColors) {
                    AppShell(onChangeSettings = settings::update)
                }
            }
        }
    }
}
