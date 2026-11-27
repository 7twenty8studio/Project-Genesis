package com.genesis.app.widget

import android.content.Context
import android.util.Log
import com.genesis.app.VerselyApplication
import com.genesis.app.settings.Entitlements
import com.genesis.core.bible.BibleRepository
import com.genesis.core.bible.BundledBible
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.insights.ReadingStats
import com.genesis.core.domain.link.GenesisLink
import com.genesis.core.domain.memorise.MemoryHint
import com.genesis.core.domain.notifications.NotificationPlanner
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

/**
 * What the widgets show, read from the app's own stores (a widget runs in
 * the app's process, so there's no snapshot file as on iOS), as
 * WidgetSnapshot. Prayer text is private: only counts and times. Verse text
 * comes verbatim from the person's Bible.
 */
internal data class WidgetData(
    val continueReading: Reading?,
    val streakDays: Int,
    val chaptersRead: Int,
    val plan: Plan?,
    val activePrayers: Int,
    val nextPrayerReminder: Long?,
    val memorise: Memorise?,
    val isPremium: Boolean,
    val language: String,
) {
    data class Reading(val verse: VerseId, val reference: String, val snippet: String?, val bookProgress: Double)

    data class Plan(
        val enrollmentId: String,
        val title: String,
        val todayTitle: String?,
        val day: Int,
        val dayCount: Int,
        val isTodayComplete: Boolean,
        val isComplete: Boolean,
        val fractionComplete: Double,
    )

    data class Memorise(val reference: String, val hint: String?, val due: Int, val total: Int)

    companion object {
        private const val TAG = "WidgetData"

        suspend fun load(context: Context, now: Long = System.currentTimeMillis()): WidgetData = withContext(Dispatchers.IO) {
            val app = context.applicationContext as VerselyApplication
            val bible = app.currentBible
            val zone = ZoneId.systemDefault()
            val today = LocalDate.now(zone)
            val record = app.progress.record.value
            val position = app.progress.position.value
            val data = runCatching { app.userData }.onFailure { Log.e(TAG, "Couldn't open the user data", it) }.getOrNull()
            val prayers = data?.prayers?.all?.value.orEmpty().filter { it.hasContent && !it.isAnswered }
            val memory = data?.memory?.all?.value.orEmpty()
            val enrollment = data?.plans?.all?.value.orEmpty().firstOrNull { it.isActive && it.plan != null }
            val premium = Entitlements.isPremium

            runCatching {
                BibleRepository.open(context, bible).use { repository ->
                    val language = repository.translation.language
                    val reading = position?.let { verse ->
                        val book = BibleBooks.withNumber(verse.book)
                        val read = (1..book.chapterCount).count { ReadingStats.chapterKey(verse.book, it) in record.chaptersRead }
                        Reading(
                            verse = verse,
                            reference = "${book.name(language)} ${verse.chapter}",
                            snippet = repository.verses(listOf(verse))[verse]?.plainText,
                            bookProgress = read.toDouble() / book.chapterCount.coerceAtLeast(1),
                        )
                    }
                    val plan = enrollment?.progress?.let { progress ->
                        val day = progress.todaysDay(today)
                        Plan(
                            enrollmentId = enrollment.id,
                            title = enrollment.title,
                            todayTitle = day?.title(language),
                            day = day?.number ?: progress.scheduledDay(today),
                            dayCount = progress.plan.dayCount,
                            isTodayComplete = day != null && day.number in enrollment.completedDays,
                            isComplete = progress.isComplete,
                            fractionComplete = progress.fractionComplete,
                        )
                    }
                    // The passage due soonest, as its opening words (MemoryHint, verbatim).
                    val next = memory.minByOrNull { it.schedule.dueAt }
                    val memorise = if (!premium || next == null) null else {
                        // A Premium tool: never a YouVersion Bible's text.
                        val tools = app.bibles.premiumToolsBible(bible)
                        val text = if (tools == bible) repository.passage(next.start, next.end).joinToString(" ") { it.plainText }
                        else BibleRepository.open(context, tools).use { it.passage(next.start, next.end).joinToString(" ") { verse -> verse.plainText } }
                        Memorise(
                            reference = next.reference.description(language),
                            hint = text.takeIf { it.isNotEmpty() }?.let { MemoryHint.opening(it, 5) },
                            due = memory.count { it.isDue(now) },
                            total = memory.size,
                        )
                    }
                    WidgetData(
                        continueReading = reading,
                        streakDays = app.progress.streak(today, record.readingDays),
                        chaptersRead = record.chaptersRead.size,
                        plan = plan,
                        activePrayers = prayers.size,
                        nextPrayerReminder = prayers.mapNotNull { nextReminder(it.reminderAt, it.reminderRepeatsDaily, now, zone) }.minOrNull(),
                        memorise = memorise,
                        isPremium = premium,
                        language = language,
                    )
                }
            }.onFailure { Log.e(TAG, "Couldn't read the widget data", it) }.getOrNull()
                ?: WidgetData(null, app.progress.streak(today, record.readingDays), record.chaptersRead.size, null, prayers.size, null, null, premium, "en")
        }

        /** The next time a prayer's reminder goes off: a daily one today or tomorrow at its time, a single one only if it's still ahead. */
        internal fun nextReminder(at: Long?, daily: Boolean, now: Long, zone: ZoneId): Long? {
            at ?: return null
            if (!daily) return at.takeIf { it > now }
            val time = Instant.ofEpochMilli(at).atZone(zone).toLocalTime()
            val todayAt = LocalDate.now(zone).atTime(time).atZone(zone).toInstant().toEpochMilli()
            return if (todayAt > now) todayAt else LocalDate.now(zone).plusDays(1).atTime(time).atZone(zone).toInstant().toEpochMilli()
        }

        /** The link that opens the reader where the person left off (Genesis 1 before any reading). */
        fun readLink(reading: Reading?): String = GenesisLink.read(reading?.verse ?: VerseId(1, 1, 1))
    }
}
