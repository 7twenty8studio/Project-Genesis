package com.genesis.app.original

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.genesis.core.domain.original.OriginalLanguage
import com.genesis.core.domain.original.PronunciationText
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Locale

/**
 * Says a Hebrew or Greek word aloud with the phone's Hebrew or Greek voice
 * (modern pronunciation), a little slowly, as WordPronouncer on iOS. Only
 * the spoken copy is simplified (`PronunciationText`); the word shown never
 * changes. Free and offline once the voice is installed.
 */
class WordPronouncer(context: Context) {
    private val context = context.applicationContext
    private var engine: TextToSpeech? = null
    private var ready = false
    private var pending: Pair<String, OriginalLanguage>? = null
    private var current: String? = null

    private val _speaking = MutableStateFlow<String?>(null)
    /** The word being said (as passed to [say]), or null. */
    val speaking: StateFlow<String?> = _speaking.asStateFlow()

    private val _missingVoice = MutableStateFlow<OriginalLanguage?>(null)
    /** Set when the phone has no voice for the language asked for. */
    val missingVoice: StateFlow<OriginalLanguage?> = _missingVoice.asStateFlow()

    /** Starts the speech engine ahead of the first word. */
    fun prepare() {
        if (engine != null) return
        engine = TextToSpeech(context) { status ->
            ready = status == TextToSpeech.SUCCESS
            val waiting = pending
            pending = null
            if (ready && waiting != null) speakNow(waiting.first, waiting.second)
            else if (!ready && waiting != null) _missingVoice.value = waiting.second
        }.apply {
            setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit
                override fun onDone(utteranceId: String?) = finished(utteranceId)
                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) = finished(utteranceId)
                override fun onStop(utteranceId: String?, interrupted: Boolean) = finished(utteranceId)
            })
        }
    }

    /** Says the word, stopping any word already being said. */
    fun say(word: String, language: OriginalLanguage) {
        stop()
        prepare()
        if (!ready) {
            pending = word to language
            return
        }
        speakNow(word, language)
    }

    private fun speakNow(word: String, language: OriginalLanguage) {
        val engine = engine ?: return
        val text = PronunciationText.spoken(word, language)
        if (text.isEmpty()) return
        val locale = Locale.forLanguageTag(if (language == OriginalLanguage.HEBREW) "he-IL" else "el-GR")
        val available = runCatching { engine.isLanguageAvailable(locale) }.getOrDefault(TextToSpeech.LANG_NOT_SUPPORTED)
        if (available < TextToSpeech.LANG_AVAILABLE) {
            _missingVoice.value = language
            return
        }
        _missingVoice.value = null
        engine.language = locale
        engine.setSpeechRate(0.8f)
        val id = "pronounce-${System.nanoTime()}"
        current = id
        _speaking.value = word
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
    }

    fun stop() {
        pending = null
        if (current != null) {
            current = null
            engine?.stop()
        }
        _speaking.value = null
    }

    private fun finished(id: String?) {
        if (id == null || id != current) return
        current = null
        _speaking.value = null
    }
}
