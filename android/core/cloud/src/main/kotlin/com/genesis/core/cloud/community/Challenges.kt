package com.genesis.core.cloud.community

import com.genesis.core.cloud.SupabaseClient
import com.genesis.core.cloud.SupabaseError
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.time.LocalDate
import java.time.temporal.ChronoUnit

// Group challenges, as GroupChallenge.swift: reading, memorizing, a daily
// reading streak or daily prayer, done together for 1 to 90 days. Rows of
// public.group_challenges (20261011000000_group_moderation_challenges.sql).
// Only ids are stored (chapters, verses); the words always come from the
// Bible on the device.

enum class ChallengeKind(val rawValue: String, val defaultDays: Int, val suggestedDays: List<Int>) {
    READING("reading", 14, listOf(7, 14, 30)),
    MEMORISE("memorise", 7, listOf(7, 14)),
    STREAK("streak", 21, listOf(7, 21, 30)),
    PRAYER("prayer", 7, listOf(7, 21, 30)),
    ;

    /** Ticked one day at a time. */
    val isDaily: Boolean get() = this == STREAK || this == PRAYER

    companion object {
        fun of(raw: String): ChallengeKind? = entries.firstOrNull { it.rawValue == raw }
    }
}

enum class ChallengeStatus { RUNNING, UPCOMING, FINISHED }

/** The rules every challenge shares (the server checks them too). */
object ChallengeRules {
    val dayRange = 1..90
    val titleLength = 1..80
    const val DETAILS_LENGTH = 500
    /** Challenges a group can run (or have waiting) at once. */
    const val MAXIMUM_RUNNING = 5
    /** How far ahead a challenge can be scheduled. */
    const val LATEST_START_DAYS = 60
    /** The most verses in a memorize challenge, as in Memorize itself. */
    const val MAXIMUM_VERSES = 15
    /** The item "I've learned it" ticks in a memorize challenge. */
    const val LEARNED_ITEM = 1
}

/** A challenge in a group. */
data class GroupChallenge(
    val id: String,
    val groupId: String,
    val createdBy: String?,
    val kind: ChallengeKind,
    val title: String,
    val details: String,
    /** The first day, a calendar day. */
    val start: LocalDate,
    val days: Int,
    /** Reading: the chapters (book * 1000 + chapter), in order. */
    val chapters: List<Int> = emptyList(),
    /** Memorize: the passage (verse ids) and the Bible it's learned in. */
    val verseStart: Int? = null,
    val verseEnd: Int? = null,
    val translationId: String? = null,
    /** Set when a moderator ended it early: it stays, finished, with everyone's progress. */
    val endedAt: String? = null,
) {
    val end: LocalDate get() = start.plusDays(days - 1L)

    /** 1 on the first day, `days` on the last; below 1 before, above `days` after. */
    fun dayIndex(today: LocalDate): Int = ChronoUnit.DAYS.between(start, today).toInt() + 1

    fun status(today: LocalDate): ChallengeStatus {
        if (endedAt != null) return ChallengeStatus.FINISHED
        val index = dayIndex(today)
        return when {
            index < 1 -> ChallengeStatus.UPCOMING
            index > days -> ChallengeStatus.FINISHED
            else -> ChallengeStatus.RUNNING
        }
    }

    /** Today's day while it runs, kept within 1..days. */
    fun currentDay(today: LocalDate): Int = dayIndex(today).coerceIn(1, days)

    /** How many things each member can tick: chapters, days, or 1 passage. */
    val itemCount: Int
        get() = when (kind) {
            ChallengeKind.READING -> chapters.size
            ChallengeKind.MEMORISE -> 1
            ChallengeKind.STREAK, ChallengeKind.PRAYER -> days
        }

    /** Whether `item` can be ticked today, as set_challenge_checkin decides (a day's slack either side). */
    fun canTick(item: Int, today: LocalDate): Boolean {
        val index = dayIndex(today)
        if (endedAt != null || index < 0 || index > days + 1) return false
        return when (kind) {
            ChallengeKind.READING -> item in chapters
            ChallengeKind.MEMORISE -> item == ChallengeRules.LEARNED_ITEM
            ChallengeKind.STREAK, ChallengeKind.PRAYER -> item in 1..days && item <= index + 1
        }
    }
}

/** One member's progress (a row of group_challenge_progress); `items` is null for other people's chapters. */
@Serializable
data class ChallengeProgress(
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String = "",
    val done: Int = 0,
    val items: List<Int>? = null,
)

