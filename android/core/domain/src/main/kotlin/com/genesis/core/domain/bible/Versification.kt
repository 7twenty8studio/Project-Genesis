package com.genesis.core.domain.bible

/**
 * Which KJV verses hold the same text as one or more verses of another
 * Bible, as VerseAlignment on iOS. Usually one to one; a verse can hold two
 * KJV verses, two verses can share one, or a verse can have none (the
 * WEB's empty Romans 16:25, whose words it prints at 14:24–26).
 */
data class VerseAlignment(val verses: List<VerseId>, val kjv: List<VerseId>)

/**
 * How one Bible's verse numbers line up with the KJV's (which church sermon
 * references and the Hebrew and Greek follow). Only the verses numbered
 * differently are listed. The same as VersificationMap on iOS.
 */
class VersificationMap(exceptions: List<VerseAlignment>) {
    private val table: Map<VerseId, VerseAlignment> = buildMap { exceptions.forEach { a -> a.verses.forEach { put(it, a) } } }
    private val byKjv: Map<VerseId, VerseAlignment> = buildMap { exceptions.forEach { a -> a.kjv.forEach { put(it, a) } } }
    private val claimed: Set<VerseId> = exceptions.flatMap { it.kjv }.toSet()

    /** This Bible's own first and last verse holding the KJV's `start..end`. */
    fun ownRange(start: VerseId, end: VerseId): Pair<VerseId, VerseId> {
        val first = byKjv[start]?.verses?.first() ?: start
        val last = byKjv[end]?.verses?.last() ?: end
        return minOf(first, last) to maxOf(first, last)
    }

    /** The alignment a verse belongs to. */
    fun alignment(verse: VerseId): VerseAlignment =
        table[verse] ?: VerseAlignment(listOf(verse), if (verse in claimed) emptyList() else listOf(verse))

    /** The alignments covering a chapter's verses, in order, each once. */
    fun alignments(verses: List<VerseId>): List<VerseAlignment> = verses.map(::alignment).distinct()

    companion object {
        val KJV = VersificationMap(emptyList())
    }
}

/**
 * The Bibles whose numbering has been checked against the KJV, as
 * OriginalVersification on iOS: KJV and ASV share it; the WEB prints Romans
 * 16:25–27 at 14:24–26; the NIV divides 3 John 14 in two. Every other Bible
 * is read with the KJV's numbers (`parallelMap`).
 */
object OriginalVersification {
    private val web = VersificationMap(
        (24..26).map { VerseAlignment(listOf(VerseId(45, 14, it)), listOf(VerseId(45, 16, it + 1))) } +
            VerseAlignment(listOf(VerseId(45, 16, 25)), emptyList()),
    )
    private val niv = VersificationMap(listOf(VerseAlignment(listOf(VerseId(64, 1, 14), VerseId(64, 1, 15)), listOf(VerseId(64, 1, 14)))))

    fun map(translationId: String): VersificationMap? = when (translationId) {
        "KJV", "ASV" -> VersificationMap.KJV
        "WEB" -> web
        "NIV" -> niv
        else -> null
    }

    fun parallelMap(translationId: String): VersificationMap = map(translationId) ?: VersificationMap.KJV
}
