package com.genesis.core.cloud.community

import com.genesis.core.cloud.SupabaseClient
import com.genesis.core.cloud.Timestamps
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import java.text.Normalizer
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

// Church sermons (VRS-18), as Genesis/Core/ChurchSermons on iOS: a church's
// published outline, read only through the database functions of migration
// 20261120000000. Scripture text is never part of it: references carry
// verse ids in KJV numbering and, for a quotation from a free Bible, only
// that Bible's code, so the app shows the words from its own copy.

enum class ChurchSermonAudience(val raw: String) {
    /** Anyone with the link. */
    LINK("link"),
    /** Members of the church's group only. */
    MEMBERS("members");

    companion object {
        fun of(raw: String?): ChurchSermonAudience = entries.firstOrNull { it.raw == raw } ?: MEMBERS
    }
}

/** Whether readers have a handout's key: hidden until revealed, revealed, or never. */
enum class SermonAnswers(val raw: String) {
    HIDDEN("hidden"), REVEALED("revealed"), NEVER("never");

    companion object {
        fun of(raw: String?): SermonAnswers = entries.firstOrNull { it.raw == raw } ?: HIDDEN
    }
}

/** One blank in a published outline: "[[n]]" in the text; the answer only once revealed, never for an open blank. */
data class SermonBlank(val n: Int, val open: Boolean, val hint: String?, val answer: String?) {
    val isCheckable: Boolean get() = !open && answer != null
}

/** A Scripture reference in an outline, as the pastor wrote it. */
data class SermonReference(
    val raw: String,
    val start: Int?,
    val end: Int?,
    val status: String,
    /** The translation the pastor named ("NIV"). */
    val label: String?,
    /** A quotation readers show from their own copy (KJV, WEB, ASV, RV1909, BLIVRE). */
    val translation: String?,
    val quoteWithheld: Boolean = false,
) {
    /** Only a verified reference links: its first and last verse ids (KJV numbering). */
    val range: Pair<Int, Int>? get() = if (status == "verified" && start != null) start to (end ?: start) else null
}

sealed interface SermonBlock {
    val id: String

    data class Heading(override val id: String, val text: String, val level: Int) : SermonBlock
    data class Paragraph(override val id: String, val text: String) : SermonBlock
    data class Quote(override val id: String, val text: String) : SermonBlock
    data class ListBlock(override val id: String, val items: List<String>, val ordered: Boolean) : SermonBlock
    data class Scripture(override val id: String, val reference: SermonReference) : SermonBlock
}

/** A sermon in a list: the archive, a series' previous and next, search. */
data class ChurchSermonSummary(
    val slug: String,
    val title: String,
    val speaker: String,
    val series: String?,
    /** "yyyy-MM-dd". */
    val preachedOn: String?,
    val audience: ChurchSermonAudience,
) {
    val preachedDate: LocalDate? get() = preachedOn?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
}

/** One gathering: weekly on a day or once on a date, at "HH:MM" on the church's clock, with a note. */
data class ChurchGathering(val weekday: Weekday? = null, val date: String? = null, val time: String, val note: String = "") {
    enum class Weekday(val raw: String) { SUN("sun"), MON("mon"), TUE("tue"), WED("wed"), THU("thu"), FRI("fri"), SAT("sat") }

    companion object {
        fun isTime(s: String): Boolean {
            val parts = s.split(":")
            if (parts.size != 2 || parts.any { it.length != 2 || !it.all(Char::isDigit) }) return false
            return parts[0].toInt() in 0..23 && parts[1].toInt() in 0..59
        }

        fun isDate(s: String): Boolean {
            val parts = s.split("-")
            return parts.map { it.length } == listOf(4, 2, 2) && parts.all { part -> part.all(Char::isDigit) }
        }

        /** "9:00 AM" / "09:00" in the reader's language. */
        fun formatTime(time: String, locale: Locale): String {
            if (!isTime(time)) return time
            val (hour, minute) = time.split(":").map(String::toInt)
            return DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).format(LocalTime.of(hour, minute))
        }

