package com.genesis.core.domain.bible

/**
 * A translation-independent verse address, encoded as
 * `book * 1_000_000 + chapter * 1_000 + verse`: the `id` column of every
 * bundled Bible database, so ids sort in canonical order and a chapter is a
 * contiguous id range. Same as `VerseID` on iOS.
 */
@JvmInline
value class VerseId(val rawValue: Int) : Comparable<VerseId> {
    constructor(book: Int, chapter: Int, verse: Int) : this(book * 1_000_000 + chapter * 1_000 + verse)

    val book: Int get() = rawValue / 1_000_000
    val chapter: Int get() = (rawValue / 1_000) % 1_000
    val verse: Int get() = rawValue % 1_000
    val chapterId: ChapterId get() = ChapterId(book, chapter)

    override fun compareTo(other: VerseId): Int = rawValue.compareTo(other.rawValue)
    override fun toString(): String = "$book.$chapter.$verse"
}

/** A book and chapter, independent of translation. */
data class ChapterId(val book: Int, val chapter: Int) : Comparable<ChapterId> {
    val firstVerse: VerseId get() = VerseId(book, chapter, 1)

    /** Inclusive id range covering every possible verse in the chapter. */
    val verseRange: IntRange
        get() = VerseId(book, chapter, 0).rawValue..VerseId(book, chapter, 999).rawValue

    val bibleBook: BibleBook get() = BibleBooks.withNumber(book)

    /** The following chapter in canonical order, crossing book boundaries. */
    val next: ChapterId?
        get() = when {
            chapter < bibleBook.chapterCount -> ChapterId(book, chapter + 1)
            book < BibleBooks.all.size -> ChapterId(book + 1, 1)
            else -> null
        }

    /** The preceding chapter in canonical order, crossing book boundaries. */
    val previous: ChapterId?
        get() = when {
            chapter > 1 -> ChapterId(book, chapter - 1)
            book > 1 -> BibleBooks.withNumber(book - 1).let { ChapterId(it.id, it.chapterCount) }
            else -> null
        }

    override fun compareTo(other: ChapterId): Int =
        compareValuesBy(this, other, ChapterId::book, ChapterId::chapter)

    /** "John 3", "Juan 3" or "João 3", in a Bible's language. */
    fun description(language: String): String = "${bibleBook.name(language)} $chapter"

    companion object {
        val genesis1 = ChapterId(1, 1)
        val john1 = ChapterId(43, 1)
    }
}
