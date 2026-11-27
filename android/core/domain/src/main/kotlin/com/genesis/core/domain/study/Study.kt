package com.genesis.core.domain.study

import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.VerseId
import java.text.Normalizer

/**
 * People, places and events for Explore, as StudyModels.swift on iOS. Read
 * from the bundled Study.sqlite (Theographic, OpenBible.info, Easton's):
 * verse ids only, never Scripture text.
 */

/** A period of the story on the timeline (Creation, Noah, … Revelation). */
data class Era(
    val id: String,
    val title: String,
    val summary: String,
    /** False for Creation and Noah, shown in order without dates. */
    val isDated: Boolean,
    val firstVerse: VerseId,
)

data class TimelineEvent(
    val id: Int,
    val title: String,
    val eraId: String,
    /** Astronomical year (0 = 1 BC); null where no date is shown. */
    val year: Int?,
    val firstVerse: VerseId?,
    val lastVerse: VerseId?,
)

/** A year for "c. %@ BC" (true) or "c. AD %@" (false), as plain digits. */
data class ApproximateYear(val digits: String, val beforeChrist: Boolean) {
    companion object {
        fun of(year: Int): ApproximateYear = if (year <= 0) ApproximateYear((1 - year).toString(), true) else ApproximateYear(year.toString(), false)
    }
}

/** The span of an era's dated events: (earliest, latest), or null. */
fun yearRange(era: Era, events: List<TimelineEvent>): Pair<Int, Int>? {
    if (!era.isDated) return null
    val years = events.mapNotNull { it.year }
    val first = years.minOrNull() ?: return null
    return first to years.max()
}

data class PersonSummary(val id: Int, val name: String, val alsoCalled: String, val verseCount: Int) {
    companion object {
        fun of(id: Int, name: String, alsoCalled: String, verseCount: Int) =
            PersonSummary(id, name, OtherNames.distinct(alsoCalled, name), verseCount)
    }
}

/**
 * Other names without repeats or the name itself: a translation can spell
 * two names alike ("Lucas", also called "Lucas"), and then there's nothing to add.
 */
object OtherNames {
    fun distinct(other: String, besides: String): String {
        if (other.isEmpty()) return other
        val seen = mutableSetOf(fold(besides.substringBefore('(')))
        return other.split(',').map { it.trim() }.filter { it.isNotEmpty() && seen.add(fold(it)) }.joinToString(", ")
    }

    private val marks = Regex("\\p{Mn}+")

    fun fold(text: String): String = Normalizer.normalize(text.trim(), Normalizer.Form.NFD).replace(marks, "").lowercase()
}

data class Person(
    val summary: PersonSummary,
    val gender: String,
    /** From Easton's Bible Dictionary (1897, public domain). Not Scripture. */
    val biography: String,
    val birthYear: Int?,
    val deathYear: Int?,
    /** Theographic's groups, comma separated ("Tribe of Judah,Apostles"); may be empty. */
    val group: String,
    val firstVerse: VerseId?,
    /** True when the biography is a translation of Easton's English. */
    val biographyIsTranslated: Boolean = false,
) {
    val id: Int get() = summary.id
    val name: String get() = summary.name
    val groups: List<String> get() = group.split(',').map { it.trim() }.filter { it.isNotEmpty() }
}

enum class RelationKind(val rawValue: String) { FATHER("father"), MOTHER("mother"), PARTNER("partner"), CHILD("child"), SIBLING("sibling") }

/** A person's immediate family, for the family tree. */
data class Family(
    val parents: List<PersonSummary> = emptyList(),
    val partners: List<PersonSummary> = emptyList(),
    val siblings: List<PersonSummary> = emptyList(),
    val children: List<PersonSummary> = emptyList(),
) {
    val isEmpty: Boolean get() = parents.isEmpty() && partners.isEmpty() && siblings.isEmpty() && children.isEmpty()

    companion object {
        /** Rows in the database's order (most mentioned first); fathers before mothers, as in the genealogies. */
        fun of(rows: List<Pair<String, PersonSummary>>): Family {
            val fathers = rows.filter { it.first == RelationKind.FATHER.rawValue }.map { it.second }
            val mothers = rows.filter { it.first == RelationKind.MOTHER.rawValue }.map { it.second }
            fun kind(kind: RelationKind) = rows.filter { it.first == kind.rawValue }.map { it.second }
            return Family(fathers + mothers, kind(RelationKind.PARTNER), kind(RelationKind.SIBLING), kind(RelationKind.CHILD))
        }
    }
}

data class PlaceSummary(
    val id: Int,
    val name: String,
    /** "City", "Region", "Mountain", …; empty where the data doesn't say. */
    val kind: String,
    val latitude: Double?,
    val longitude: Double?,
    val verseCount: Int,
    /** How sure scholars are of the location, 0–1000 (OpenBible.info); null when unknown. */
    val confidence: Int? = null,
) {
    val isMapped: Boolean get() = latitude != null && longitude != null
    val certainty: PlaceCertainty get() = PlaceCertainty.of(confidence)
}

/** How sure we can be where a place was, from OpenBible.info's confidence score. */
enum class PlaceCertainty {
    KNOWN, LIKELY, UNCERTAIN;

    companion object {
        fun of(confidence: Int?): PlaceCertainty = when (confidence ?: 0) {
            in 750..Int.MAX_VALUE -> KNOWN
            in 500 until 750 -> LIKELY
            else -> UNCERTAIN
        }
    }
}

data class Place(
    val summary: PlaceSummary,
    val aliases: String,
    /** From Easton's Bible Dictionary (public domain). Not Scripture. */
    val description: String,
    /** False where the location is uncertain (the pin marks the general area). */
    val isPrecise: Boolean,
    val firstVerse: VerseId?,
    val descriptionIsTranslated: Boolean = false,
) {
    val id: Int get() = summary.id
    val name: String get() = summary.name
}

data class RoutePoint(val latitude: Double, val longitude: Double)

/** A journey drawn on the map: Paul's journeys and a traditional Exodus route. */
data class Route(
    val id: String,
    val title: String,
    val passage: String,
    val firstVerse: VerseId,
    val stops: List<PlaceSummary>,
    val path: List<RoutePoint> = emptyList(),
)

/** How many times a book mentions someone. */
data class BookMentions(val book: Int, val count: Int, val firstVerse: VerseId)

/** The chapter a verse id in event_verses belongs to. */
fun chapterOf(verse: Int): ChapterId = VerseId(verse).chapterId

/** "Ab" -> "Ab%", with LIKE wildcards in the text escaped (ESCAPE '\'). */
fun likePrefix(text: String): String =
    text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