        /** "Thursday, November 26, 2026" in the reader's language. */
        fun formatDate(day: String, locale: Locale): String {
            val date = runCatching { LocalDate.parse(day) }.getOrNull() ?: return day
            return DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(locale).format(date)
        }
    }
}

/** One place on a church's Locations and Times, the same rules as the web's locations.ts. */
data class ChurchLocation(
    val name: String,
    val street: String = "",
    val city: String = "",
    val region: String = "",
    val postalCode: String = "",
    val country: String = "",
    val address: String = "",
    val times: String = "",
    val gatherings: List<ChurchGathering> = emptyList(),
) {
    val timeLines: List<String> get() = times.lines().map { it.trim() }.filter { it.isNotEmpty() }

    /** Street; "City, ST 75146"; country. Falls back to the one-line address. */
    val addressLines: List<String>
        get() {
            val regionLine = listOf(region.trim(), postalCode.trim()).filter { it.isNotEmpty() }.joinToString(" ")
            val cityLine = listOf(city.trim(), regionLine).filter { it.isNotEmpty() }.joinToString(", ")
            val lines = listOf(street.trim(), cityLine, country.trim()).filter { it.isNotEmpty() }
            if (lines.isNotEmpty()) return lines
            return if (address.isBlank()) emptyList() else listOf(address.trim())
        }

    val oneLineAddress: String get() = addressLines.joinToString(", ")

    /** Directions in Google Maps, searched by the address (as the web page). */
    val mapsUrl: String?
        get() = oneLineAddress.takeIf { it.isNotEmpty() }?.let {
            "https://www.google.com/maps/search/?api=1&query=" + java.net.URLEncoder.encode(it, Charsets.UTF_8)
        }

    /**
     * The schedule as lines: each weekday once with its times ("Sundays ·
     * 9:00 AM, 11:00 AM (Spanish)"), then dates from `today` on, then any
     * times typed as text. `dayName` gives "Sundays" in the app's language.
     */
    fun scheduleLines(today: String, locale: Locale, dayName: (ChurchGathering.Weekday) -> String): List<String> {
        val valid = gatherings.filter { ChurchGathering.isTime(it.time) }
        fun at(g: ChurchGathering): String {
            val time = ChurchGathering.formatTime(g.time, locale)
            val note = g.note.trim()
            return if (note.isEmpty()) time else "$time ($note)"
        }
        val lines = mutableListOf<String>()
        for (day in ChurchGathering.Weekday.entries) {
            val on = valid.filter { it.weekday == day }.sortedBy { it.time }
            if (on.isNotEmpty()) lines += "${dayName(day)} · ${on.joinToString(", ", transform = ::at)}"
        }
        for (date in valid.mapNotNull { it.date }.filter { it >= today }.toSortedSet()) {
            val on = valid.filter { it.date == date }.sortedBy { it.time }
            lines += "${ChurchGathering.formatDate(date, locale)} · ${on.joinToString(", ", transform = ::at)}"
        }
        return lines + timeLines
    }
}

data class PublishedSermon(
    val id: String,
    val slug: String,
    val groupId: String,
    val church: String,
    val title: String,
    val speaker: String,
    val series: String?,
    val preachedOn: String?,
    val location: String,
    val language: String,
    val coverPath: String?,
    val coverAlt: String,
    val coverDecorative: Boolean,
    val audience: ChurchSermonAudience,
    val blocks: List<SermonBlock>,
    val previous: ChurchSermonSummary?,
    val next: ChurchSermonSummary?,
    val isMember: Boolean,
    val locations: List<ChurchLocation> = emptyList(),
    val revision: Int = 0,
    val answers: SermonAnswers = SermonAnswers.HIDDEN,
    val blanks: List<SermonBlank> = emptyList(),
) {
    val hasBlanks: Boolean get() = blanks.isNotEmpty()
    val preachedDate: LocalDate? get() = preachedOn?.let { runCatching { LocalDate.parse(it) }.getOrNull() }

    /** The verified passages, in order, each once (first and last verse ids). */
    val passages: List<Pair<Int, Int>>
        get() = blocks.mapNotNull { (it as? SermonBlock.Scripture)?.reference?.range }.distinct()
}

