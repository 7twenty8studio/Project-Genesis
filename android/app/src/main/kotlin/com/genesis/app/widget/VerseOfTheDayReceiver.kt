package com.genesis.app.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import java.time.LocalDate
import java.time.ZoneId

/**
 * Hosts the Verse of the Day widget and turns it over at local midnight, as
 * the iOS timeline does: an inexact alarm (no exact-alarm permission needed)
 * a minute after midnight asks for an update, which schedules the next one.
 */
class VerseOfTheDayReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = VerseOfTheDayWidget()

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        scheduleMidnight(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        context.getSystemService(AlarmManager::class.java)?.cancel(midnightIntent(context))
    }

    private fun scheduleMidnight(context: Context) {
        val zone = ZoneId.systemDefault()
        val at = LocalDate.now(zone).plusDays(1).atStartOfDay(zone).plusMinutes(1).toInstant().toEpochMilli()
        context.getSystemService(AlarmManager::class.java)
            ?.setWindow(AlarmManager.RTC, at, 15 * 60 * 1000L, midnightIntent(context))
    }

    private fun midnightIntent(context: Context): PendingIntent {
        val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, VerseOfTheDayReceiver::class.java))
        val intent = Intent(context, VerseOfTheDayReceiver::class.java)
            .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}
