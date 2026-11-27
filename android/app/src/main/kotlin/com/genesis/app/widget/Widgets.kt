package com.genesis.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.width
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextDecoration
import androidx.glance.text.TextStyle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.core.domain.link.GenesisLink
import java.text.DateFormat
import java.util.Date

/** One snapshot per update, shared by every widget below. */
abstract class VerselyWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val data = WidgetData.load(context)
        provideContent { Content(data) }
    }

    @Composable
    internal abstract fun Content(data: WidgetData)
}

private fun time(millis: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(millis))

@Composable
private fun prayerCount(count: Int): String = if (count == 1) string(R.string.one_prayer) else string(R.string.prayers_count, count)

// Continue Reading

/** Pick up where you left off: the chapter, its opening words and how far through the book. */
class ContinueReadingWidget : VerselyWidget() {
    @Composable
    override fun Content(data: WidgetData) {
        val reading = data.continueReading
        WidgetCard(WidgetData.readLink(reading)) {
            Eyebrow(string(if (reading == null) R.string.begin_reading else R.string.continue_reading))
            Spacer(GlanceModifier.height(8.dp))
            Headline(reading?.reference ?: string(R.string.genesis_one), size = 19, maxLines = 1)
            Spacer(GlanceModifier.height(4.dp))
            reading?.snippet?.let { Caption(it, maxLines = 2, serif = true, size = 13) }
            Spacer(GlanceModifier.defaultWeight())
            if (reading != null) ProgressBar(reading.bookProgress)
        }
    }
}

// Reading Progress

/** Today: the plan's reading (or where the person left off), the streak, chapters read and prayers. */
class ReadingProgressWidget : VerselyWidget() {
    @Composable
    override fun Content(data: WidgetData) {
        val plan = data.plan
        WidgetCard(if (plan != null) GenesisLink.PLANS else WidgetData.readLink(data.continueReading)) {
            Eyebrow(string(R.string.group_today))
            Spacer(GlanceModifier.height(12.dp))
            val reading = data.continueReading
            if (plan != null) {
                Caption(plan.title)
                Headline(if (plan.isComplete) string(R.string.plan_complete) else plan.todayTitle.orEmpty(), size = 19)
                Spacer(GlanceModifier.height(4.dp))
                Row(GlanceModifier.fillMaxWidth()) {
                    Caption(string(R.string.day_of_days, plan.day, plan.dayCount))
                    Spacer(GlanceModifier.defaultWeight())
                    if (plan.isTodayComplete) Caption("✓ " + string(R.string.done))
                }
                Spacer(GlanceModifier.height(6.dp))
                ProgressBar(plan.fractionComplete)
            } else if (reading != null) {
                Caption(string(R.string.continue_reading))
                Headline(reading.reference, size = 19, maxLines = 1)
                Spacer(GlanceModifier.height(6.dp))
                ProgressBar(reading.bookProgress)
            }
            Spacer(GlanceModifier.height(16.dp))
            Row(GlanceModifier.fillMaxWidth()) {
                Stat(R.drawable.ic_widget_flame, data.streakDays.toString(), string(R.string.day_streak), GlanceModifier.defaultWeight())
                Stat(R.drawable.ic_widget_book, data.chaptersRead.toString(), string(R.string.chapters_read), GlanceModifier.defaultWeight())
            }
            Spacer(GlanceModifier.height(16.dp))
            Row(
                GlanceModifier.fillMaxWidth().clickable(androidx.glance.appwidget.action.actionStartActivity(openIntent(androidx.glance.LocalContext.current, GenesisLink.PRAYER))),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Symbol(R.drawable.ic_widget_prayer)
                Spacer(GlanceModifier.width(10.dp))
                Column {
                    Text(prayerCount(data.activePrayers), style = TextStyle(color = WidgetPalette.text, fontWeight = FontWeight.Medium, fontSize = 14.sp))
                    data.nextPrayerReminder?.let { Caption(string(R.string.next_reminder_at, time(it))) }
                }
            }
        }
    }

    @Composable
    private fun Stat(icon: Int, value: String, label: String, modifier: GlanceModifier) {
        Column(modifier) {
            Symbol(icon)
            Text(value, style = TextStyle(color = WidgetPalette.text, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Medium, fontSize = 22.sp))
            Caption(label, size = 11)
        }
    }
}

// Reading Streak

/** Days in a row read, small. */
class StreakWidget : VerselyWidget() {
    @Composable
    override fun Content(data: WidgetData) {
        val wide = LocalSize.current.width >= 150.dp
        WidgetCard(WidgetData.readLink(data.continueReading), small = true) {
            Symbol(R.drawable.ic_widget_flame, size = 22)
            Spacer(GlanceModifier.defaultWeight())
            Text(data.streakDays.toString(), style = TextStyle(color = WidgetPalette.text, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Medium, fontSize = if (wide) 30.sp else 26.sp))
            Caption(string(R.string.day_streak), size = 11)
        }
    }
}

// Prayer Reminder

/** The next prayer reminder and how many requests are being prayed for; never their words. */
class PrayerReminderWidget : VerselyWidget() {
    @Composable
    override fun Content(data: WidgetData) {
        WidgetCard(GenesisLink.PRAYER, small = true) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Symbol(R.drawable.ic_widget_prayer)
                Spacer(GlanceModifier.width(6.dp))
                Text(string(R.string.prayer), style = TextStyle(color = WidgetPalette.accent, fontWeight = FontWeight.Bold, fontSize = 13.sp))
            }
            Spacer(GlanceModifier.defaultWeight())
            Headline(data.nextPrayerReminder?.let { string(R.string.next_reminder_at, time(it)) } ?: string(R.string.no_reminder_set), size = 15)
            Caption(prayerCount(data.activePrayers))
        }
    }
}