/** What a link opens. */
sealed interface ChurchSermonLookup {
    data class Found(val sermon: PublishedSermon) : ChurchSermonLookup
    /** For the church's members only, and the person isn't one. */
    data object MembersOnly : ChurchSermonLookup
    /** Never published, unpublished, hidden, deleted, or switched off. */
    data object NotFound : ChurchSermonLookup
}

/** A church found by name (only churches that chose to be listed) with its link sermons. */
data class SermonChurch(val id: String, val name: String, val sermons: List<ChurchSermonSummary>)

/** A heading and what follows it, for Copy and Jump to Section. */
data class SermonOutlineSection(val id: String, val title: String?, val blocks: List<SermonBlock>)

/** The outline's helpers, the same as the guest page's (web/src/lib/outline.ts). */
object SermonOutline {
    fun sections(blocks: List<SermonBlock>): List<SermonOutlineSection> {
        val out = mutableListOf<Triple<String, String?, MutableList<SermonBlock>>>()
        for (block in blocks) {
            if (block is SermonBlock.Heading) out += Triple(block.id, block.text, mutableListOf(block))
            else if (out.isEmpty()) out += Triple("start", null, mutableListOf(block))
            else out.last().third += block
        }
        return out.map { SermonOutlineSection(it.first, it.second, it.third) }
    }

    /** What Copy puts on the clipboard: the church's words as published; a reference as typed, never verse text. */
    fun copyText(blocks: List<SermonBlock>, blanks: List<SermonBlank> = emptyList()): String {
        val known = blanks.map { it.n }.toSet()
        fun words(text: String) = SermonBlanks.filled(text, known::contains)
        return blocks.map { block ->
            when (block) {
                is SermonBlock.Heading -> words(block.text)
                is SermonBlock.Paragraph -> words(block.text)
                is SermonBlock.Quote -> "“${block.text}”"
                is SermonBlock.ListBlock -> block.items.mapIndexed { i, item -> if (block.ordered) "${i + 1}. ${words(item)}" else "• ${words(item)}" }.joinToString("\n")
                is SermonBlock.Scripture -> block.reference.label?.let { "${block.reference.raw} ($it)" } ?: block.reference.raw
            }
        }.filter { it.isNotBlank() }.joinToString("\n\n")
    }
}

/** The rules for blanks, the same as web/src/lib/blanks.ts and SermonBlanks on iOS. */
object SermonBlanks {
    sealed interface Piece {
        data class Text(val words: String) : Piece
        data class Blank(val n: Int) : Piece
    }

    /** Splits text at its "[[n]]" markers; a marker with no blank of that number stays as words. */
    fun pieces(text: String, known: (Int) -> Boolean): List<Piece> {
        val out = mutableListOf<Piece>()
        val words = StringBuilder()
        var i = 0
        while (true) {
            val open = text.indexOf("[[", i)
            if (open < 0) break
            var j = open + 2
            while (j < text.length && text[j].isDigit() && text[j].code < 128) j++
            val digits = j - (open + 2)
            val n = if (digits in 1..3) text.substring(open + 2, j).toIntOrNull() else null
            if (n != null && text.startsWith("]]", j) && known(n)) {
                words.append(text, i, open)
                if (words.isNotEmpty()) out += Piece.Text(words.toString())
                words.clear()
                out += Piece.Blank(n)
                i = j + 2
            } else {
                words.append(text, i, open + 2)
                i = open + 2
            }
        }
        words.append(text, i, text.length)
        if (words.isNotEmpty()) out += Piece.Text(words.toString())
        return out
    }

    fun numbers(text: String, known: (Int) -> Boolean): List<Int> = pieces(text, known).mapNotNull { (it as? Piece.Blank)?.n }

