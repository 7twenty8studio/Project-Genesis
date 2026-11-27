package com.genesis.core.domain.features

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class OptionalFeatureTest {
    @Test fun rawValuesMatchIOS() {
        assertEquals(
            listOf("plans", "prayer", "memorise", "listen", "ambientSounds", "wordStudy", "explore", "studyAssistant", "insights", "moments", "together", "sermons", "studyLibrary", "goals", "nudges", "churchSermons"),
            OptionalFeature.entries.map { it.rawValue },
        )
        assertFalse(OptionalFeature.TOGETHER in OptionalFeature.defaults)
    }

    @Test fun newSwitchesStartOnAndNudgesFollowGroups() {
        val known = OptionalFeature.entries.map { it.rawValue }.toSet() - "goals" - "nudges"
        val withGroups = OptionalFeature.migrated(setOf("plans", "together"), known)
        assertEquals(setOf(OptionalFeature.PLANS, OptionalFeature.TOGETHER, OptionalFeature.GOALS, OptionalFeature.NUDGES), withGroups)
        val without = OptionalFeature.migrated(setOf("plans"), known)
        assertFalse(OptionalFeature.NUDGES in without)
        assertTrue(OptionalFeature.GOALS in without)
    }

    @Test fun availability() {
        val flags = mapOf("groups" to true, "church_sermons" to false)
        assertTrue(OptionalFeature.isAvailable(OptionalFeature.TOGETHER, flags))
        assertFalse(OptionalFeature.isAvailable(OptionalFeature.CHURCH_SERMONS, flags))
        assertFalse(OptionalFeature.isAvailable(OptionalFeature.STUDY_ASSISTANT, mapOf("study_assistant" to true)))
        assertTrue(OptionalFeature.isAvailable(OptionalFeature.PLANS, emptyMap()))
    }
}
