package com.genesis.app.journal

import androidx.annotation.StringRes
import com.genesis.app.R
import com.genesis.core.domain.journal.JournalTemplate

/** A template's words: its title and each part's heading and prompt (as JournalTemplate on iOS). */
internal data class TemplateWords(@StringRes val title: Int, val parts: List<Pair<Int, Int>>)

internal val JournalTemplate.words: TemplateWords get() = when (this) {
    JournalTemplate.ACTS -> TemplateWords(R.string.tpl_acts, listOf(R.string.tpl_acts_h0 to R.string.tpl_acts_p0, R.string.tpl_acts_h1 to R.string.tpl_acts_p1, R.string.tpl_acts_h2 to R.string.tpl_acts_p2, R.string.tpl_acts_h3 to R.string.tpl_acts_p3))
    JournalTemplate.GRATITUDE -> TemplateWords(R.string.tpl_gratitude, listOf(R.string.tpl_gratitude_h0 to R.string.tpl_gratitude_p0, R.string.tpl_gratitude_h1 to R.string.tpl_gratitude_p1, R.string.tpl_gratitude_h2 to R.string.tpl_gratitude_p2))
    JournalTemplate.FOR_OTHERS -> TemplateWords(R.string.tpl_for_others, listOf(R.string.tpl_for_others_h0 to R.string.tpl_for_others_p0, R.string.tpl_for_others_h1 to R.string.tpl_for_others_p1, R.string.tpl_for_others_h2 to R.string.tpl_for_others_p2, R.string.tpl_for_others_h3 to R.string.tpl_for_others_p3))
    JournalTemplate.LAMENT -> TemplateWords(R.string.tpl_lament, listOf(R.string.tpl_lament_h0 to R.string.tpl_lament_p0, R.string.tpl_lament_h1 to R.string.tpl_lament_p1, R.string.tpl_lament_h2 to R.string.tpl_lament_p2, R.string.tpl_lament_h3 to R.string.tpl_lament_p3))
    JournalTemplate.MORNING_OFFERING -> TemplateWords(R.string.tpl_morning_offering, listOf(R.string.tpl_morning_offering_h0 to R.string.tpl_morning_offering_p0, R.string.tpl_morning_offering_h1 to R.string.tpl_morning_offering_p1, R.string.tpl_morning_offering_h2 to R.string.tpl_morning_offering_p2))
    JournalTemplate.MAIN_POINTS -> TemplateWords(R.string.tpl_main_points, listOf(R.string.tpl_main_points_h0 to R.string.tpl_main_points_p0, R.string.tpl_main_points_h1 to R.string.tpl_main_points_p1, R.string.tpl_main_points_h2 to R.string.tpl_main_points_p2))
    JournalTemplate.OBSERVATION -> TemplateWords(R.string.tpl_observation, listOf(R.string.tpl_observation_h0 to R.string.tpl_observation_p0, R.string.tpl_observation_h1 to R.string.tpl_observation_p1, R.string.tpl_observation_h2 to R.string.tpl_observation_p2))
    JournalTemplate.DISCUSSION -> TemplateWords(R.string.tpl_discussion, listOf(R.string.tpl_discussion_h0 to R.string.tpl_discussion_p0, R.string.tpl_discussion_h1 to R.string.tpl_discussion_p1, R.string.tpl_discussion_h2 to R.string.tpl_discussion_p2))
    JournalTemplate.OUTLINE -> TemplateWords(R.string.tpl_outline, listOf(R.string.tpl_outline_h0 to R.string.tpl_outline_p0, R.string.tpl_outline_h1 to R.string.tpl_outline_p1, R.string.tpl_outline_h2 to R.string.tpl_outline_p2))
}
