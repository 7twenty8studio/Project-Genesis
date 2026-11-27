package com.genesis.core.bible

import android.content.Context
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.SQLiteStatement
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READONLY
import androidx.sqlite.execSQL
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.study.BookMentions
import com.genesis.core.domain.study.Era
import com.genesis.core.domain.study.Family
import com.genesis.core.domain.study.OtherNames
import com.genesis.core.domain.study.Person
import com.genesis.core.domain.study.PersonSummary
import com.genesis.core.domain.study.Place
import com.genesis.core.domain.study.PlaceSummary
import com.genesis.core.domain.study.Route
import com.genesis.core.domain.study.RoutePoint
import com.genesis.core.domain.study.TimelineEvent
import com.genesis.core.domain.study.likePrefix

/**
 * People, places, events and routes for Explore, read from the bundled
 * Study.sqlite: the same queries as StudyRepository.swift.
 *
 * Data: Theographic Bible Metadata (CC BY-SA 4.0), coordinates from
 * OpenBible.info (CC BY 4.0), descriptions from Easton's Bible Dictionary
 * (public domain). Verse ids only, never Scripture text.
 *
 * In Spanish and Portuguese, names, titles and summaries come from the
 * `translations` table, each falling back to the English; search finds both.
 */
class StudyRepository private constructor(private val connection: SQLiteConnection, language: String?) : AutoCloseable {
    private val lock = Any()

    /** "es" or "pt" when the database has names in that language; null for English. */
    val language: String? = language?.takeIf { it in TRANSLATED && hasTable("translations") }

    // Timeline

    fun eras(): List<Era> = query(
        "SELECT e.id, ${pick("t", "name", "e.title")}, ${pick("t", "other", "e.summary")}, e.dated, e.first_verse FROM eras e${join("era", "t", "e.id")} ORDER BY e.sort",
    ) { Era(it.getText(0), it.getText(1), it.getText(2), it.getLong(3) != 0L, VerseId(it.getLong(4).toInt())) }

    fun eventsInEra(inEra: String): List<TimelineEvent> = query("$eventColumns WHERE ev.era = ? ORDER BY ev.sort_key, ev.id", inEra, map = ::event)

    fun event(id: Int): TimelineEvent? = query("$eventColumns WHERE ev.id = ?", id, map = ::event).firstOrNull()

    /** Chapters the event is told in, in canonical order. */
    fun chapters(forEvent: Int): List<ChapterId> =
        query("SELECT DISTINCT verse / 1000 FROM event_verses WHERE event_id = ? ORDER BY 1", forEvent) {
            val chapter = it.getLong(0).toInt()
            ChapterId(chapter / 1000, chapter % 1000)
        }

    fun peopleInEvent(inEvent: Int): List<PersonSummary> =
        query("$personColumns JOIN event_people e ON e.person_id = p.id WHERE e.event_id = ? ORDER BY p.verse_count DESC", inEvent, map = ::personSummary)

    fun placesInEvent(inEvent: Int): List<PlaceSummary> =
        query("$placeColumns JOIN event_places e ON e.place_id = p.id WHERE e.event_id = ? ORDER BY p.verse_count DESC", inEvent) { placeSummary(it) }

    fun eventsForPerson(forPerson: Int): List<TimelineEvent> =
        query("$eventColumns JOIN event_people e ON e.event_id = ev.id WHERE e.person_id = ? ORDER BY ev.sort_key", forPerson, map = ::event)

    fun eventsAtPlace(atPlace: Int): List<TimelineEvent> =
        query("$eventColumns JOIN event_places e ON e.event_id = ev.id WHERE e.place_id = ? ORDER BY ev.sort_key", atPlace, map = ::event)

    // People

    /** People whose name (or other name) starts with the text; the best known first. */
    fun searchPeople(text: String, limit: Int = 50): List<PersonSummary> {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return notablePeople(limit)
        val pattern = likePrefix(trimmed)
        return query(
            "$personColumns WHERE p.name LIKE ? ESCAPE '\\' OR p.also_called LIKE ? ESCAPE '\\' OR p.also_called LIKE ? ESCAPE '\\'${translatedMatch("tp")} ORDER BY p.verse_count DESC LIMIT ?",
            *(listOf<Any>(pattern, pattern, "%, $pattern") + translatedArgument(trimmed) + limit).toTypedArray(),
            map = ::personSummary,
        )
    }

    /** The most-mentioned people, for the opening list. */
    fun notablePeople(limit: Int = 50): List<PersonSummary> = query("$personColumns ORDER BY p.verse_count DESC LIMIT ?", limit, map = ::personSummary)

