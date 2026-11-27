package com.genesis.app.original

import android.content.Context
import com.genesis.app.VerselyApplication
import com.genesis.app.reader.ReaderViewModel
import com.genesis.core.bible.Translation
import com.genesis.core.bible.Verse
import com.genesis.core.bible.WordStudyRepository
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.OriginalVersification
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.original.CommentaryPassage
import com.genesis.core.domain.original.GreekEdition
import com.genesis.core.domain.original.LexiconEntry
import com.genesis.core.domain.original.OriginalParallel
import com.genesis.core.domain.original.OriginalParallelRow
import com.genesis.core.domain.original.OriginalSource
import com.genesis.core.domain.original.OriginalWord
import com.genesis.core.domain.original.ParallelVerse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** The app's language for the lexicon and commentary: "en", "es" or "pt". */
internal fun Context.studyLanguage(): String = resources.configuration.locales[0].language.let { if (it in WordStudyRepository.TRANSLATED) it else "en" }

internal suspend fun Context.wordStudy(): WordStudyRepository? {
    val app = applicationContext as VerselyApplication
    val language = studyLanguage()
    return withContext(Dispatchers.IO) { app.wordStudy(language) }
}

/** One chapter of the Original parallel, ready to show. */
data class OriginalChapter(
    val chapter: ChapterId,
    val translation: Translation,
    val greek: OriginalSource.Greek,
    val rows: List<OriginalParallelRow>,
    /** Word meanings are translated ones (the note and credit show). */
    val glossesTranslated: Boolean,
    val lexiconTranslated: Boolean,
)

/** The chapter's verses, verbatim, beside the Hebrew or Greek of the KJV verses they hold. */
internal suspend fun ReaderViewModel.originalChapter(context: Context, chapter: ChapterId, glossLanguage: (Translation) -> String, unlocked: Boolean): OriginalChapter? {
    val wordStudy = context.wordStudy() ?: return null
    return withBible { bible ->
        val translation = bible.translation
        val map = OriginalVersification.parallelMap(translation.id)
        val greek = OriginalSource.parallelGreek(translation.id)
        val verses = bible.chapter(chapter).verses.map { ParallelVerse(it.id, it.displayText) }
        val gloss = glossLanguage(translation)
        val needed = OriginalParallel.kjvVerses(verses.map { it.id }, map)
        val words = wordStudy.words(needed, greek.edition, gloss)
        OriginalChapter(
            chapter = chapter,
            translation = translation,
            greek = greek,
            rows = OriginalParallel.rows(verses, map, words, if (unlocked) null else OriginalParallel.PREVIEW_VERSES),
            glossesTranslated = wordStudy.hasTranslatedGlosses(gloss),
            lexiconTranslated = wordStudy.language != null,
        )
    }
}

/** What the word sheet adds to a word: its entry, how often it's used and another edition's reading. */
data class WordDetails(val entry: LexiconEntry?, val count: Int, val alternative: String?)

internal suspend fun Context.wordDetails(word: OriginalWord): WordDetails {
    val wordStudy = wordStudy() ?: return WordDetails(null, 0, null)
    return withContext(Dispatchers.IO) {
        runCatching {
            val compared = if (word.isNotInComparison) word.edition?.comparison else null
            WordDetails(
                entry = word.strongs?.let(wordStudy::entry),
                count = word.strongs?.let(wordStudy::occurrences) ?: 0,
                alternative = compared?.let { wordStudy.reading(word, it) },
            )
        }.getOrDefault(WordDetails(null, 0, null))
    }
}

/** A verse's word study: the verse verbatim, its Hebrew or Greek words and Henry on the passage. */
data class VerseStudy(
    val verse: VerseId,
    val text: String,
    val language: String,
    val words: List<OriginalWord>,
    val commentary: List<CommentaryPassage>,
    val glossesTranslated: Boolean,
    val lexiconTranslated: Boolean,
    val commentaryTranslated: Boolean,
)

internal suspend fun ReaderViewModel.verseStudy(context: Context, verse: VerseId, glossLanguage: (Translation) -> String): VerseStudy? {
    val wordStudy = context.wordStudy() ?: return null
    return withBible { bible ->
        val translation = bible.translation
        val gloss = glossLanguage(translation)
        // The KJV verses (the word data's numbering) holding this verse's text.
        val kjv = OriginalVersification.map(translation.id)?.alignment(verse)?.kjv ?: listOf(verse)
        VerseStudy(
            verse = verse,
            text = bible.verses(listOf(verse))[verse]?.text.orEmpty(),
            language = translation.language,
            words = kjv.flatMap { wordStudy.words(it, GreekEdition.TEXTUS_RECEPTUS, gloss) },
            commentary = kjv.firstOrNull()?.let(wordStudy::commentary).orEmpty(),
            glossesTranslated = wordStudy.hasTranslatedGlosses(gloss),
            lexiconTranslated = wordStudy.language != null,
            commentaryTranslated = wordStudy.commentaryLanguage != null,
        )
    }
}

/** One Strong's entry with the verses that use it, verbatim from the Bible being read. */
data class LexiconPage(val entry: LexiconEntry, val count: Int, val verses: List<Verse>, val language: String)

/** Verses listed under an entry (the count covers them all). */
internal const val LEXICON_VERSE_LIMIT = 60

internal suspend fun ReaderViewModel.lexiconPage(context: Context, strongs: String): LexiconPage? {
    val wordStudy = context.wordStudy() ?: return null
    return withBible { bible ->
        val entry = wordStudy.entry(strongs) ?: return@withBible null
        val ids = wordStudy.verses(strongs, LEXICON_VERSE_LIMIT)
        val found = bible.verses(ids)
        LexiconPage(entry, wordStudy.occurrences(strongs), ids.mapNotNull { found[it] }, bible.translation.language)
    }
}
