package com.genesis.core.domain.features

/**
 * Parts of Versely people can switch off for a simpler app, as
 * OptionalFeature on iOS (same raw values). Reading, notes, highlights,
 * bookmarks, search and the Bibles library are always there. Every
 * optional feature gets its own case. Hiding never deletes anything.
 */
enum class OptionalFeature(val rawValue: String, val area: Area, val isOfferedInSetup: Boolean = true) {
    PLANS("plans", Area.DAILY),
    PRAYER("prayer", Area.DAILY),
    MEMORISE("memorise", Area.DAILY),
    LISTEN("listen", Area.LISTENING),
    AMBIENT_SOUNDS("ambientSounds", Area.LISTENING, isOfferedInSetup = false),
    WORD_STUDY("wordStudy", Area.STUDY),
    EXPLORE("explore", Area.STUDY),
    STUDY_ASSISTANT("studyAssistant", Area.STUDY),
    INSIGHTS("insights", Area.TOUCHES, isOfferedInSetup = false),
    MOMENTS("moments", Area.TOUCHES, isOfferedInSetup = false),
    TOGETHER("together", Area.COMMUNITY),
    SERMONS("sermons", Area.STUDY),
    STUDY_LIBRARY("studyLibrary", Area.STUDY),
    GOALS("goals", Area.DAILY),
    NUDGES("nudges", Area.COMMUNITY, isOfferedInSetup = false),
    CHURCH_SERMONS("churchSermons", Area.COMMUNITY, isOfferedInSetup = false),
    ;

    /** How Settings › Features groups the switches. */
    enum class Area { DAILY, STUDY, LISTENING, COMMUNITY, TOUCHES }

    companion object {
        fun of(raw: String): OptionalFeature? = entries.firstOrNull { it.rawValue == raw }

        /** On for someone who sets up Versely without changing anything; groups and the community are opt-in. */
        val defaults: Set<OptionalFeature> = entries.toSet() - TOGETHER

        /**
         * A saved choice read with today's switches: one the choice didn't
         * know starts on (nudges start the way Groups & Community was).
         */
        fun migrated(saved: Set<String>, known: Set<String>): Set<OptionalFeature> {
            val result = saved.mapNotNull(::of).toMutableSet()
            for (feature in entries) {
                if (feature.rawValue in known) continue
                val on = if (feature == NUDGES) TOGETHER.rawValue in saved else true
                if (on) result += feature
            }
            return result
        }

        /**
         * Whether the feature exists right now: the server has it switched
         * on (for those behind a switch). The study assistant isn't part of
         * Versely for Android.
         */
        fun isAvailable(feature: OptionalFeature, flags: Map<String, Boolean>): Boolean = when (feature) {
            STUDY_ASSISTANT -> false
            TOGETHER -> flags["groups"] == true || flags["community"] == true
            NUDGES -> flags["groups"] == true
            // A church is a group, so its sermons need groups too.
            CHURCH_SERMONS -> flags["church_sermons"] == true && flags["groups"] == true
            else -> true
        }
    }
}