/** Daily streaks from the days someone ticked. */
object ChallengeStreak {
    /** Days in a row up to today, or up to yesterday if today isn't ticked yet. */
    fun current(ticked: Set<Int>, today: Int): Int {
        var day = if (today in ticked) today else today - 1
        var count = 0
        while (day >= 1 && day in ticked) {
            count++
            day--
        }
        return count
    }

    /** Still going: today or yesterday is ticked; on the first day nobody has missed anything. */
    fun isAlive(ticked: Set<Int>, today: Int): Boolean = today <= 1 || today in ticked || (today - 1) in ticked
}

/** Totals for a challenge: how the group is doing together, and how you are. Never a ranking. */
data class ChallengeSummary(
    val itemCount: Int,
    val memberCount: Int,
    val myItems: Set<Int>,
    val myDone: Int,
    val groupDone: Int,
    val day: Int,
    val stillGoing: Int,
) {
    val groupFraction: Float get() = fraction(groupDone, itemCount * memberCount)
    val myFraction: Float get() = fraction(myDone, itemCount)
    val myStreak: Int get() = ChallengeStreak.current(myItems, day)

    companion object {
        fun fraction(done: Int, total: Int): Float = if (total > 0) (done.toFloat() / total).coerceIn(0f, 1f) else 0f

        fun of(challenge: GroupChallenge, rows: List<ChallengeProgress>, me: String?, today: LocalDate): ChallengeSummary {
            val mine = rows.firstOrNull { me != null && it.userId.equals(me, ignoreCase = true) }
            val day = challenge.currentDay(today)
            return ChallengeSummary(
                itemCount = challenge.itemCount,
                memberCount = rows.size,
                myItems = mine?.items.orEmpty().toSet(),
                myDone = minOf(mine?.done ?: 0, challenge.itemCount),
                groupDone = rows.sumOf { it.done.coerceIn(0, challenge.itemCount) },
                day = day,
                stillGoing = if (challenge.kind.isDaily) rows.count { ChallengeStreak.isAlive(it.items.orEmpty().toSet(), day) } else 0,
            )
        }
    }
}

/** Chapters as the server stores them (book * 1000 + chapter). */
object ChallengeChapters {
    fun raw(book: Int, chapter: Int): Int = book * 1_000 + chapter
    fun book(raw: Int): Int = raw / 1_000
    fun chapter(raw: Int): Int = raw % 1_000

    /** A chapter range in one book, kept within the book's `count` chapters. */
    fun range(book: Int, from: Int, through: Int, count: Int): List<Int> {
        if (book !in 1..66 || count < 1) return emptyList()
        val lower = from.coerceIn(1, count)
        val upper = through.coerceIn(lower, count)
        return (lower..upper).map { raw(book, it) }
    }
}

/** What a leader fills in to start a challenge. */
data class ChallengeDraft(
    val kind: ChallengeKind,
    val title: String,
    val details: String,
    val start: LocalDate,
    val days: Int,
    val chapters: List<Int> = emptyList(),
    val verseStart: Int? = null,
    val verseEnd: Int? = null,
    val translationId: String? = null,
) {
    /** Whether the server would accept it (it checks again). */
    fun isValid(today: LocalDate): Boolean {
        if (title.trim().length !in ChallengeRules.titleLength || details.trim().length > ChallengeRules.DETAILS_LENGTH || days !in ChallengeRules.dayRange) return false
        val offset = ChronoUnit.DAYS.between(today, start)
        if (offset !in -1..ChallengeRules.LATEST_START_DAYS.toLong()) return false
        return when (kind) {
            ChallengeKind.READING -> chapters.isNotEmpty() && chapters.size <= 1_189
            ChallengeKind.MEMORISE -> {
                val first = verseStart ?: return false
                val last = verseEnd ?: return false
                !translationId.isNullOrEmpty() && first / 1_000_000 == last / 1_000_000 && last >= first && first / 1_000_000 in 1..66
            }
            ChallengeKind.STREAK, ChallengeKind.PRAYER -> true
        }
    }
}

/** The challenge functions' error codes, which `CommunityError.Code` carries. */
object ChallengeErrors {
    val codes = setOf("moderators_only", "invalid_challenge", "too_many_challenges", "challenge_ended", "not_started", "invalid_item")
}

/** Group challenges on the server (SupabaseGroupChallengeBackend on iOS). */
class ChallengeApi(private val client: SupabaseClient, private val token: () -> String) {
    private val json = Json { ignoreUnknownKeys = true }

