package com.genesis.core.domain.memorise

import java.text.Normalizer

// Memorize games (Premium), as MemoryGame.swift on iOS. Everything here works
// on the passage's own words, exactly as the Bible database gives them: words
// are only hidden, shuffled or offered as choices, never invented, shortened
// or respelled. Joining the tokens back together reproduces the verse string
// character for character.

private fun Int.isWordCodePoint(): Boolean = Character.isLetter(this) || Character.isDigit(this) ||
    Character.getType(this).let { it == Character.LETTER_NUMBER.toInt() || it == Character.OTHER_NUMBER.toInt() }

private fun String.hasWordCharacter(): Boolean = codePoints().anyMatch { it.isWordCodePoint() }

/** One word of a passage as it appears, with its punctuation attached. */
data class VerseToken(
    /** The word as written, punctuation included ("heart;", "“For"). */
    val text: String,
    /** The whitespace that followed it in the passage ("" after the last word). */
    val trailing: String,
) {
    /** True when the token holds a letter or digit (not just punctuation). */
    val hasLetters: Boolean get() = text.hasWordCharacter()

    private val firstWord: Int get() = indexOfWord(first = true)
    private val lastWordEnd: Int get() = indexOfWord(first = false)

    /** UTF-16 index of the first word character, or the end after the last one; -1 if none. */
    private fun indexOfWord(first: Boolean): Int {
        var index = 0
        var found = -1
        while (index < text.length) {
            val cp = text.codePointAt(index)
            val next = index + Character.charCount(cp)
            if (cp.isWordCodePoint()) {
                if (first) return index
                found = next
            }
            index = next
        }
        return found
    }

    /** The word without the punctuation around it ("heart" for "heart;"). */
    val core: String get() {
        val start = firstWord
        if (start < 0) return text
        return text.substring(start, lastWordEnd)
    }

    /** Punctuation before the word ("“" for "“For"). */
    val leadingPunctuation: String get() = firstWord.let { if (it < 0) "" else text.substring(0, it) }

    /** Punctuation after the word (";" for "heart;"). */
    val trailingPunctuation: String get() = lastWordEnd.let { if (it < 0) "" else text.substring(it) }
}

/**
 * A passage split into words, keeping every character so it can be rebuilt
 * exactly. Splits on whitespace only, so punctuation stays with its word; a
 * lone mark (an em dash between spaces) joins the word before it.
 */
class VerseWords(text: String) {
    /** Whitespace before the first word (normally ""). */
    val leading: String
    val tokens: List<VerseToken>

    init {
        val leading = StringBuilder()
        val pieces = mutableListOf<Pair<String, String>>()
        val word = StringBuilder()
        val space = StringBuilder()
        for (character in text) {
            if (character.isWhitespace()) {
                if (pieces.isEmpty() && word.isEmpty()) leading.append(character) else space.append(character)
            } else {
                if (space.isNotEmpty()) {
                    pieces += word.toString() to space.toString()
                    word.clear()
                    space.clear()
                }
                word.append(character)
            }
        }
        if (word.isNotEmpty()) pieces += word.toString() to space.toString()

        // Punctuation-only pieces join a neighbouring word so every chip is a word.
        val tokens = mutableListOf<VerseToken>()
        var pendingPrefix = ""
        for ((piece, trailing) in pieces) {
            val isPunctuation = !piece.hasWordCharacter()
            if (isPunctuation && tokens.isNotEmpty()) {
                val previous = tokens.last()
                tokens[tokens.lastIndex] = VerseToken(previous.text + previous.trailing + piece, trailing)
            } else if (isPunctuation) {
                pendingPrefix += piece + trailing
            } else {
                tokens += VerseToken(pendingPrefix + piece, trailing)
                pendingPrefix = ""
            }
        }
        if (pendingPrefix.isNotEmpty()) {
            // Nothing but punctuation: keep it as one token so nothing is lost.
            val body = pendingPrefix.trimEnd()
            tokens += VerseToken(body, pendingPrefix.substring(body.length))
        }
        this.leading = leading.toString()
        this.tokens = tokens
    }

