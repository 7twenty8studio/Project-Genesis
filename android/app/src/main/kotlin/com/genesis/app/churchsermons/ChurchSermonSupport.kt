package com.genesis.app.churchsermons

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.genesis.app.R
import com.genesis.app.reader.ChurchPassage
import com.genesis.app.together.text
import com.genesis.core.cloud.community.ChurchGathering
import com.genesis.core.cloud.community.ChurchSermonApi
import com.genesis.core.cloud.community.CommunityError
import com.genesis.core.cloud.community.PublishedSermon
import com.genesis.core.cloud.community.SavedHandout
import com.genesis.core.cloud.community.SavedHandouts
import com.genesis.core.cloud.community.SermonAnswers
import com.genesis.core.cloud.community.SermonBlank
import com.genesis.core.cloud.community.SermonBlanks
import com.genesis.core.data.UserDatabase
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.prayer.PrayerPassage
import com.genesis.core.domain.sermons.Sermon
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.ZoneId
import java.util.UUID

/** What church sermon screens need from the rest of the app. */
class ChurchSermonContext(
    val api: ChurchSermonApi?,
    val hidden: HiddenChurches,
    val sermons: UserDatabase.SermonStore,
    /** The Bible being read, and every Bible on this phone (ids). */
    val currentBible: String,
    val bibles: List<String>,
    val language: String,
    val isSignedIn: Boolean,
    val isAvailable: Boolean,
    val passage: suspend (bibleId: String, start: VerseId, end: VerseId) -> ChurchPassage?,
    val onRead: (VerseId) -> Unit,
    val onOpenNotes: (String) -> Unit,
    val onSignIn: () -> Unit,
)

/**
 * Churches whose sermons the person chose not to see (the Block in Report
 * and Block), as HiddenChurches on iOS. Kept on this phone; nobody is told.
 */
class HiddenChurches(context: Context) {
    private val prefs = context.getSharedPreferences("churchSermons", Context.MODE_PRIVATE)
    private val _ids = MutableStateFlow(prefs.getStringSet(KEY, emptySet()).orEmpty().map { it.lowercase() }.toSet())
    val ids: StateFlow<Set<String>> = _ids.asStateFlow()

    fun isHidden(church: String): Boolean = church.lowercase() in _ids.value

    fun set(church: String, hidden: Boolean) {
        val id = church.lowercase()
        _ids.value = if (hidden) _ids.value + id else _ids.value - id
        prefs.edit().putStringSet(KEY, _ids.value).apply()
    }

    private companion object {
        const val KEY = "hidden"
    }
}

/**
 * A person's own notes on a church's sermon, as ChurchSermonNotes on iOS:
 * an ordinary Sermon in Sermon Notes linked by `sourceSermonId`, with the
 * details and verified passages only (never the outline or verse text).
 */
object ChurchSermonNotes {
    fun existing(store: UserDatabase.SermonStore, sermonId: String): Sermon? =
        store.all.value.firstOrNull { it.sourceSermonId.equals(sermonId, ignoreCase = true) }

    /** The person's notes on this sermon, started the first time. */
    fun notes(store: UserDatabase.SermonStore, sermon: PublishedSermon): Sermon {
        existing(store, sermon.id)?.let { return it }
        val preached = sermon.preachedDate?.atStartOfDay(ZoneId.systemDefault())?.toInstant()?.toEpochMilli() ?: System.currentTimeMillis()
        val notes = Sermon(
            id = UUID.randomUUID().toString(),
            title = sermon.title,
            preacher = sermon.speaker,
            church = sermon.church,
            preachedAt = preached,
            series = sermon.series,
            passages = sermon.passages.take(Sermon.MAXIMUM_PASSAGES).map { (start, end) -> PrayerPassage.of(VerseId(start), VerseId(end)) },
            sourceSermonId = sermon.id,
            createdAt = 0,
            updatedAt = 0,
        )
        return store.save(notes)
    }

    fun savedHandout(store: UserDatabase.SermonStore, sermon: PublishedSermon): SavedHandout? =
        existing(store, sermon.id)?.let { notes -> SavedHandouts.decode(notes.handoutsJson).lastOrNull { it.revision == sermon.revision } }

