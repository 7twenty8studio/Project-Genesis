package com.genesis.app.notifications

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.edit
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.plans.builtInTitle
import com.genesis.app.settings.AppLanguageChoice
import com.genesis.core.bible.BibleRepository
import com.genesis.core.bible.BundledBible
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.home.DailyVerse
import com.genesis.core.domain.link.GenesisLink
import com.genesis.core.domain.notifications.NotificationInput
import com.genesis.core.domain.notifications.NotificationPlanner
import com.genesis.core.domain.notifications.ReminderKind
import com.genesis.app.features.feature
import com.genesis.app.features.shows
import com.genesis.core.domain.notifications.ReminderMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale

/**
 * Puts the planned notifications on the phone's schedule, as
 * ReminderScheduler on iOS: local alarms, so they work offline with no
 * server. Each refresh replaces Versely's alarms with a fresh week (and the
 * prayers' own reminders). Called when Versely opens or leaves the screen,
 * when the person's data or the settings change, when a reminder rings, and
 * after the phone restarts or its clock changes.
 */
object ReminderScheduler {
    private const val TAG = "Reminders"
    private const val SCHEDULED = "notifications.scheduled"
    private const val PRAYER_PREFIX = "prayer-"
    private val lock = Mutex()

    /** Whether Android lets Versely post notifications (the app's switch in the system's settings). */
    fun systemAllows(context: Context): Boolean = NotificationManagerCompat.from(context).areNotificationsEnabled()

    suspend fun refresh(context: Context) = lock.withLock {
        withContext(Dispatchers.IO) {
            runCatching { reschedule(context.applicationContext) }.onFailure { Log.e(TAG, "Couldn't schedule reminders", it) }
        }
    }