    fun person(id: Int): Person? = query(
        "SELECT p.id, ${pick("tp", "name", "p.name")}, ${pick("tp", "other", "p.also_called")}, p.verse_count, p.gender, ${pick("tp", "detail", "p.bio")}, p.birth_year, p.death_year, p.tribe, p.first_verse, ${translated("tp")} FROM people p${join("person", "tp", "p.id")} WHERE p.id = ?",
        id,
    ) {
        Person(
            summary = personSummary(it),
            gender = it.getText(4),
            biography = it.getText(5),
            birthYear = it.optionalInt(6),
            deathYear = it.optionalInt(7),
            group = it.getText(8),
            firstVerse = it.optionalInt(9)?.let(::VerseId),
            biographyIsTranslated = it.getLong(10) != 0L,
        )
    }.firstOrNull()

    fun family(ofPerson: Int): Family = Family.of(
        query(
            "SELECT r.kind, p.id, ${pick("tp", "name", "p.name")}, ${pick("tp", "other", "p.also_called")}, p.verse_count FROM relations r JOIN people p ON p.id = r.other_id${join("person", "tp", "p.id")} WHERE r.person_id = ? ORDER BY p.verse_count DESC",
            ofPerson,
        ) { it.getText(0) to PersonSummary.of(it.getLong(1).toInt(), it.getText(2), it.getText(3), it.getLong(4).toInt()) },
    )

    /** Books that mention the person, in canonical order. */
    fun books(forPerson: Int): List<BookMentions> =
        query("SELECT verse / 1000000, COUNT(*), MIN(verse) FROM person_verses WHERE person_id = ? GROUP BY 1 ORDER BY 1", forPerson) {
            BookMentions(it.getLong(0).toInt(), it.getLong(1).toInt(), VerseId(it.getLong(2).toInt()))
        }

    fun versesForPerson(forPerson: Int, limit: Int = 200): List<VerseId> =
        query("SELECT verse FROM person_verses WHERE person_id = ? ORDER BY verse LIMIT ?", forPerson, limit) { VerseId(it.getLong(0).toInt()) }

    /** Mapped places where the person's events happen. */
    fun placesForPerson(forPerson: Int, limit: Int = 30): List<PlaceSummary> = query(
        "$placeColumns WHERE p.latitude IS NOT NULL AND p.id IN (SELECT ep.place_id FROM event_places ep JOIN event_people e ON e.event_id = ep.event_id WHERE e.person_id = ?) ORDER BY p.verse_count DESC LIMIT ?",
        forPerson, limit,
    ) { placeSummary(it) }

    // Places

    fun place(id: Int): Place? = query(
        "SELECT p.id, ${pick("tq", "name", "p.name")}, p.kind, p.latitude, p.longitude, p.verse_count, ${pick("tq", "other", "p.aliases")}, ${pick("tq", "detail", "p.bio")}, p.precise, p.first_verse, p.confidence, ${translated("tq")} FROM places p${join("place", "tq", "p.id")} WHERE p.id = ?",
        id,
    ) {
        Place(
            summary = placeSummary(it, confidenceColumn = 10),
            aliases = OtherNames.distinct(it.getText(6), it.getText(1)),
            description = it.getText(7),
            isPrecise = it.getLong(8) != 0L,
            firstVerse = it.optionalInt(9)?.let(::VerseId),
            descriptionIsTranslated = it.getLong(11) != 0L,
        )
    }.firstOrNull()

    fun mappedPlaces(minimumMentions: Int = 1, limit: Int = 2000): List<PlaceSummary> =
        query("$placeColumns WHERE p.latitude IS NOT NULL AND p.verse_count >= ? ORDER BY p.verse_count DESC LIMIT ?", minimumMentions, limit) { placeSummary(it) }

    fun versesForPlace(forPlace: Int, limit: Int = 200): List<VerseId> =
        query("SELECT verse FROM place_verses WHERE place_id = ? ORDER BY verse LIMIT ?", forPlace, limit) { VerseId(it.getLong(0).toInt()) }

    // Routes

