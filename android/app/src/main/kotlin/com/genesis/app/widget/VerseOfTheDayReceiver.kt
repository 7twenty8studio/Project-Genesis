package com.genesis.app.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import com.genesis.core.domain.widgets.VerseWidgetSchedule
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * Hosts the verse widget and moves it on when its verse changes, as the iOS
 * timeline does: Random Verse and the categories every three hours, the
 * others at local midnight (which is also a three-hour boundary). An inexact
 * alarm (no exact-alarm permission) a minute after the next boundary asks
 * for an update, which schedules the one after.
 */
class VerseOfTheDayReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = VerseOfTheDayWidget()

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        scheduleNextChange(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        context.getSystemService(AlarmManager::class.java)?.cancel(changeIntent(context))
    }

    companion object {
        fun scheduleNextChange(context: Context) {
            val zone = ZoneId.systemDefault()
            val next = VerseWidgetSchedule.nextChange(LocalDateTime.now(zone), rotates = true)
            val at = next.atZone(zone).plusMinutes(1).toInstant().toEpochMilli()
            context.getSystemService(AlarmManager::class.java)
                ?.setWindow(AlarmManager.RTC, at, 15 * 60 * 1000L, changeIntent(context))
        }

        private fun changeIntent(context: Context): PendingIntent {
            val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, VerseOfTheDayReceiver::class.java))
            val intent = Intent(context, VerseOfTheDayReceiver::class.java)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
    }
}