    /** The passage rebuilt from its tokens: identical to the text it came from. */
    val text: String get() = join(leading, tokens)

    companion object {
        fun join(leading: String, tokens: Iterable<VerseToken>): String = leading + tokens.joinToString("") { it.text + it.trailing }
    }
}

/** A small deterministic random source (SplitMix64), so a seed always gives the same gaps, choices and shuffles in tests. */
class SeededGenerator(seed: Long) {
    private var state = seed

    fun next(): Long {
        state += -0x61c8864680b583ebL
        var z = state
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
        return z xor (z ushr 31)
    }

    /** 0 until `bound`. */
    fun nextInt(bound: Int): Int = java.lang.Long.remainderUnsigned(next(), bound.toLong()).toInt()

    fun <T> shuffled(items: List<T>): List<T> {
        val list = items.toMutableList()
        for (i in list.lastIndex downTo 1) {
            val j = nextInt(i + 1)
            val swap = list[i]
            list[i] = list[j]
            list[j] = swap
        }
        return list
    }
}

/** Rules shared by the games. */
object MemoryGame {
    /** The most gaps in one passage, so a long passage stays a short game. */
    const val MAXIMUM_GAPS = 12

    /** Choices offered for each gap (the answer plus decoys), when the words allow. */
    const val CHOICE_COUNT = 4

    /** A short game: Speed Round's minute sets its own limit. */
    const val GAME_LENGTH = 10

    /** How many words to hide: more as the passage becomes better known. */
    fun gapCount(wordCount: Int, mastery: MemoryMastery): Int {
        if (wordCount <= 0) return 0
        val share = when (mastery) {
            MemoryMastery.NEW -> 0.2
            MemoryMastery.LEARNING -> 0.35
            MemoryMastery.FAMILIAR -> 0.5
            MemoryMastery.MEMORISED -> 0.7
        }
        val count = maxOf(1, Math.round(wordCount * share).toInt())
        return minOf(count, wordCount, MAXIMUM_GAPS)
    }

    /** Token positions to hide (ascending), chosen among real words only. */
    fun gaps(words: List<VerseToken>, count: Int, seed: Long): List<Int> {
        val candidates = words.indices.filter { words[it].hasLetters }
        if (count <= 0 || candidates.isEmpty()) return emptyList()
        return SeededGenerator(seed).shuffled(candidates).take(count).sorted()
    }

    /**
     * Words to choose from for one gap: the answer and up to `count - 1` decoys,
     * all taken verbatim from the passage (then from nearby verses in `extra`
     * when the passage is short). No decoy matches the answer.
     */
    fun choices(answer: VerseToken, words: List<VerseToken>, extra: List<VerseToken> = emptyList(), count: Int = CHOICE_COUNT, seed: Long): List<String> {
        val generator = SeededGenerator(seed)
        val seen = mutableSetOf(key(answer.core))
        fun distinct(tokens: List<VerseToken>) = tokens.filter { it.hasLetters && seen.add(key(it.core)) }.map { it.core }
        val own = generator.shuffled(distinct(words))
        val nearby = generator.shuffled(distinct(extra))
        val decoys = (own + nearby).take(maxOf(0, count - 1))
        return generator.shuffled(decoys + answer.core)
    }

    /** True when a chosen word is the hidden one (ignoring case and accents). */
    fun matches(choice: String, answer: VerseToken): Boolean = key(choice) == key(answer.core)