    /** Text with each blank as a line (for Copy), or as the given words. */
    fun filled(text: String, known: (Int) -> Boolean, fill: (Int) -> String = { "_____" }): String =
        pieces(text, known).joinToString("") { piece ->
            when (piece) {
                is Piece.Text -> piece.words
                is Piece.Blank -> fill(piece.n)
            }
        }

    /** As compared: case, accents, spacing and outer punctuation don't count. */
    fun normalized(s: String): String {
        val folded = Normalizer.normalize(s.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")
            .replace('’', '\'').replace('‘', '\'')
        val trimmed = folded.trim { it.isWhitespace() || isPunctuation(it) }
        return trimmed.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
    }

    private fun isPunctuation(c: Char): Boolean = when (Character.getType(c)) {
        Character.CONNECTOR_PUNCTUATION.toInt(), Character.DASH_PUNCTUATION.toInt(), Character.START_PUNCTUATION.toInt(),
        Character.END_PUNCTUATION.toInt(), Character.INITIAL_QUOTE_PUNCTUATION.toInt(), Character.FINAL_QUOTE_PUNCTUATION.toInt(),
        Character.OTHER_PUNCTUATION.toInt() -> true
        else -> false
    }

    fun isCorrect(response: String, answer: String): Boolean {
        val r = normalized(response)
        return r.isNotEmpty() && r == normalized(answer)
    }
}

/** A sermon's one link: https://versely.7twenty8studio.com/s/<slug>, or versely://sermon/<slug>. */
object ChurchSermonLink {
    const val HOST = "versely.7twenty8studio.com"

    /** Ten lowercase letters and digits (`genesis_new_sermon_slug`). */
    fun isSlug(text: String): Boolean = text.length == 10 && text.all { it in 'a'..'z' || it in '0'..'9' }

    fun url(slug: String): String = "https://$HOST/s/$slug"

    /** Church Studio on the web, opened on this church. */
    fun studio(church: String): String = "https://$HOST/studio?church=${church.lowercase()}"

    /** The slug a link opens, or null for any other address. */
    fun slug(link: String): String? {
        val trimmed = link.trim()
        val scheme = trimmed.substringBefore("://", "").lowercase()
        val rest = trimmed.substringAfter("://", "").substringBefore('?').substringBefore('#')
        val host = rest.substringBefore('/').lowercase()
        val parts = rest.substringAfter('/', "").split('/').filter { it.isNotEmpty() }
        val slug = when (scheme) {
            "https" -> if (host == HOST && parts.size == 2 && parts[0] == "s") parts[1] else null
            "versely" -> if (host == "sermon" && parts.size == 1) parts[0] else null
            else -> null
        }
        return slug?.takeIf(::isSlug)
    }
}

/** Which Bible a church sermon's passages open in: one choice for the whole sermon. */
object ChurchPassageBible {
    fun options(current: String, chosen: String?, quoted: String?, isAvailable: (String) -> Boolean): List<String> {
        val list = mutableListOf(current)
        for (id in listOfNotNull(chosen, quoted)) if (id !in list && isAvailable(id)) list += id
        return list
    }

    fun shown(options: List<String>, chosen: String?): String? = if (chosen != null && chosen in options) chosen else options.firstOrNull()

    /** True when the pastor's label names the Bible shown, so it isn't named twice. */
    fun labelNames(label: String?, id: String): Boolean {
        val trimmed = label?.trim().orEmpty()
        return trimmed.isNotEmpty() && trimmed.equals(id, ignoreCase = true)
    }
}

/** The Bibles whose quotations a church may publish (as a code, never the words). */
object ChurchSermonQuote {
    val codes = setOf("KJV", "WEB", "ASV", "RV1909", "BLIVRE")
}

// MARK: Reading the functions' JSON, leniently (a block or field from a later version is skipped).

object ChurchSermonWire {
    private val json = Json { ignoreUnknownKeys = true }

    private fun JsonElement?.obj(): JsonObject? = this as? JsonObject
    private fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
    private fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.intOrNull
    private fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.booleanOrNull
    private fun JsonObject.array(key: String): List<JsonElement> = (this[key] as? JsonArray).orEmpty()
    private fun nonEmpty(text: String?): String? = text?.takeIf { it.isNotBlank() }

