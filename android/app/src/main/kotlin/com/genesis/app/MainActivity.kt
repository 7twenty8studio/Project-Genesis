package com.genesis.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import com.genesis.app.widget.VerseOfTheDayWidget
import com.genesis.core.domain.link.GenesisLink
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.app.settings.LocalRecentColors
import com.genesis.core.design.VerselyTheme

class MainActivity : ComponentActivity() {
    /** A versely:// link to open (a widget tap), until AppShell has acted on it. */
    private val link = MutableStateFlow<GenesisLink?>(null)

    override fun attachBaseContext(newBase: android.content.Context) {
        super.attachBaseContext(com.genesis.app.settings.AppLanguageChoice.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val settings = (application as VerselyApplication).readerSettings
        if (savedInstanceState == null) receive(intent)
        // The widget catches up on a new day, the Bible or the language when the app opens.
        lifecycleScope.launch { VerseOfTheDayWidget.refresh(applicationContext) }
        (application as VerselyApplication).followReminders()
        setContent {
            val preferences by settings.preferences.collectAsStateWithLifecycle()
            val recentColors = settings.recentColors.collectAsStateWithLifecycle()
            VerselyTheme(theme = preferences.theme) {
                CompositionLocalProvider(LocalReaderPreferences provides preferences, LocalRecentColors provides recentColors) {
                    val pending by link.collectAsStateWithLifecycle()
                    AppShell(
                        onChangeSettings = settings::update,
                        link = pending,
                        onLinkHandled = { link.update { null } },
                    )
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        // Catch up with the person's other devices whenever Versely comes back.
        lifecycleScope.launch {
            val app = application as VerselyApplication
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { app.userData }
            app.sync.schedule()
        }
        // A new day, or a change in Android's notification settings.
        (application as VerselyApplication).refreshReminders()
    }

    override fun onStop() {
        super.onStop()
        // Reading today drops today's reading reminder.
        (application as VerselyApplication).refreshReminders()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        receive(intent)
    }

    private fun receive(intent: Intent?) {
        val data = intent?.dataString ?: return
        // versely://auth-callback finishes signing in with Apple or Google.
        if ((application as VerselyApplication).account.handleCallback(data)) return
        GenesisLink.parse(data)?.let { parsed -> link.update { parsed } }
    }
}