    fun key(word: String): String =
        Normalizer.normalize(word.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")

    /**
     * How a finished game maps onto the review schedule. A clean game is
     * "Good", a slip or two "Hard", many mistakes "Again". Games never give
     * "Easy": choosing or reordering words is recognition, a little easier
     * than recalling the passage unaided.
     */
    fun grade(mistakes: Int, steps: Int): MemoryGrade = when {
        mistakes <= 0 -> MemoryGrade.GOOD
        mistakes <= maxOf(1, steps / 4) -> MemoryGrade.HARD
        else -> MemoryGrade.AGAIN
    }

    /** Speed Round is honest self-grading: "I knew it" is good, "Not yet" brings it back soon. */
    fun speedGrade(knewIt: Boolean): MemoryGrade = if (knewIt) MemoryGrade.GOOD else MemoryGrade.AGAIN

    fun randomSeed(): Long = kotlin.random.Random.nextLong()
}

/** Fill the Gaps: some words are hidden; the person picks each in turn from a few of the passage's own words. */
data class FillGapsGame(
    val words: VerseWords,
    /** Hidden token positions, in reading order. */
    val gaps: List<Int>,
    /** The choices for each gap, in the same order as `gaps`. */
    val choiceSets: List<List<String>>,
    val filled: Int = 0,
    val mistakes: Int = 0,
) {
    val isSolved: Boolean get() = filled >= gaps.size

    /** The token waiting to be filled. */
    val currentGap: Int? get() = if (isSolved) null else gaps[filled]

    val currentChoices: List<String> get() = if (isSolved) emptyList() else choiceSets[filled]

    fun isHidden(index: Int): Boolean = gaps.drop(filled).contains(index)

    fun wasFilled(index: Int): Boolean = gaps.take(filled).contains(index)

    /** Tries a choice for the current gap: the game after it, and whether it was right. */
    fun choose(choice: String): Pair<FillGapsGame, Boolean> {
        val index = currentGap ?: return this to false
        return if (MemoryGame.matches(choice, words.tokens[index])) copy(filled = filled + 1) to true
        else copy(mistakes = mistakes + 1) to false
    }

    val grade: MemoryGrade get() = MemoryGame.grade(mistakes, gaps.size)

    companion object {
        /** `nearby`: neighbouring verses' text, used only for decoys. */
        fun start(text: String, mastery: MemoryMastery, nearby: List<String> = emptyList(), seed: Long): FillGapsGame {
            val words = VerseWords(text)
            val wordCount = words.tokens.count { it.hasLetters }
            val gaps = MemoryGame.gaps(words.tokens, MemoryGame.gapCount(wordCount, mastery), seed)
            val extra = nearby.flatMap { VerseWords(it).tokens }
            val choices = gaps.mapIndexed { offset, index -> MemoryGame.choices(words.tokens[index], words.tokens, extra, seed = seed + offset + 1) }
            return FillGapsGame(words, gaps, choices)
        }
    }
}

/** Word Order: the passage's words as shuffled chips, tapped back in order. */
data class WordOrderGame(
    val words: VerseWords,
    /** Chip order on screen, as positions in `words.tokens`. */
    val shuffled: List<Int>,
    /** Chips placed so far, in order. */
    val placed: List<Int> = emptyList(),
    val mistakes: Int = 0,
) {
    val isSolved: Boolean get() = placed.size >= words.tokens.size

    fun isPlaced(index: Int): Boolean = index in placed

    /**
     * Tries a chip as the next word. Repeated words ("the", "and") are
     * interchangeable: any chip with the same text fits. A wrong chip counts a
     * mistake and doesn't advance.
     */
    fun tap(index: Int): Pair<WordOrderGame, Boolean> {
        if (isSolved || index !in words.tokens.indices || isPlaced(index)) return this to false
        return if (words.tokens[index].text == words.tokens[placed.size].text) copy(placed = placed + index) to true
        else copy(mistakes = mistakes + 1) to false
    }

    /** The passage so far; once solved it is exactly the verse text. */
    val builtText: String get() = VerseWords.join(words.leading, words.tokens.take(placed.size))

    val grade: MemoryGrade get() = MemoryGame.grade(mistakes, words.tokens.size)

    companion object {
        fun start(text: String, seed: Long): WordOrderGame {
            val words = VerseWords(text)
            var order = SeededGenerator(seed).shuffled(words.tokens.indices.toList())
            // Never hand over the answer already in order.
            if (order.size > 1 && order == words.tokens.indices.toList()) order = listOf(order[1], order[0]) + order.drop(2)
            return WordOrderGame(words, order)
        }
    }
}