    fun lookup(body: String): ChurchSermonLookup {
        val root = runCatching { json.parseToJsonElement(body) }.getOrNull().obj() ?: return ChurchSermonLookup.NotFound
        return when (root.str("status")) {
            "ok" -> root["sermon"].obj()?.let(::sermon)?.let(ChurchSermonLookup::Found) ?: ChurchSermonLookup.NotFound
            "members_only" -> ChurchSermonLookup.MembersOnly
            else -> ChurchSermonLookup.NotFound
        }
    }

    /** group_sermons: published summaries; leaders' drafts and hidden rows are left out. */
    fun archive(body: String): List<ChurchSermonSummary> =
        (runCatching { json.parseToJsonElement(body) }.getOrNull() as? JsonArray).orEmpty().mapNotNull { element ->
            val row = element.obj() ?: return@mapNotNull null
            if (row.containsKey("status") && row["status"] !is JsonNull) {
                if (row.str("status") != "published" || row.str("live_audience") == null || row.bool("hidden") == true) return@mapNotNull null
            }
            summary(row)
        }

    fun churches(body: String): List<SermonChurch> =
        (runCatching { json.parseToJsonElement(body) }.getOrNull() as? JsonArray).orEmpty().mapNotNull { element ->
            val row = element.obj() ?: return@mapNotNull null
            val id = row.str("group_id") ?: return@mapNotNull null
            val name = row.str("name") ?: return@mapNotNull null
            SermonChurch(id.lowercase(), name, row.array("sermons").mapNotNull { it.obj()?.let(::summary) })
        }

    fun summary(row: JsonObject): ChurchSermonSummary? {
        val slug = row.str("slug")?.takeIf(ChurchSermonLink::isSlug) ?: return null
        return ChurchSermonSummary(
            slug = slug,
            title = row.str("title").orEmpty(),
            speaker = row.str("speaker").orEmpty(),
            series = nonEmpty(row.str("series")),
            preachedOn = row.str("preached_on")?.take(10),
            audience = ChurchSermonAudience.of(row.str("live_audience") ?: row.str("audience")),
        )
    }

    private fun verse(raw: Int?): Int? {
        raw ?: return null
        val book = raw / 1_000_000
        val chapter = (raw / 1_000) % 1_000
        val verse = raw % 1_000
        return raw.takeIf { book in 1..66 && chapter > 0 && verse > 0 }
    }

    fun reference(row: JsonObject): SermonReference? {
        val raw = row.str("raw") ?: return null
        val start = verse(row.int("start"))
        val status = row.str("status")?.takeIf { it in setOf("verified", "ambiguous", "unlinked") } ?: "unlinked"
        return SermonReference(
            raw = raw,
            start = start,
            end = verse(row.int("end")),
            // A reference the app can't read doesn't link.
            status = if (status == "verified" && start == null) "unlinked" else status,
            label = nonEmpty(row.str("label")),
            translation = row.str("translation")?.takeIf { it in ChurchSermonQuote.codes },
            quoteWithheld = row.bool("quote_withheld") ?: false,
        )
    }

    fun block(row: JsonObject): SermonBlock? {
        val id = row.str("id") ?: return null
        val text = row.str("text")
        return when (row.str("kind")) {
            "heading" -> text?.let { SermonBlock.Heading(id, it, (row.int("level") ?: 2).coerceIn(1, 3)) }
            "paragraph" -> text?.let { SermonBlock.Paragraph(id, it) }
            "quote" -> text?.let { SermonBlock.Quote(id, it) }
            "list" -> (row["items"] as? JsonArray)?.let { items ->
                SermonBlock.ListBlock(id, items.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }, row.bool("ordered") ?: false)
            }
            "scripture" -> row["ref"].obj()?.let(::reference)?.let { SermonBlock.Scripture(id, it) }
            else -> null
        }
    }

