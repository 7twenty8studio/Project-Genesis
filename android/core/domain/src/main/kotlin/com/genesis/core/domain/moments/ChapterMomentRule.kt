package com.genesis.core.domain.moments

import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.welcome.MorningWelcomeRules
import java.time.LocalDate

/** "Once per chapter per day": the rule behind chapter-complete moments (ChapterMomentRule on iOS). */
object ChapterMomentRule {
    /** "2026-10-06|chapter:43003" or "2026-10-06|plan:<id>:12". */
    fun key(subject: String, on: LocalDate): String = "${MorningWelcomeRules.dayKey(on)}|$subject"

    fun chapterSubject(chapter: ChapterId): String = "chapter:${chapter.book * 1_000 + chapter.chapter}"

    fun planDaySubject(planId: String, day: Int): String = "plan:$planId:$day"

    fun shouldCelebrate(key: String, alreadyCelebrated: Set<String>): Boolean = key !in alreadyCelebrated

    /** Only today's keys are worth keeping. */
    fun pruned(keys: Set<String>, on: LocalDate): Set<String> {
        val prefix = MorningWelcomeRules.dayKey(on) + "|"
        return keys.filterTo(mutableSetOf()) { it.startsWith(prefix) }
    }
}
