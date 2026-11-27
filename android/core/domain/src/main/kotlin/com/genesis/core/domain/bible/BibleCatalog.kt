package com.genesis.core.domain.bible

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * A Bible that can be put on the phone, as DownloadableTranslation on iOS:
 * a file from public.bible_translations, or a YouVersion Platform Bible
 * (public.youversion_bibles, `youVersionId` set), which has no file and is
 * built on the phone book by book.
 */
@Serializable
data class DownloadableBible(
    val id: String,
    val name: String,
    val year: String = "",
    val license: String = "",
    val summary: String = "",
    @SerialName("file_url") val fileUrl: String = "",
    @SerialName("file_bytes") val fileBytes: Long = 0,
    @SerialName("database_bytes") val databaseBytes: Long = 0,
    val sha256: String = "",
    val version: Int = 1,
    val language: String = "en",
    val approach: String? = null,
    @SerialName("reading_level") val readingLevel: String? = null,
    val rights: String? = null,
    val popularity: Int? = null,
    /** Only with Premium (a Bible whose licence Versely pays for). */
    val premium: Boolean = false,
    /** Set for a YouVersion Platform Bible: its id on the Platform. */
    @SerialName("yvp_id") val youVersionId: Int? = null,
    /** The publisher's website, linked from the notice under every chapter (https only). */
    @SerialName("publisher_url") val publisherUrl: String? = null,
) {
    val isYouVersion: Boolean get() = youVersionId != null

    /** A licensed file comes through the bible-file function; public-domain files straight from storage. */
    val isLicensedFile: Boolean get() = !isYouVersion && rights == "licensed"

    /** The base language ("pt" for "pt-PT"). */
    val baseLanguage: String get() = language.substringBefore('-').lowercase()
}

/** A Bible downloaded or built on this phone. */
@Serializable
data class InstalledBibleRecord(
    val bible: DownloadableBible,
    /** The file inside the phone's Bibles folder. */
    val fileName: String,
    /** When it was downloaded or built (ms since 1970). */
    val installedAt: Long = 0,
    /** For a YouVersion Bible, the build format (YouVersionBuild.FORMAT). */
    val format: Int? = null,
)

/**
 * The Bibles screen's rules, as ReadingLibrary on iOS: Bibles grouped by
 * language, the most read first; a language menu (each language with a
 * Bible, then All Languages) that opens on the current Bible's language.
 */
object ReadingLibrary {
    const val ALL_LANGUAGES = "all"

    /** A Bible in a list: on the phone or offered. */
    data class Entry(val id: String, val name: String, val language: String, val popularity: Int?, val sort: Int, val installed: Boolean)

    /** Every language with a Bible, the app's language first, then by name code. */
    fun languages(entries: List<Entry>, appLanguage: String): List<String> =
        entries.map { base(it.language) }.distinct().sortedWith(compareBy({ it != base(appLanguage) }, { it != "en" }, { it }))

    /** The language the screen opens on: the current Bible's, if any Bible has it. */
    fun defaultLanguage(currentBibleLanguage: String?, appLanguage: String, entries: List<Entry>): String {
        val known = languages(entries, appLanguage)
        return listOfNotNull(currentBibleLanguage?.let(::base), base(appLanguage)).firstOrNull { it in known } ?: known.firstOrNull() ?: ALL_LANGUAGES
    }

    /** The sections shown for a language choice: one per language, the most read first, then the catalog's order. */
    fun sections(entries: List<Entry>, language: String, appLanguage: String): List<Pair<String, List<Entry>>> {
        val languages = if (language == ALL_LANGUAGES) languages(entries, appLanguage) else listOf(language)
        return languages.mapNotNull { code ->
            val shown = entries.filter { base(it.language) == code }
                .sortedWith(compareBy({ it.popularity ?: Int.MAX_VALUE }, { it.sort }, { it.name }))
            if (shown.isEmpty()) null else code to shown
        }
    }

    /**
     * Installed Bibles for the reader's quick menu: grouped by language, the
     * current Bible's language first; nothing filtered out.
     */
    fun groups(entries: List<Entry>, currentLanguage: String): List<Pair<String, List<Entry>>> {
        val current = base(currentLanguage)
        return entries.filter { it.installed }.groupBy { base(it.language) }.toList()
            .sortedWith(compareBy({ it.first != current }, { it.first != "en" }, { it.first }))
            .map { (code, list) -> code to list.sortedWith(compareBy({ it.popularity ?: Int.MAX_VALUE }, { it.sort }, { it.name })) }
    }

    fun base(language: String): String = language.substringBefore('-').lowercase()
}