    private fun location(row: JsonObject): ChurchLocation? {
        val name = row.str("name")?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return ChurchLocation(
            name = name, street = row.str("street").orEmpty(), city = row.str("city").orEmpty(), region = row.str("region").orEmpty(),
            postalCode = row.str("postal_code").orEmpty(), country = row.str("country").orEmpty(), address = row.str("address").orEmpty(),
            times = row.str("times").orEmpty(),
            gatherings = row.array("gatherings").mapNotNull { element ->
                val g = element.obj() ?: return@mapNotNull null
                val time = g.str("time")?.takeIf(ChurchGathering::isTime) ?: return@mapNotNull null
                val day = ChurchGathering.Weekday.entries.firstOrNull { it.raw == g.str("day") }
                val date = g.str("date")?.takeIf(ChurchGathering::isDate)
                when {
                    day != null -> ChurchGathering(weekday = day, time = time, note = g.str("note").orEmpty())
                    date != null -> ChurchGathering(date = date, time = time, note = g.str("note").orEmpty())
                    else -> null
                }
            },
        )
    }

    fun blank(row: JsonObject): SermonBlank? {
        val n = row.int("n")?.takeIf { it in 1..999 } ?: return null
        val open = row.bool("open") ?: false
        return SermonBlank(n, open, nonEmpty(row.str("hint")), if (open) null else row.str("answer"))
    }

    fun sermon(row: JsonObject): PublishedSermon? {
        val slug = row.str("slug")?.takeIf(ChurchSermonLink::isSlug) ?: return null
        val id = row.str("id") ?: return null
        val groupId = row.str("group_id") ?: return null
        val cover = row["cover"].obj()
        return PublishedSermon(
            id = id.lowercase(), slug = slug, groupId = groupId.lowercase(), church = row.str("church").orEmpty(),
            title = row.str("title").orEmpty(), speaker = row.str("speaker").orEmpty(), series = nonEmpty(row.str("series")),
            preachedOn = row.str("preached_on")?.take(10), location = row.str("location").orEmpty(), language = row.str("language") ?: "en",
            coverPath = cover?.str("path")?.takeIf { it.isNotEmpty() }, coverAlt = cover?.str("alt").orEmpty(), coverDecorative = cover?.bool("decorative") ?: false,
            audience = ChurchSermonAudience.of(row.str("audience")),
            blocks = row.array("blocks").mapNotNull { it.obj()?.let(::block) },
            previous = row["previous"].obj()?.let(::summary), next = row["next"].obj()?.let(::summary),
            isMember = row.bool("is_member") ?: false,
            locations = row.array("locations").mapNotNull { it.obj()?.let(::location) },
            revision = row.int("revision") ?: 0,
            answers = SermonAnswers.of(row.str("answers")),
            blanks = row.array("blanks").mapNotNull { it.obj()?.let(::blank) },
        )
    }
}

// MARK: Saved handouts (sermons.handouts), as SermonHandout on iOS

/**
 * A member's own saved work on a church's handout: the revision, its
 * outline, their answers and the key only once it was revealed. Kept with
 * their sermon notes and never sent to the church. Stored as the iPhone
 * stores it (snake_case keys), so both phones read each other's work.
 */
data class SavedHandout(
    val sermonId: String,
    val slug: String,
    val revision: Int,
    val title: String,
    val church: String,
    val savedAt: Long,
    val blocks: List<SermonBlock>,
    val blanks: List<SermonBlank>,
    val responses: Map<Int, String>,
) {
    val id: String get() = "$sermonId-$revision"
    val hasKey: Boolean get() = blanks.any { it.isCheckable }

    companion object {
        const val MAXIMUM_KEPT = 10
        const val MAXIMUM_BYTES = 900_000

        fun of(sermon: PublishedSermon, responses: Map<Int, String>, keepKey: Boolean, savedAt: Long): SavedHandout = SavedHandout(
            sermonId = sermon.id, slug = sermon.slug, revision = sermon.revision, title = sermon.title, church = sermon.church,
            savedAt = savedAt, blocks = sermon.blocks,
            blanks = sermon.blanks.map { it.copy(answer = if (keepKey) it.answer else null) },
            responses = responses,
        )
    }
}