    fun routes(): List<Route> {
        val hasPaths = hasTable("route_path")
        val headers = query("SELECT r.id, ${pick("t", "name", "r.title")}, ${pick("t", "other", "r.passage")}, r.first_verse FROM routes r${join("route", "t", "r.id")} ORDER BY r.sort") {
            listOf(it.getText(0), it.getText(1), it.getText(2), it.getLong(3).toInt())
        }
        return headers.map { (id, title, passage, first) ->
            id as String
            val stops = query(
                "SELECT p.id, ${pick("tq", "name", "p.name")}, p.kind, p.latitude, p.longitude, p.verse_count, p.confidence FROM route_stops s JOIN places p ON p.id = s.place_id${join("place", "tq", "p.id")} WHERE s.route_id = ? ORDER BY s.position",
                id,
            ) { placeSummary(it) }
            val path = if (hasPaths) query("SELECT latitude, longitude FROM route_path WHERE route_id = ? ORDER BY position", id) { RoutePoint(it.getDouble(0), it.getDouble(1)) } else emptyList()
            Route(id, title as String, passage as String, VerseId(first as Int), stops, path)
        }
    }

    override fun close() = synchronized(lock) { connection.close() }

    // Rows

    private val eventColumns get() = "SELECT ev.id, ${pick("te", "name", "ev.title")}, ev.era, ev.year, ev.first_verse, ev.last_verse FROM events ev${join("event", "te", "ev.id")}"
    private val personColumns get() = "SELECT p.id, ${pick("tp", "name", "p.name")}, ${pick("tp", "other", "p.also_called")}, p.verse_count FROM people p${join("person", "tp", "p.id")}"
    private val placeColumns get() = "SELECT p.id, ${pick("tq", "name", "p.name")}, p.kind, p.latitude, p.longitude, p.verse_count, p.confidence FROM places p${join("place", "tq", "p.id")}"

    /** " LEFT JOIN translations …" in Spanish or Portuguese, or "" in English. The language is one of [TRANSLATED], never free text. */
    private fun join(kind: String, alias: String, id: String): String =
        language?.let { " LEFT JOIN translations $alias ON $alias.lang = '$it' AND $alias.kind = '$kind' AND $alias.key = CAST($id AS TEXT)" } ?: ""

    private fun pick(alias: String, column: String, english: String): String =
        if (language == null) english else "COALESCE(NULLIF($alias.$column, ''), $english)"

    private fun translated(alias: String): String = if (language == null) "0" else "COALESCE($alias.detail, '') <> ''"

    /** Also matches the start of a translated name or other name, accents and case aside ("moi" finds Moisés). */
    private fun translatedMatch(alias: String): String = if (language == null) "" else " OR $alias.folded LIKE ? ESCAPE '\\'"

    private fun translatedArgument(text: String): List<Any> = if (language == null) emptyList() else listOf("%, " + likePrefix(OtherNames.fold(text)))

    private fun event(row: SQLiteStatement) = TimelineEvent(
        id = row.getLong(0).toInt(),
        title = row.getText(1),
        eraId = row.getText(2),
        year = row.optionalInt(3),
        firstVerse = row.optionalInt(4)?.let(::VerseId),
        lastVerse = row.optionalInt(5)?.let(::VerseId),
    )

    private fun personSummary(row: SQLiteStatement) = PersonSummary.of(row.getLong(0).toInt(), row.getText(1), row.getText(2), row.getLong(3).toInt())

    private fun placeSummary(row: SQLiteStatement, confidenceColumn: Int = 6) = PlaceSummary(
        id = row.getLong(0).toInt(),
        name = row.getText(1),
        kind = row.getText(2),
        latitude = if (row.isNull(3)) null else row.getDouble(3),
        longitude = if (row.isNull(4)) null else row.getDouble(4),
        verseCount = row.getLong(5).toInt(),
        confidence = row.optionalInt(confidenceColumn),
    )

    private fun SQLiteStatement.optionalInt(column: Int): Int? = if (isNull(column)) null else getLong(column).toInt()

    private fun hasTable(name: String): Boolean =
        query("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", name) { true }.isNotEmpty()

    private fun <T> query(sql: String, vararg arguments: Any, map: (SQLiteStatement) -> T): List<T> = synchronized(lock) {
        connection.prepare(sql).use { statement ->
            arguments.forEachIndexed { index, value ->
                when (value) {
                    is Int -> statement.bindLong(index + 1, value.toLong())
                    is Long -> statement.bindLong(index + 1, value)
                    else -> statement.bindText(index + 1, value.toString())
                }
            }
            buildList { while (statement.step()) add(map(statement)) }
        }
    }

    companion object {
        /** Languages Study.sqlite has names for. Only these reach the SQL. */
        val TRANSLATED = setOf("es", "pt")

        /** The bundled database in the app's language ("en", "es", "pt"). */
        fun open(context: Context, language: String?): StudyRepository {
            val connection = BundledSQLiteDriver().open(BundledFiles.file(context, "Study.sqlite").path, SQLITE_OPEN_READONLY)
            connection.execSQL("PRAGMA query_only = ON")
            return StudyRepository(connection, language)
        }
    }
}