    private fun <T> wrap(block: () -> T): T = try {
        block()
    } catch (error: SupabaseError) {
        val code = ChallengeErrors.codes.firstOrNull { error.message?.contains(it) == true }
        throw if (code != null) CommunityError.Code(code) else CommunityError.from(error)
    } catch (error: Throwable) {
        throw CommunityError.from(error)
    }

    private fun rpc(name: String, vararg params: Pair<String, JsonElement>): String = wrap {
        client.rpc(name, buildJsonObject { params.forEach { (key, value) -> put(key, value) } }.toString(), token())
    }

    @Serializable
    private data class Row(
        val id: String,
        @SerialName("group_id") val groupId: String,
        @SerialName("created_by") val createdBy: String? = null,
        val kind: String,
        val title: String,
        val details: String? = null,
        @SerialName("starts_on") val startsOn: String,
        val days: Int,
        val chapters: List<Int>? = null,
        @SerialName("verse_start") val verseStart: Int? = null,
        @SerialName("verse_end") val verseEnd: Int? = null,
        @SerialName("translation_id") val translationId: String? = null,
        @SerialName("ended_at") val endedAt: String? = null,
    ) {
        fun challenge(): GroupChallenge? {
            val kind = ChallengeKind.of(kind) ?: return null
            if (days !in ChallengeRules.dayRange) return null
            val start = runCatching { LocalDate.parse(startsOn.take(10)) }.getOrNull() ?: return null
            return GroupChallenge(
                id = id.lowercase(), groupId = groupId.lowercase(), createdBy = createdBy?.lowercase(), kind = kind, title = title,
                details = details.orEmpty(), start = start, days = days,
                // Only real chapters, whatever the server holds.
                chapters = chapters.orEmpty().filter { it / 1_000 in 1..66 && it % 1_000 > 0 },
                verseStart = verseStart, verseEnd = verseEnd, translationId = translationId, endedAt = endedAt,
            )
        }
    }

    /** The group's challenges, running, waiting and finished (ended ones too). */
    fun challenges(group: String): List<GroupChallenge> = wrap {
        val reply = client.select(
            "group_challenges",
            listOf(
                "select" to "id,group_id,created_by,kind,title,details,starts_on,days,chapters,verse_start,verse_end,translation_id,created_at,ended_at",
                "group_id" to "eq.$group",
                "order" to "starts_on.desc,created_at.desc",
                "limit" to "60",
            ),
            token(),
        )
        json.decodeFromString<List<Row>>(reply.ifBlank { "[]" }).mapNotNull { it.challenge() }
    }

    /** Owners and moderators only; the new challenge's id. */
    fun create(draft: ChallengeDraft, group: String): String {
        val reading = draft.kind == ChallengeKind.READING
        val memorise = draft.kind == ChallengeKind.MEMORISE
        val reply = rpc(
            "create_group_challenge",
            "p_group" to JsonPrimitive(group),
            "p_kind" to JsonPrimitive(draft.kind.rawValue),
            "p_title" to JsonPrimitive(draft.title.trim()),
            "p_details" to JsonPrimitive(draft.details.trim()),
            "p_starts_on" to JsonPrimitive(draft.start.toString()),
            "p_days" to JsonPrimitive(draft.days),
            "p_chapters" to if (reading) JsonArray(draft.chapters.map(::JsonPrimitive)) else JsonNull,
            "p_verse_start" to (draft.verseStart?.takeIf { memorise }?.let(::JsonPrimitive) ?: JsonNull),
            "p_verse_end" to (draft.verseEnd?.takeIf { memorise }?.let(::JsonPrimitive) ?: JsonNull),
            "p_translation" to (draft.translationId?.takeIf { memorise }?.let(::JsonPrimitive) ?: JsonNull),
        )
        return reply.trim().trim('"').lowercase().takeIf { it.length >= 32 } ?: throw CommunityError.Unknown()
    }

    /** Owners and moderators: stops early, keeping everyone's progress. */
    fun end(challenge: String) {
        rpc("end_group_challenge", "p_challenge" to JsonPrimitive(challenge))
    }

    /** Ticks (or unticks) a chapter, a day, or "I've learned it". */
    fun setCheckin(done: Boolean, item: Int, challenge: String) {
        rpc("set_challenge_checkin", "p_challenge" to JsonPrimitive(challenge), "p_item" to JsonPrimitive(item), "p_done" to JsonPrimitive(done))
    }

    fun progress(challenge: String): List<ChallengeProgress> = wrap {
        json.decodeFromString<List<ChallengeProgress>>(rpc("group_challenge_progress", "p_challenge" to JsonPrimitive(challenge)).ifBlank { "[]" }.let { if (it == "null") "[]" else it })
    }
}
