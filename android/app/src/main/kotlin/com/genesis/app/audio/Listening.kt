package com.genesis.app.audio

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import android.util.Log
import androidx.annotation.StringRes
import androidx.core.content.ContextCompat
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.genesis.app.R
import com.genesis.core.bible.BibleRepository
import com.genesis.core.bible.Chapter
import com.genesis.core.domain.audio.Narration
import com.genesis.core.domain.audio.NarrationItem
import com.genesis.core.domain.audio.NarrationVerse
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.VerseId
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

enum class ListeningStatus { IDLE, LOADING, PLAYING, PAUSED }

/** Stops listening after some minutes, or at the end of the chapter. */
sealed interface SleepTimer {
    data class Minutes(val minutes: Int) : SleepTimer
    data object EndOfChapter : SleepTimer

    companion object {
        val choices: List<SleepTimer> = listOf(Minutes(15), Minutes(30), Minutes(60), EndOfChapter)
    }
}

data class ListeningState(
    val status: ListeningStatus = ListeningStatus.IDLE,
    val bible: com.genesis.core.bible.InstalledBible? = null,
    val chapter: ChapterId? = null,
    /** The verse being read, or null during the chapter's title. */
    val verse: VerseId? = null,
    val language: String = "en",
    val abbreviation: String = "",
    @param:StringRes val error: Int? = null,
    val sleepTimer: SleepTimer? = null,
    val sleepEndsAt: Long? = null,
) {
    val isActive: Boolean get() = status != ListeningStatus.IDLE
    val isPlaying: Boolean get() = status == ListeningStatus.PLAYING || status == ListeningStatus.LOADING

    /** "John 3:16", or "John 3" before the first verse. */
    val title: String
        get() {
            val chapter = chapter ?: return ""
            val base = chapter.description(language)
            return verse?.let { "$base:${it.verse}" } ?: base
        }
}

/**
 * Listening to the Bible with the phone's own voice, verse by verse, the
 * reader following along, chapter after chapter (AudioPlayerService +
 * SpeechNarrator on iOS). Free for everyone, works offline. The words are
 * read straight from the Bible database; nothing is rewritten.
 *
 * Android's text-to-speech can't pause mid-word, so Pause stops and Play
 * picks up again from the verse being read. Everything runs on the main thread.
 */
class Listening(private val context: Context, val settings: ListeningSettings) {
    private val main = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(Dispatchers.Main)
    private val _state = MutableStateFlow(ListeningState())
    val state: StateFlow<ListeningState> = _state.asStateFlow()

    /** The lock screen, notification and headphone buttons (Media3), made on first use. */
    val player: ListeningPlayer by lazy { ListeningPlayer(this) }
    private var controller: ListenableFuture<MediaController>? = null

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var whenReady: (() -> Unit)? = null

