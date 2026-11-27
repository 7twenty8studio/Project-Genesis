package com.genesis.app.notifications

import android.content.Context
import androidx.core.content.edit
import com.genesis.core.domain.notifications.NotificationSettings
import com.genesis.core.domain.notifications.ReminderKind
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * What the person wants to be notified about, and when (Settings ›
 * Notifications), as NotificationPreferences on iOS, with the same keys.
 * Saved on the device. "Allow Notifications" off silences everything and
 * keeps each choice.
 */
class NotificationPreferences(context: Context) {
    private val defaults = context.getSharedPreferences("notifications", Context.MODE_PRIVATE)
    private val _settings = MutableStateFlow(read())

    /** The choices, every kind's switch and time (the master switch apart). */
    val state: StateFlow<State> = _settings.asStateFlow()

    data class State(
        val allowsNotifications: Boolean,
        val on: Map<ReminderKind, Boolean>,
        val minutes: Map<ReminderKind, Int>,
        /** The Home card inviting notifications was answered (either way). */
        val hasAnsweredInvite: Boolean = false,
    ) {
        fun isOn(kind: ReminderKind): Boolean = on[kind] ?: kind.isOnByDefault
        fun allows(kind: ReminderKind): Boolean = allowsNotifications && isOn(kind)
        fun minutes(kind: ReminderKind): Int = minutes[kind] ?: kind.defaultMinutes

        val settings: NotificationSettings
            get() = NotificationSettings(ReminderKind.entries.filter(::allows).toSet(), ReminderKind.entries.associateWith(::minutes))
    }

    fun setAllowsNotifications(value: Boolean) {
        defaults.edit { putBoolean(MASTER, value) }
        _settings.value = read()
    }

    fun set(kind: ReminderKind, on: Boolean) {
        defaults.edit { putBoolean(onKey(kind), on) }
        _settings.value = read()
    }

    fun answerInvite() {
        defaults.edit { putBoolean(INVITE, true) }
        _settings.value = read()
    }

    fun setMinutes(kind: ReminderKind, minutes: Int) {
        defaults.edit { putInt(minutesKey(kind), minutes.coerceIn(0, 24 * 60 - 1)) }
        _settings.value = read()
    }

    private fun read() = State(
        allowsNotifications = defaults.getBoolean(MASTER, true),
        on = ReminderKind.entries.associateWith { defaults.getBoolean(onKey(it), it.isOnByDefault) },
        minutes = ReminderKind.entries.associateWith { defaults.getInt(minutesKey(it), it.defaultMinutes).coerceIn(0, 24 * 60 - 1) },
        hasAnsweredInvite = defaults.getBoolean(INVITE, false),
    )

    private companion object {
        const val MASTER = "notifications.allowed"
        const val INVITE = "notifications.inviteAnswered"
        fun onKey(kind: ReminderKind) = "notifications.${kind.rawValue}.on"
        fun minutesKey(kind: ReminderKind) = "notifications.${kind.rawValue}.minutes"
    }
}