    /** Saves the member's answers on this revision with their notes (starting the notes the first time). */
    fun saveHandout(store: UserDatabase.SermonStore, sermon: PublishedSermon, responses: Map<Int, String>) {
        val notes = notes(store, sermon)
        val saved = SavedHandouts.saving(SavedHandouts.decode(notes.handoutsJson), sermon, responses, System.currentTimeMillis())
        store.save(notes.copy(handoutsJson = SavedHandouts.encode(saved)))
    }

    /** New answers on a saved handout (from Sermon Notes); its outline and key stay. */
    fun updating(notes: Sermon, handout: SavedHandout, responses: Map<Int, String>): Sermon {
        val saved = SavedHandouts.decode(notes.handoutsJson).map {
            if (it.id == handout.id) it.copy(responses = responses, savedAt = System.currentTimeMillis()) else it
        }
        return notes.copy(handoutsJson = SavedHandouts.encode(saved))
    }
}

/**
 * A fill-in-the-blank handout being filled in, as HandoutModel on iOS.
 * Check Answers and Show Answers come together, only with the key; Practice
 * Again is a fresh try that never touches the saved answers.
 */
class HandoutState(
    blanks: List<SermonBlank>,
    val answers: SermonAnswers,
    saved: Map<Int, String>,
    savedKey: List<SermonBlank> = emptyList(),
    private val save: (Map<Int, String>) -> Unit,
) {
    val blanks: List<SermonBlank> = blanks.sortedBy { it.n }
    val known: Set<Int> = this.blanks.map { it.n }.toSet()
    private val key: Map<Int, String> = buildMap {
        savedKey.filter { it.isCheckable }.forEach { put(it.n, it.answer!!) }
        if (answers == SermonAnswers.REVEALED) blanks.filter { it.isCheckable }.forEach { put(it.n, it.answer!!) }
    }
    private val responses = mutableStateMapOf<Int, String>().apply { putAll(saved) }
    private var practice by mutableStateOf<Map<Int, String>?>(null)
    var checked by mutableStateOf(false)
        private set
    var showing by mutableStateOf(false)
        private set

    val canCheck: Boolean get() = key.isNotEmpty()
    val isPracticing: Boolean get() = practice != null

    fun blank(n: Int): SermonBlank? = blanks.firstOrNull { it.n == n }
    fun value(n: Int): String = (practice ?: responses)[n].orEmpty()

    fun set(n: Int, text: String) {
        checked = false
        val trying = practice
        if (trying != null) {
            practice = trying + (n to text)
            return
        }
        responses[n] = text
        save(responses.filterValues { it.isNotEmpty() })
    }

    fun grade(n: Int): Boolean? {
        if (!checked) return null
        val answer = key[n] ?: return null
        return SermonBlanks.isCorrect(value(n), answer)
    }

    fun shownAnswer(n: Int): String? = if (showing) key[n] else null
    fun check() { if (canCheck) checked = true }
    fun toggleShowing() { if (canCheck) showing = !showing }

    fun startPractice() {
        practice = emptyMap()
        checked = false
        showing = false
    }

    fun endPractice() {
        practice = null
        checked = false
    }

    val score: Pair<Int, Int>?
        get() {
            if (!checked) return null
            val graded = blanks.mapNotNull { grade(it.n) }
            return graded.count { it } to graded.size
        }
}

internal val ChurchGathering.Weekday.plural: Int
    get() = when (this) {
        ChurchGathering.Weekday.SUN -> R.string.weekday_sun
        ChurchGathering.Weekday.MON -> R.string.weekday_mon
        ChurchGathering.Weekday.TUE -> R.string.weekday_tue
        ChurchGathering.Weekday.WED -> R.string.weekday_wed
        ChurchGathering.Weekday.THU -> R.string.weekday_thu
        ChurchGathering.Weekday.FRI -> R.string.weekday_fri
        ChurchGathering.Weekday.SAT -> R.string.weekday_sat
    }

/** The words for a church sermon error (ChurchSermonError on iOS), else the community's. */
internal fun CommunityError.sermonText(): Int = when ((this as? CommunityError.Code)?.code) {
    "not_signed_in" -> R.string.error_sermon_sign_in
    "not_found" -> R.string.error_sermon_gone
    "not_allowed" -> R.string.error_sermon_not_allowed
    "invalid_details" -> R.string.error_sermon_reason
    else -> text()
}