    /** Each start gets a new generation, so callbacks from a stopped chapter are ignored. */
    private var generation = 0
    private var verseByUtterance: Map<String, VerseId> = emptyMap()
    private var chapterVerses: List<VerseId> = emptyList()
    private var loadJob: Job? = null
    private var sleepJob: Job? = null
    private var pausedByInterruption = false
    private val repositories = mutableMapOf<com.genesis.core.bible.InstalledBible, BibleRepository>()

    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
    private val focusRequest by lazy {
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attributes)
            .setOnAudioFocusChangeListener({ change -> focusChanged(change) }, main)
            .build()
    }
    private var noisyRegistered = false
    private val noisy = object : BroadcastReceiver() {
        // Headphones unplugged: pause rather than read out loud in the room.
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) pause()
        }
    }

    // MARK: Playing

    /** Starts reading a chapter of [bible], from a verse or the start. */
    fun play(bible: com.genesis.core.bible.InstalledBible, chapter: ChapterId, from: VerseId? = null) {
        connectSession()
        stopSpeaking()
        loadJob?.cancel()
        _state.update { it.copy(status = ListeningStatus.LOADING, bible = bible, chapter = chapter, verse = from?.takeIf { v -> v.chapterId == chapter }, error = null) }
        loadJob = scope.launch {
            val loaded = withContext(Dispatchers.IO) { runCatching { repository(bible).chapter(chapter) }.getOrNull() }
            if (loaded == null) {
                fail(R.string.chapter_load_failed)
                return@launch
            }
            val gen = generation
            withTts { if (gen == generation && state.value.status == ListeningStatus.LOADING) speak(loaded, from) }
        }
    }

    fun pause() {
        val current = state.value
        if (!current.isPlaying) return
        pausedByInterruption = false
        loadJob?.cancel()
        stopSpeaking()
        _state.update { it.copy(status = ListeningStatus.PAUSED) }
        player.refresh()
    }

    fun resume() {
        val current = state.value
        if (current.status != ListeningStatus.PAUSED) return
        val bible = current.bible ?: return
        val chapter = current.chapter ?: return
        play(bible, chapter, current.verse)
    }

    fun toggle() = if (state.value.isPlaying) pause() else resume()

    fun stop() {
        loadJob?.cancel()
        cancelSleepTimer()
        stopSpeaking()
        _state.value = ListeningState()
        abandonFocus()
        player.refresh()
        controller?.let { MediaController.releaseFuture(it) }
        controller = null
    }

    fun nextChapter() {
        val current = state.value
        val next = current.chapter?.next ?: return
        play(current.bible ?: return, next)
    }

    fun previousChapter() {
        val current = state.value
        val chapter = current.chapter ?: return
        play(current.bible ?: return, Narration.previous(chapter, current.verse))
    }

    /** A verse back or on; while paused, moves without speaking. */
    fun skip(forward: Boolean) {
        val current = state.value
        val verse = current.verse ?: return
        val target = Narration.skip(chapterVerses, verse, forward) ?: return
        if (current.status == ListeningStatus.PAUSED) {
            _state.update { it.copy(verse = target) }
            player.refresh()
        } else {
            play(current.bible ?: return, current.chapter ?: return, target)
        }
    }

    fun setSpeed(speed: Double) {
        settings.setSpeed(speed)
        // Speech can't change speed mid-sentence: pick up from this verse.
        val current = state.value
        if (current.isPlaying) play(current.bible ?: return, current.chapter ?: return, current.verse)
    }

    fun setSleepTimer(timer: SleepTimer?) {
        cancelSleepTimer()
        if (timer == null) return
        val minutes = (timer as? SleepTimer.Minutes)?.minutes
        val endsAt = minutes?.let { System.currentTimeMillis() + it * 60_000L }
        _state.update { it.copy(sleepTimer = timer, sleepEndsAt = endsAt) }
        if (minutes != null) {
            sleepJob = scope.launch {
                delay(minutes * 60_000L)
                _state.update { it.copy(sleepTimer = null, sleepEndsAt = null) }
                pause()
            }
        }
    }

    private fun cancelSleepTimer() {
        sleepJob?.cancel()
        sleepJob = null
        _state.update { it.copy(sleepTimer = null, sleepEndsAt = null) }
    }

    // MARK: Speaking

    private fun speak(chapter: Chapter, from: VerseId?) {
        val engine = tts ?: return fail(R.string.listening_no_engine)
        val language = chapter.translation.language
        if (!chooseVoice(engine, language)) return fail(R.string.listening_no_voice)
        if (!requestFocus()) return fail(R.string.listening_no_focus)
        val speed = settings.state.value.speed
        engine.setSpeechRate(speed.toFloat())
        val verses = chapter.verses.map { NarrationVerse(it.id, it.text, it.startsParagraph) }
        chapterVerses = verses.map { it.id }
        val title = Narration.title(chapter.id.bibleBook.name(language), chapter.id.chapter, language)
        val script = Narration.script(verses, from, title, speed)
        generation += 1
        val gen = generation
        val ids = mutableMapOf<String, VerseId>()
        script.forEachIndexed { index, item: NarrationItem ->
            val id = "$gen:$index"
            item.verse?.let { ids[id] = it }
            engine.speak(item.text, TextToSpeech.QUEUE_ADD, Bundle(), id)
            if (item.pauseAfterMillis > 0) engine.playSilentUtterance(item.pauseAfterMillis, TextToSpeech.QUEUE_ADD, "$gen:pause$index")
        }
        engine.playSilentUtterance(1, TextToSpeech.QUEUE_ADD, "$gen:end")
        verseByUtterance = ids
        registerNoisy()
        _state.update {
            it.copy(
                status = ListeningStatus.PLAYING,
                language = language,
                abbreviation = chapter.translation.abbreviation,
                verse = script.firstOrNull()?.verse,
            )
        }
        player.refresh()
    }

    private fun stopSpeaking() {
        generation += 1
        verseByUtterance = emptyMap()
        tts?.stop()
        unregisterNoisy()
    }

    private fun utteranceStarted(id: String) {
        if (!id.startsWith("$generation:")) return
        val verse = verseByUtterance[id] ?: return
        if (state.value.verse == verse) return
        _state.update { it.copy(verse = verse) }
        player.refresh()
    }

    private fun utteranceDone(id: String) {
        if (id != "$generation:end" || state.value.status != ListeningStatus.PLAYING) return
        chapterFinished()
    }

    private fun chapterFinished() {
        val current = state.value
        val next = current.chapter?.next
        if (current.sleepTimer == SleepTimer.EndOfChapter || !settings.state.value.continuesToNextChapter || next == null) {
            if (current.sleepTimer == SleepTimer.EndOfChapter) cancelSleepTimer()
            stopSpeaking()
            _state.update { it.copy(status = ListeningStatus.PAUSED, verse = null) }
            player.refresh()
            return
        }
        play(current.bible ?: return, next)
    }

    private fun fail(@StringRes message: Int) {
        stopSpeaking()
        _state.update { it.copy(status = ListeningStatus.PAUSED, error = message) }
        player.refresh()
    }

    // MARK: Text to speech

    private fun withTts(action: () -> Unit) {
        if (ttsReady) return action()
        whenReady = action
        if (tts != null) return
        tts = TextToSpeech(context) { status ->
            main.post {
                if (status == TextToSpeech.SUCCESS) {
                    ttsReady = true
                    tts?.setAudioAttributes(attributes)
                    tts?.setOnUtteranceProgressListener(progress)
                    whenReady?.invoke()
                } else {
                    tts = null
                    fail(R.string.listening_no_engine)
                }
                whenReady = null
            }
        }
    }

    private val progress = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String) {
            main.post { utteranceStarted(utteranceId) }
        }

        override fun onDone(utteranceId: String) {
            main.post { utteranceDone(utteranceId) }
        }

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String) {
            Log.w(TAG, "Couldn't speak $utteranceId")
        }
    }

    /**
     * The most natural installed voice in the Bible's language that works
     * offline; Portuguese is Brazilian unless the Bible says otherwise
     * (as VoiceAccent on iOS). False when the phone has none.
     */
    private fun chooseVoice(engine: TextToSpeech, language: String): Boolean {
        val locale = when (language) {
            "pt" -> Locale.forLanguageTag("pt-BR")
            "es" -> Locale.forLanguageTag("es-MX")
            "en" -> Locale.US
            else -> Locale.forLanguageTag(language)
        }
        val voices = runCatching { engine.voices }.getOrNull().orEmpty().filter { voice ->
            voice.locale.language == locale.language &&
                !voice.isNetworkConnectionRequired &&
                TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED !in voice.features
        }
        val best = voices.sortedWith(
            compareByDescending<Voice> { it.locale.country == locale.country }.thenByDescending { it.quality }.thenBy { it.latency },
        ).firstOrNull()
        if (best != null) return engine.setVoice(best) == TextToSpeech.SUCCESS
        val result = engine.setLanguage(locale)
        return result != TextToSpeech.LANG_MISSING_DATA && result != TextToSpeech.LANG_NOT_SUPPORTED
    }

    // MARK: Audio focus

    private fun requestFocus(): Boolean =
        audioManager.requestAudioFocus(focusRequest) != AudioManager.AUDIOFOCUS_REQUEST_FAILED

    private fun abandonFocus() {
        audioManager.abandonAudioFocusRequest(focusRequest)
    }

    private fun focusChanged(change: Int) {
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> pause()
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                // A call or a navigation prompt: pick up again afterwards.
                if (state.value.isPlaying) {
                    pause()
                    pausedByInterruption = true
                }
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                if (pausedByInterruption && state.value.status == ListeningStatus.PAUSED) resume()
                pausedByInterruption = false
            }
        }
    }

    private fun registerNoisy() {
        if (noisyRegistered) return
        ContextCompat.registerReceiver(context, noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), ContextCompat.RECEIVER_NOT_EXPORTED)
        noisyRegistered = true
    }

    private fun unregisterNoisy() {
        if (!noisyRegistered) return
        runCatching { context.unregisterReceiver(noisy) }
        noisyRegistered = false
    }

    // MARK: Helpers

    /** Binds the media session service, which shows the controls and keeps reading with the screen off. */
    private fun connectSession() {
        if (controller != null) return
        val token = SessionToken(context, ComponentName(context, ListeningService::class.java))
        controller = MediaController.Builder(context, token).buildAsync()
    }

    private fun repository(bible: com.genesis.core.bible.InstalledBible): BibleRepository = synchronized(repositories) {
        repositories.getOrPut(bible) { BibleRepository.open(context, bible) }
    }

    private companion object {
        const val TAG = "Listening"
    }
}
