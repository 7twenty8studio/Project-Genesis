package com.genesis.app.goals

import android.content.Context
import androidx.core.content.edit
import com.genesis.core.domain.goals.ReadingGoal
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * The person's goal and streak settings (Settings › Goals & Streaks), as
 * GoalPreferences on iOS: the daily goal, streak shields (on by default)
 * and the milestones already celebrated. Kept on the device.
 */
class GoalPreferences(context: Context) {
    data class State(
        val goal: ReadingGoal,
        val usesStreakShields: Boolean,
        val celebrated: Set<String>,
        /** False before milestones were ever looked at (no parade for existing readers). */
        val hasCelebratedAny: Boolean,
    )

    private val defaults = context.getSharedPreferences("goals", Context.MODE_PRIVATE)
    private val _state = MutableStateFlow(load())
    val state: StateFlow<State> = _state.asStateFlow()

    private fun load() = State(
        goal = ReadingGoal.of(defaults.getString(GOAL, null)),
        usesStreakShields = defaults.getBoolean(SHIELDS, true),
        celebrated = defaults.getStringSet(CELEBRATED, emptySet()).orEmpty(),
        hasCelebratedAny = defaults.contains(CELEBRATED),
    )

    fun setGoal(goal: ReadingGoal) {
        defaults.edit { putString(GOAL, goal.rawValue) }
        _state.update { it.copy(goal = goal) }
    }

    fun setStreakShields(on: Boolean) {
        defaults.edit { putBoolean(SHIELDS, on) }
        _state.update { it.copy(usesStreakShields = on) }
    }

    fun markCelebrated(ids: Collection<String>) {
        val all = _state.value.celebrated + ids
        defaults.edit { putStringSet(CELEBRATED, all) }
        _state.update { it.copy(celebrated = all, hasCelebratedAny = true) }
    }

    private companion object {
        const val GOAL = "goals.daily"
        const val SHIELDS = "goals.streakShields"
        const val CELEBRATED = "goals.celebratedMilestones"
    }
}
