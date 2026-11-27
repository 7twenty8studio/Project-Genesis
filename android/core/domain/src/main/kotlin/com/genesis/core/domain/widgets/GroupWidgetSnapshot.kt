package com.genesis.core.domain.widgets

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * The last group opened that has a reading plan, as GroupWidgetSnapshot on
 * iOS: written by the group's screen each time it loads (names as members
 * show them in the group, and how far each has read), read by the widget.
 */
@Serializable
data class GroupWidgetSnapshot(
    val groupId: String,
    val groupName: String,
    val planTitle: String,
    /** Today's day in the plan (0 before it starts). */
    val day: Int,
    val dayCount: Int,
    val dayTitle: String? = null,
    val readTodayCount: Int,
    val memberCount: Int,
    val members: List<Member>,
    /** The day it was written (yyyy-MM-dd): who read "today" is only known for that day. */
    val writtenOn: String,
) {
    @Serializable
    data class Member(val name: String, val fraction: Double, val readToday: Boolean)

    fun encoded(): String = json.encodeToString(serializer(), this)

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun decode(text: String): GroupWidgetSnapshot? = runCatching { json.decodeFromString(serializer(), text) }.getOrNull()
    }
}
