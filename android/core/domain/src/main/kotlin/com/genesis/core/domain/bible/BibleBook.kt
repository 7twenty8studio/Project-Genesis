package com.genesis.core.domain.bible

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
enum class Testament {
    @SerialName("old") OLD,
    @SerialName("new") NEW,
}

/** A book's name, abbreviation and other accepted spellings in one language. */
@Serializable
data class LocalName(val name: String, val abbreviation: String, val aliases: List<String>)

/**
 * One of the 66 books of the Protestant canon. Book numbers (1–66) are the
 * stable key shared by every translation database.
 */
@Serializable
data class BibleBook(
    val id: Int,
    val osis: String,
    val en: LocalName,
    val es: LocalName,
    val pt: LocalName,
    val testament: Testament,
    val chapterCount: Int,
    /** Verses in each chapter, in the KJV's numbering. */
    val verses: List<Int>,
) {
    val englishName: String get() = en.name

    /** The book's name in a language ("en", "es" or "pt", with or without a region); English for others. */
    fun name(language: String): String = local(language).name

    fun abbreviation(language: String): String = local(language).abbreviation

    fun local(language: String): LocalName = when {
        language.startsWith("es") -> es
        language.startsWith("pt") -> pt
        else -> en
    }

    fun verseCount(chapter: Int): Int = verses.getOrElse(chapter - 1) { 0 }
}

/**
 * The 66 books, read from bibleBooks.json: the file the web's reference
 * parser reads, generated from BibleBook.swift and the KJV by
 * Tools/BibleData/export_reference_books.py, so the names, aliases and verse
 * counts never drift between iPhone, Android and the web.
 */
object BibleBooks {
    @Serializable
    private data class File(val books: List<BibleBook>)

    val all: List<BibleBook> by lazy {
        val stream = requireNotNull(BibleBooks::class.java.getResourceAsStream("bibleBooks.json")) {
            "bibleBooks.json is missing from core:domain's resources"
        }
        val text = stream.use { it.readBytes().decodeToString() }
        Json { ignoreUnknownKeys = true }.decodeFromString<File>(text).books
    }

    val oldTestament: List<BibleBook> get() = all.filter { it.testament == Testament.OLD }
    val newTestament: List<BibleBook> get() = all.filter { it.testament == Testament.NEW }

    fun withNumber(number: Int): BibleBook = all[number.coerceIn(1, all.size) - 1]
}