// Today's Reading, with a tick

/** Today's reading from the plan, ticked off from the widget (TogglePlanDayIntent on iOS). */
class TodaysReadingWidget : VerselyWidget() {
    @Composable
    override fun Content(data: WidgetData) {
        val plan = data.plan
        val small = LocalSize.current.width < MEDIUM.width
        WidgetCard(GenesisLink.PLANS, small = small) {
            if (plan == null || plan.todayTitle == null) {
                Symbol(R.drawable.ic_widget_check, size = 22)
                Spacer(GlanceModifier.height(8.dp))
                Text(
                    if (plan == null) string(R.string.widget_start_plan) else string(R.string.plan_complete),
                    style = TextStyle(color = WidgetPalette.text, fontFamily = FontFamily.Serif, fontSize = 13.sp),
                )
                return@WidgetCard
            }
            Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Eyebrow(string(R.string.todays_reading))
                Spacer(GlanceModifier.defaultWeight())
                if (!small) Caption(string(R.string.day_of_days, plan.day, plan.dayCount), size = 11)
            }
            Spacer(GlanceModifier.height(8.dp))
            Text(
                plan.todayTitle,
                maxLines = 2,
                style = TextStyle(
                    color = WidgetPalette.text,
                    fontFamily = FontFamily.Serif,
                    fontWeight = FontWeight.Medium,
                    fontSize = if (small) 16.sp else 19.sp,
                    textDecoration = if (plan.isTodayComplete) TextDecoration.LineThrough else null,
                ),
            )
            Caption(plan.title)
            Spacer(GlanceModifier.defaultWeight())
            ProgressBar(plan.fractionComplete)
            Spacer(GlanceModifier.height(8.dp))
            Row(
                GlanceModifier.clickable(
                    actionRunCallback<MarkPlanDayAction>(
                        actionParametersOf(
                            MarkPlanDayAction.ENROLLMENT to plan.enrollmentId,
                            MarkPlanDayAction.DAY to plan.day,
                            MarkPlanDayAction.COMPLETED to !plan.isTodayComplete,
                        ),
                    ),
                ),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Symbol(if (plan.isTodayComplete) R.drawable.ic_widget_check else R.drawable.ic_widget_circle, size = 16)
                Spacer(GlanceModifier.width(5.dp))
                Text(
                    string(if (plan.isTodayComplete) R.string.done else R.string.mark_read),
                    style = TextStyle(color = WidgetPalette.accent, fontWeight = FontWeight.Bold, fontSize = 12.sp),
                )
            }
        }
    }

    private companion object {
        val MEDIUM = DpSize(250.dp, 110.dp)
    }
}

/** Ticks (or unticks) a plan day from the widget, then redraws every widget. */
class MarkPlanDayAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val id = parameters[ENROLLMENT] ?: return
        val day = parameters[DAY] ?: return
        val completed = parameters[COMPLETED] ?: true
        val app = context.applicationContext as VerselyApplication
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { app.userData.plans.setDay(day, completed, id) }
        VerselyWidgets.refresh(context)
    }

    companion object {
        val ENROLLMENT = ActionParameters.Key<String>("enrollment")
        val DAY = ActionParameters.Key<Int>("day")
        val COMPLETED = ActionParameters.Key<Boolean>("completed")
    }
}

// Memorize (Premium)

/** The next passage to recall, as its opening words, and how many are due. Premium; a message otherwise. */
class MemoriseWidget : VerselyWidget() {
    @Composable
    override fun Content(data: WidgetData) {
        val small = LocalSize.current.width < 250.dp
        WidgetCard(GenesisLink.MEMORISE, small = small) {
            val memorise = data.memorise
            if (!data.isPremium || memorise == null) {
                Symbol(R.drawable.ic_widget_memorise, size = 22)
                Spacer(GlanceModifier.height(8.dp))
                Text(
                    string(if (!data.isPremium) R.string.widget_memorise_locked else R.string.widget_memorise_empty),
                    style = TextStyle(color = WidgetPalette.text, fontFamily = FontFamily.Serif, fontSize = 13.sp),
                )
                return@WidgetCard
            }
            Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Eyebrow(string(R.string.memorise))
                Spacer(GlanceModifier.defaultWeight())
                if (memorise.due > 0) Text(string(R.string.memorise_due_count, memorise.due), style = TextStyle(color = WidgetPalette.accent, fontWeight = FontWeight.Bold, fontSize = 11.sp))
            }
            Spacer(GlanceModifier.height(8.dp))
            Headline(memorise.reference, size = if (small) 16 else 19, maxLines = 1)
            Spacer(GlanceModifier.height(4.dp))
            memorise.hint?.let { Caption(it, maxLines = if (small) 3 else 2, serif = true, size = if (small) 12 else 14) }
            Spacer(GlanceModifier.defaultWeight())
            Caption(string(if (memorise.due > 0) R.string.tap_to_review else R.string.memorise_caught_up), size = 11)
        }
    }
}

class ContinueReadingReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ContinueReadingWidget()
}

class ReadingProgressReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ReadingProgressWidget()
}

class StreakReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = StreakWidget()
}

class PrayerReminderReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = PrayerReminderWidget()
}

class TodaysReadingReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodaysReadingWidget()
}

class MemoriseReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = MemoriseWidget()
}