    private fun reschedule(app: Context) {
        val versely = app as VerselyApplication
        // The words in Versely's own language (Settings › Language).
        val words = AppLanguageChoice.wrap(app)
        createChannels(words)
        val alarms = app.getSystemService(AlarmManager::class.java)
        val store = app.getSharedPreferences("notifications", Context.MODE_PRIVATE)
        val previous = store.getStringSet(SCHEDULED, emptySet()).orEmpty()
        previous.forEach { id -> alarms.cancel(pendingIntent(app, id, null, PendingIntent.FLAG_NO_CREATE) ?: return@forEach) }

        val preferences = versely.notifications.state.value
        val zone = ZoneId.systemDefault()
        val now = LocalDateTime.now(zone)
        val items = mutableListOf<Alarm>()
        if (systemAllows(app)) {
            NotificationPlanner.plan(input(versely, words, preferences, now, zone)).forEach { planned ->
                val (title, body) = words.text(planned.message)
                items += Alarm(planned.id, planned.kind, planned.fireAt, title, body, planned.link)
            }
            if (preferences.allows(ReminderKind.PRAYER) && versely.features.isOn(com.genesis.core.domain.features.OptionalFeature.PRAYER)) {
                for (prayer in versely.userData.prayers.all.value) {
                    val at = prayer.reminderAt?.let { LocalDateTime.ofInstant(Instant.ofEpochMilli(it), zone) }
                    val fire = NotificationPlanner.prayerReminder(prayer.isAnswered, at, prayer.reminderRepeatsDaily, now) ?: continue
                    // Prayer text is private: only the title the person chose, never the body.
                    val title = prayer.title.trim().ifEmpty { prayer.displayTitle ?: words.getString(R.string.prayer) }
                    items += Alarm(PRAYER_PREFIX + prayer.id, ReminderKind.PRAYER, fire, words.getString(R.string.a_moment_to_pray), title, GenesisLink.PRAYER)
                }
            }
        }
        for (item in items) {
            val millis = item.fireAt.atZone(zone).toInstant().toEpochMilli()
            val intent = pendingIntent(app, item.id, item, PendingIntent.FLAG_UPDATE_CURRENT) ?: continue
            // On the minute where Android allows it ("Alarms & reminders"); otherwise
            // as close as Android lets an app ring while the phone sleeps.
            if (alarms.canScheduleExactAlarms()) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, intent)
            } else {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, intent)
            }
        }
        store.edit { putStringSet(SCHEDULED, items.map { it.id }.toSet()) }
    }

    /** Gathers what the planner needs, as ReminderScheduler.input on iOS. */
    private fun input(app: VerselyApplication, words: Context, preferences: NotificationPreferences.State, now: LocalDateTime, zone: ZoneId): NotificationInput {
        // Nothing is sent for a hidden feature (Settings › Features).
        val shown = app.features.enabled.value
        val flags = app.flags.values.value
        val settings = preferences.settings.let { all ->
            all.copy(enabled = all.enabled.filter { kind -> kind.feature()?.let { shown.shows(it, flags) } ?: true }.toSet())
        }
        val today = now.toLocalDate()
        val days = (0 until NotificationPlanner.HORIZON_DAYS).map { today.plusDays(it.toLong()) }
        val language = words.resources.configuration.locales[0].language
        var input = NotificationInput(now = now, settings = settings)

        if (ReminderKind.VERSE_OF_THE_DAY in settings.enabled) {
            val bible = app.currentBible
            runCatching {
                BibleRepository.open(app, bible).use { repository ->
                    val ids = days.associateWith { DailyVerse.verse(it, zone) }
                    val verses = repository.verses(ids.values.toList())
                    val translation = repository.translation
                    input = input.copy(
                        dailyVerses = ids.mapNotNull { (day, id) ->
                            val text = verses[id]?.displayText ?: return@mapNotNull null
                            day to NotificationInput.VerseText(
                                reference = ReferenceParser.describe(id.rawValue, language = translation.language) + " (" + translation.abbreviation + ")",
                                text = text,
                                verse = id,
                            )
                        }.toMap(),
                    )
                }
            }.onFailure { Log.w(TAG, "Couldn't read the verses of the day", it) }
        }

        if (ReminderKind.DAILY_READING in settings.enabled) {
            // The streak follows the shields; the reminder follows the daily goal.
            val goal = app.goals.state.value
            input = input.copy(
                readingDays = app.progress.readingDays,
                streakShields = goal.usesStreakShields,
                goalToday = goal.goal.progress(app.progress.chaptersRead(today), app.progress.secondsRead(today)),
            )
        }

        // Memorize is Premium.
        if (ReminderKind.MEMORISE in settings.enabled && com.genesis.app.settings.Entitlements.isPremium) {
            input = input.copy(memoryDueDates = app.userData.memory.all.value.map { LocalDateTime.ofInstant(Instant.ofEpochMilli(it.schedule.dueAt), zone) })
        }

        if (ReminderKind.PRAYER_ANNIVERSARY in settings.enabled) {
            input = input.copy(
                answeredPrayers = app.userData.prayers.all.value.mapNotNull { prayer ->
                    val answered = prayer.answeredAt?.takeIf { prayer.isAnswered } ?: return@mapNotNull null
                    val title = prayer.displayTitle ?: words.getString(R.string.prayer)
                    NotificationInput.AnsweredPrayer(title, Instant.ofEpochMilli(answered).atZone(zone).toLocalDate())
                },
            )
        }

        if (ReminderKind.READING_PLAN in settings.enabled) {
            val enrollment = app.userData.plans.all.value.firstOrNull { it.isActive }
            val plan = enrollment?.plan
            val progress = enrollment?.progress
            if (plan != null && progress != null && !progress.isComplete) {
                val readings = mutableMapOf<LocalDate, String>()
                for (day in days) {
                    // A day already ticked off has nothing left to remind about.
                    if (progress.scheduledDay(day) in progress.completedDays) continue
                    progress.todaysDay(day)?.let { readings[day] = it.title(language) }
                }
                val title = plan.custom?.title ?: builtInTitle(plan.id)?.let(words::getString) ?: enrollment.title
                input = input.copy(planTitle = title, planReadings = readings)
            }
        }
        return input
    }

    private fun Context.text(message: ReminderMessage): Pair<String, String> = when (message) {
        is ReminderMessage.VerseOfTheDay -> getString(R.string.verse_of_the_day) + " · " + message.reference to message.text
        is ReminderMessage.Streak -> getString(R.string.keep_streak_going) to getString(R.string.keep_streak_body, message.days)
        ReminderMessage.TwoDaysInARow -> getString(R.string.two_days_in_a_row) to getString(R.string.two_days_body)
        ReminderMessage.WelcomeBack -> getString(R.string.welcome_back_anytime) to getString(R.string.welcome_back_body)
        is ReminderMessage.Invitation -> {
            val titles = intArrayOf(R.string.invitation_title_0, R.string.invitation_title_1, R.string.invitation_title_2, R.string.invitation_title_3)
            val bodies = intArrayOf(R.string.invitation_body_0, R.string.invitation_body_1, R.string.invitation_body_2, R.string.invitation_body_3)
            getString(titles[message.index]) to getString(bodies[message.index])
        }
        is ReminderMessage.PlanReading -> message.planTitle to getString(R.string.todays_reading_body, message.reading)
        is ReminderMessage.AlmostThere -> getString(R.string.almost_there) to when {
            message.progress.goal.unit == com.genesis.core.domain.goals.ReadingGoal.Unit.MINUTES -> getString(R.string.goal_nudge_minutes, message.progress.remaining)
            message.progress.remaining == 1 -> getString(R.string.goal_nudge_one_chapter)
            else -> getString(R.string.goal_nudge_chapters, message.progress.remaining)
        }
        is ReminderMessage.MemoriseDue -> getString(R.string.time_to_review) to if (message.count == 1) getString(R.string.review_one) else getString(R.string.review_many, message.count)
        ReminderMessage.SermonNotes -> getString(R.string.sermon_notes) to getString(R.string.sermon_notes_reminder)
        ReminderMessage.WeeklyRecap -> getString(R.string.your_week_in_scripture) to getString(R.string.weekly_recap_body)
        is ReminderMessage.Anniversary -> {
            val title = if (message.years == 1) getString(R.string.a_year_ago_today) else getString(R.string.years_ago_today, message.years)
            val body = if (message.more == 0) getString(R.string.anniversary_body, message.title) else getString(R.string.anniversary_body_more, message.title, message.more)
            title to body
        }
    }

    /** One channel per kind, so each can also be tuned in Android's settings. */
    private fun createChannels(words: Context) {
        val manager = words.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannels(
            ReminderKind.entries.map { NotificationChannel(it.rawValue, words.getString(it.titleRes), NotificationManager.IMPORTANCE_DEFAULT) },
        )
    }

    internal val ReminderKind.titleRes: Int
        get() = when (this) {
            ReminderKind.VERSE_OF_THE_DAY -> R.string.verse_of_the_day
            ReminderKind.DAILY_READING -> R.string.reminder_daily_reading
            ReminderKind.READING_PLAN -> R.string.reminder_reading_plan
            ReminderKind.MEMORISE -> R.string.reminder_memorise
            ReminderKind.PRAYER -> R.string.reminder_prayer
            ReminderKind.SERMONS -> R.string.reminder_sermons
            ReminderKind.WEEKLY_RECAP -> R.string.reminder_recap
            ReminderKind.GROUPS -> R.string.reminder_groups
            ReminderKind.NUDGES -> R.string.reminder_nudges
            ReminderKind.PRAYER_ANNIVERSARY -> R.string.reminder_anniversary
        }

    internal val ReminderKind.detailRes: Int
        get() = when (this) {
            ReminderKind.VERSE_OF_THE_DAY -> R.string.reminder_verse_detail
            ReminderKind.DAILY_READING -> R.string.reminder_reading_detail
            ReminderKind.READING_PLAN -> R.string.reminder_plan_detail
            ReminderKind.MEMORISE -> R.string.reminder_memorise_detail
            ReminderKind.PRAYER -> R.string.reminder_prayer_detail
            ReminderKind.SERMONS -> R.string.reminder_sermons_detail
            ReminderKind.WEEKLY_RECAP -> R.string.reminder_recap_detail
            ReminderKind.GROUPS -> R.string.reminder_groups_detail
            ReminderKind.NUDGES -> R.string.reminder_nudges_detail
            ReminderKind.PRAYER_ANNIVERSARY -> R.string.reminder_anniversary_detail
        }

    internal class Alarm(val id: String, val kind: ReminderKind, val fireAt: LocalDateTime, val title: String, val body: String, val link: String)

    /** The alarm's intent; its address (data) is the reminder's id, so each has its own. */
    private fun pendingIntent(context: Context, id: String, alarm: Alarm?, flag: Int): PendingIntent? {
        val intent = Intent(context, ReminderReceiver::class.java)
            .setAction(ReminderReceiver.ACTION_RING)
            .setData(Uri.parse("versely-reminder://" + Uri.encode(id)))
        if (alarm != null) {
            intent.putExtra(ReminderReceiver.EXTRA_KIND, alarm.kind.rawValue)
                .putExtra(ReminderReceiver.EXTRA_TITLE, alarm.title)
                .putExtra(ReminderReceiver.EXTRA_BODY, alarm.body)
                .putExtra(ReminderReceiver.EXTRA_LINK, alarm.link)
        }
        return PendingIntent.getBroadcast(context, 0, intent, flag or PendingIntent.FLAG_IMMUTABLE)
    }
}