object SavedHandouts {
    private val json = Json { ignoreUnknownKeys = true }

    fun decode(raw: String?): List<SavedHandout> {
        if (raw.isNullOrBlank()) return emptyList()
        val array = runCatching { json.parseToJsonElement(raw) }.getOrNull() as? JsonArray ?: return emptyList()
        return array.mapNotNull { element ->
            val row = element as? JsonObject ?: return@mapNotNull null
            fun s(key: String) = (row[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
            val sermonId = (s("sermon_id") ?: s("sermonId"))?.lowercase() ?: return@mapNotNull null
            val revision = (row["revision"] as? JsonPrimitive)?.intOrNull ?: return@mapNotNull null
            SavedHandout(
                sermonId = sermonId,
                slug = s("slug").orEmpty(),
                revision = revision,
                title = s("title").orEmpty(),
                church = s("church").orEmpty(),
                savedAt = (s("saved_at") ?: s("savedAt"))?.let(Timestamps::millis) ?: 0L,
                blocks = (row["blocks"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(::savedBlock) },
                blanks = (row["blanks"] as? JsonArray).orEmpty().mapNotNull { blank ->
                    val b = blank as? JsonObject ?: return@mapNotNull null
                    val n = (b["n"] as? JsonPrimitive)?.intOrNull ?: return@mapNotNull null
                    val open = (b["open"] as? JsonPrimitive)?.booleanOrNull ?: false
                    SermonBlank(n, open, (b["hint"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }, (b["answer"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull)
                },
                responses = (row["responses"] as? JsonObject).orEmpty().mapNotNull { (key, value) ->
                    val n = key.toIntOrNull() ?: return@mapNotNull null
                    val text = (value as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
                    n to text
                }.toMap(),
            )
        }
    }

    /** A saved block: a reference's fields sit on the block itself (HandoutBlock). */
    private fun savedBlock(row: JsonObject): SermonBlock? {
        if ((row["kind"] as? JsonPrimitive)?.contentOrNull != "scripture") return ChurchSermonWire.block(row)
        val id = (row["id"] as? JsonPrimitive)?.contentOrNull ?: return null
        val reference = ChurchSermonWire.reference(row) ?: return null
        return SermonBlock.Scripture(id, reference.copy(quoteWithheld = false))
    }

    fun encode(handouts: List<SavedHandout>): String? {
        if (handouts.isEmpty()) return null
        var kept = handouts.takeLast(SavedHandout.MAXIMUM_KEPT)
        var raw = array(kept).toString()
        while (raw.toByteArray().size > SavedHandout.MAXIMUM_BYTES && kept.isNotEmpty()) {
            kept = kept.drop(1)
            raw = array(kept).toString()
        }
        return raw.takeIf { kept.isNotEmpty() }
    }

    private fun array(handouts: List<SavedHandout>): JsonArray = buildJsonArray {
        handouts.forEach { h ->
            add(buildJsonObject {
                put("sermon_id", h.sermonId)
                put("slug", h.slug)
                put("revision", h.revision)
                put("title", h.title)
                put("church", h.church)
                put("saved_at", Timestamps.string(h.savedAt))
                put("blocks", buildJsonArray { h.blocks.forEach { add(blockJson(it)) } })
                put("blanks", buildJsonArray {
                    h.blanks.forEach { b ->
                        add(buildJsonObject {
                            put("n", b.n)
                            put("open", b.open)
                            b.hint?.let { put("hint", it) }
                            b.answer?.let { put("answer", it) }
                        })
                    }
                })
                put("responses", buildJsonObject { h.responses.filterValues { it.isNotEmpty() }.forEach { (n, text) -> put(n.toString(), text) } })
            })
        }
    }

    private fun blockJson(block: SermonBlock): JsonObject = buildJsonObject {
        put("id", block.id)
        when (block) {
            is SermonBlock.Heading -> { put("kind", "heading"); put("text", block.text); put("level", block.level) }
            is SermonBlock.Paragraph -> { put("kind", "paragraph"); put("text", block.text) }
            is SermonBlock.Quote -> { put("kind", "quote"); put("text", block.text) }
            is SermonBlock.ListBlock -> {
                put("kind", "list")
                put("items", buildJsonArray { block.items.forEach { add(JsonPrimitive(it)) } })
                put("ordered", block.ordered)
            }
            is SermonBlock.Scripture -> {
                val r = block.reference
                put("kind", "scripture")
                put("raw", r.raw)
                r.start?.let { put("start", it) }
                r.end?.let { put("end", it) }
                put("status", r.status)
                r.label?.let { put("label", it) }
                r.translation?.let { put("translation", it) }
            }
        }
    }

    /**
     * Saves the member's answers on this revision, keeping other revisions'
     * work. The key goes with them only once revealed; a key saved earlier stays.
     */
    fun saving(existing: List<SavedHandout>, sermon: PublishedSermon, responses: Map<Int, String>, now: Long): List<SavedHandout> {
        var copy = SavedHandout.of(sermon, responses, keepKey = sermon.answers == SermonAnswers.REVEALED, savedAt = now)
        val index = existing.indexOfLast { it.sermonId == sermon.id && it.revision == sermon.revision }
        if (index < 0) return existing + copy
        if (!copy.hasKey) copy = copy.copy(blanks = existing[index].blanks)
        return existing.toMutableList().also { it[index] = copy }
    }
}

// MARK: The server

enum class ChurchSermonEvent(val raw: String) { OPEN("open"), PASSAGE("passage"), SAVE("save") }

/**
 * Church sermons on the server (SupabaseChurchSermonBackend on iOS):
 * published_sermon, group_sermons, search_sermon_churches and
 * report_church_sermon; covers through sermon-cover and counts through
 * sermon-events. Signed out, the anon key reads what anyone with the link may.
 */
class ChurchSermonApi(private val client: SupabaseClient, private val token: () -> String?) {
    private fun rpc(name: String, signedIn: Boolean = false, vararg params: Pair<String, JsonElement>): String {
        val access = token()
        if (signedIn && access == null) throw CommunityError.SignInRequired()
        return try {
            client.rpc(name, buildJsonObject { params.forEach { (key, value) -> put(key, value) } }.toString(), access)
        } catch (error: Throwable) {
            throw CommunityError.from(error)
        }
    }

    fun sermon(slug: String): ChurchSermonLookup {
        if (!ChurchSermonLink.isSlug(slug)) return ChurchSermonLookup.NotFound
        return ChurchSermonWire.lookup(rpc("published_sermon", false, "p_slug" to JsonPrimitive(slug)))
    }

    /** A church's published sermons, newest first, for its members; throws when sermons are off. */
    fun archive(group: String): List<ChurchSermonSummary> =
        ChurchSermonWire.archive(rpc("group_sermons", true, "p_group" to JsonPrimitive(group.lowercase())))

    fun searchChurches(query: String): List<SermonChurch> {
        val trimmed = query.trim()
        if (trimmed.length < 2) return emptyList()
        return ChurchSermonWire.churches(rpc("search_sermon_churches", false, "p_query" to JsonPrimitive(trimmed.take(60))))
    }

    fun report(slug: String, reason: String) {
        rpc("report_church_sermon", true, "p_slug" to JsonPrimitive(slug), "p_reason" to JsonPrimitive(reason.take(500)))
    }

    /** The cover, checked against the reader's access on every request; never saved. */
    fun cover(path: String): ByteArray? = runCatching { client.getBytes("functions/v1/sermon-cover", "name=" + java.net.URLEncoder.encode(path, Charsets.UTF_8), token()) }.getOrNull()

    /** Counts an open, a passage or notes saved (no account, address or text kept). Never throws. */
    fun count(event: ChurchSermonEvent, slug: String) {
        runCatching {
            client.callFunctionAnonymously("sermon-events", buildJsonObject { put("slug", slug); put("kind", event.raw) }.toString())
        }
    }
}
