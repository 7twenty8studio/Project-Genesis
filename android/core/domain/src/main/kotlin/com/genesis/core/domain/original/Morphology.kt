package com.genesis.core.domain.original

/** A word's part of speech, as PartOfSpeech on iOS. */
enum class PartOfSpeech { NOUN, PROPER_NOUN, VERB, ADJECTIVE, ADVERB, PRONOUN, PREPOSITION, CONJUNCTION, ARTICLE, PARTICLE, INTERJECTION }

/**
 * A morphology code in plain terms, parsed as Morphology.swift: Greek
 * (TAGNT, Robinson style: "V-AAI-3S", "N-GSF") and Hebrew or Aramaic
 * (TAHOT, OSHB style: "HC/Vqw3ms", "HNcmpc/Sp2ms").
 */
class Morphology(code: String, language: OriginalLanguage) {
    enum class Gender { MASCULINE, FEMININE, NEUTER, COMMON }
    enum class Number { SINGULAR, PLURAL, DUAL }
    enum class Case { NOMINATIVE, GENITIVE, DATIVE, ACCUSATIVE, VOCATIVE }
    enum class State { ABSOLUTE, CONSTRUCT, DETERMINED }
    enum class Tense { PRESENT, IMPERFECT, FUTURE, AORIST, PERFECT, PLUPERFECT }
    enum class Voice { ACTIVE, MIDDLE, PASSIVE, MIDDLE_OR_PASSIVE, MIDDLE_DEPONENT, PASSIVE_DEPONENT, MIDDLE_OR_PASSIVE_DEPONENT }
    enum class Mood { INDICATIVE, SUBJUNCTIVE, OPTATIVE, IMPERATIVE, INFINITIVE, PARTICIPLE }
    enum class VerbForm {
        PERFECT, SEQUENTIAL_PERFECT, IMPERFECT, SEQUENTIAL_IMPERFECT, CONJUNCTIVE_IMPERFECT,
        COHORTATIVE, JUSSIVE, IMPERATIVE, ACTIVE_PARTICIPLE, PASSIVE_PARTICIPLE,
        INFINITIVE_ABSOLUTE, INFINITIVE_CONSTRUCT,
    }
    enum class Prefix { CONJUNCTION, PREPOSITION, ARTICLE, INTERROGATIVE }
    data class Suffix(val person: Int?, val gender: Gender?, val number: Number?)

    var partOfSpeech: PartOfSpeech? = null; private set
    /** Hebrew or Aramaic verb stem, named as grammars do: Qal, Niphal… */
    var stem: String? = null; private set
    var verbForm: VerbForm? = null; private set
    var tense: Tense? = null; private set
    var voice: Voice? = null; private set
    var mood: Mood? = null; private set
    var person: Int? = null; private set
    var gender: Gender? = null; private set
    var number: Number? = null; private set
    var grammaticalCase: Case? = null; private set
    var state: State? = null; private set
    var prefixes: List<Prefix> = emptyList(); private set
    var suffix: Suffix? = null; private set
    var isAramaic: Boolean = false; private set

    init {
        if (language == OriginalLanguage.GREEK) parseGreek(code) else parseHebrew(code)
    }

    // Greek

    private fun parseGreek(code: String) {
        val main = code.split(" + ").first()
        val parts = main.split('-').filter { it.isNotEmpty() }
        val head = parts.firstOrNull() ?: return
        when (head) {
            "V" -> {
                partOfSpeech = PartOfSpeech.VERB
                if (parts.size > 1) parseGreekVerb(parts[1])
                if (parts.size > 2) parsePersonOrCase(parts[2])
            }
            "N", "A", "T", "D", "R", "I", "X", "Q", "K", "C" -> {
                partOfSpeech = GREEK_PARTS[head]
                if (parts.size > 1) parseCaseNumberGender(parts[1])
            }
            "P", "F" -> {
                partOfSpeech = PartOfSpeech.PRONOUN
                if (parts.size > 1) parsePersonOrCase(parts[1])
            }
            "S" -> {
                partOfSpeech = PartOfSpeech.PRONOUN
                val digit = parts.getOrNull(1)?.firstOrNull()?.digitToIntOrNull()
                if (digit != null) {
                    person = digit
                    parseCaseNumberGender(parts[1].drop(2))
                }
            }
            else -> partOfSpeech = GREEK_PARTS[head]
        }
    }

    private fun parseGreekVerb(text: String) {
        val letters = text.dropWhile { it.isDigit() }
        if (letters.length < 3) return
        tense = TENSES[letters[0]]
        voice = VOICES[letters[1]]
        mood = MOODS[letters[2]]
    }

    private fun parsePersonOrCase(text: String) {
        val first = text.firstOrNull() ?: return
        val digit = first.digitToIntOrNull()
        if (digit != null) {
            person = digit
            val rest = text.drop(1)
            if (rest.length == 1) number = GREEK_NUMBERS[rest[0]] else parseCaseNumberGender(rest)
        } else {
            parseCaseNumberGender(text)
        }
    }

    private fun parseCaseNumberGender(text: String) {
        val first = text.firstOrNull() ?: return
        grammaticalCase = CASES[first]
        if (text.length > 1) number = GREEK_NUMBERS[text[1]]
        if (text.length > 2) gender = GREEK_GENDERS[text[2]]
    }

    // Hebrew and Aramaic

    private fun parseHebrew(code: String) {
        val language = code.firstOrNull() ?: return
        isAramaic = language == 'A'
        val parts = code.drop(1).split('/').filter { it.isNotEmpty() }
        val mainIndex = parts.indexOfLast { !it.startsWith("S") }
        if (mainIndex < 0) return
        prefixes = parts.subList(0, mainIndex).mapNotNull(::prefixKind)
        parts.drop(mainIndex + 1).firstOrNull { it.startsWith("Sp") }?.let { part ->
            val letters = part.drop(2)
            suffix = Suffix(
                person = letters.firstOrNull()?.digitToIntOrNull(),
                gender = letters.getOrNull(1)?.let(::hebrewGender),
                number = letters.getOrNull(2)?.let(::hebrewNumber),
            )
        }
        parseHebrewWord(parts[mainIndex])
    }

    private fun prefixKind(part: String): Prefix? = when (part) {
        "C", "c" -> Prefix.CONJUNCTION
        "R", "Rd" -> Prefix.PREPOSITION
        "Td" -> Prefix.ARTICLE
        "Ti" -> Prefix.INTERROGATIVE
        else -> null
    }

    private fun parseHebrewWord(letters: String) {
        val head = letters.firstOrNull() ?: return
        val rest = letters.drop(1)
        when (head) {
            'V' -> {
                partOfSpeech = PartOfSpeech.VERB
                if (rest.length < 2) return
                stem = (if (isAramaic) ARAMAIC_STEMS else HEBREW_STEMS)[rest[0]]
                verbForm = VERB_FORMS[rest[1]]
                val tail = rest.drop(2)
                when (verbForm) {
                    VerbForm.ACTIVE_PARTICIPLE, VerbForm.PASSIVE_PARTICIPLE -> parseGenderNumberState(tail)
                    VerbForm.INFINITIVE_ABSOLUTE, VerbForm.INFINITIVE_CONSTRUCT, null -> Unit
                    else -> {
                        person = tail.firstOrNull()?.digitToIntOrNull()
                        if (tail.length > 1) gender = hebrewGender(tail[1])
                        if (tail.length > 2) number = hebrewNumber(tail[2])
                    }
                }
            }
            'N' -> {
                val proper = rest.firstOrNull() == 'p'
                partOfSpeech = if (proper) PartOfSpeech.PROPER_NOUN else PartOfSpeech.NOUN
                if (!proper) parseGenderNumberState(rest.drop(1))
            }
            'A' -> {
                partOfSpeech = PartOfSpeech.ADJECTIVE
                parseGenderNumberState(rest.drop(1))
            }
            'P' -> {
                partOfSpeech = PartOfSpeech.PRONOUN
                if (rest.firstOrNull() == 'p' && rest.length >= 4) {
                    person = rest[1].digitToIntOrNull()
                    gender = hebrewGender(rest[2])
                    number = hebrewNumber(rest[3])
                }
            }
            'R' -> partOfSpeech = PartOfSpeech.PREPOSITION
            'C', 'c' -> partOfSpeech = PartOfSpeech.CONJUNCTION
            'D' -> partOfSpeech = PartOfSpeech.ADVERB
            'T' -> partOfSpeech = when (rest.firstOrNull()) {
                'd' -> PartOfSpeech.ARTICLE
                'j' -> PartOfSpeech.INTERJECTION
                else -> PartOfSpeech.PARTICLE
            }
            else -> Unit
        }
    }

    private fun parseGenderNumberState(letters: String) {
        if (letters.isNotEmpty()) gender = hebrewGender(letters[0])
        if (letters.length > 1) number = hebrewNumber(letters[1])
        if (letters.length > 2) state = STATES[letters[2]]
    }

    private fun hebrewGender(letter: Char): Gender? = when (letter) {
        'm' -> Gender.MASCULINE
        'f' -> Gender.FEMININE
        'b', 'c' -> Gender.COMMON
        else -> null
    }

    private fun hebrewNumber(letter: Char): Number? = when (letter) {
        's' -> Number.SINGULAR
        'p' -> Number.PLURAL
        'd' -> Number.DUAL
        else -> null
    }

    /** The lines of a word's grammar, in the order grammars give them. */
    sealed interface Detail {
        data class Part(val value: PartOfSpeech) : Detail
        data class Stem(val name: String) : Detail
        data class Form(val value: VerbForm) : Detail
        data class TenseOf(val value: Tense) : Detail
        data class VoiceOf(val value: Voice) : Detail
        data class MoodOf(val value: Mood) : Detail
        data class Person(val value: Int) : Detail
        data class CaseOf(val value: Case) : Detail
        data class GenderOf(val value: Gender) : Detail
        data class NumberOf(val value: Number) : Detail
        data class StateOf(val value: State) : Detail
        data class JoinedTo(val prefixes: List<Prefix>) : Detail
        data class PronounSuffix(val suffix: Suffix) : Detail
    }

    val details: List<Detail>
        get() = buildList {
            partOfSpeech?.let { add(Detail.Part(it)) }
            stem?.let { add(Detail.Stem(it)) }
            verbForm?.let { add(Detail.Form(it)) }
            tense?.let { add(Detail.TenseOf(it)) }
            voice?.let { add(Detail.VoiceOf(it)) }
            mood?.let { add(Detail.MoodOf(it)) }
            person?.takeIf { it in 1..3 }?.let { add(Detail.Person(it)) }
            grammaticalCase?.let { add(Detail.CaseOf(it)) }
            gender?.let { add(Detail.GenderOf(it)) }
            number?.let { add(Detail.NumberOf(it)) }
            state?.let { add(Detail.StateOf(it)) }
            if (prefixes.isNotEmpty()) add(Detail.JoinedTo(prefixes))
            suffix?.takeIf { (it.person?.takeIf { p -> p in 1..3 }) != null || it.gender != null || it.number != null }
                ?.let { add(Detail.PronounSuffix(it)) }
        }

    private companion object {
        val GREEK_PARTS = mapOf(
            "N" to PartOfSpeech.NOUN, "A" to PartOfSpeech.ADJECTIVE, "T" to PartOfSpeech.ARTICLE,
            "D" to PartOfSpeech.PRONOUN, "R" to PartOfSpeech.PRONOUN, "I" to PartOfSpeech.PRONOUN,
            "X" to PartOfSpeech.PRONOUN, "Q" to PartOfSpeech.PRONOUN, "K" to PartOfSpeech.PRONOUN, "C" to PartOfSpeech.PRONOUN,
            "ADV" to PartOfSpeech.ADVERB, "CONJ" to PartOfSpeech.CONJUNCTION, "COND" to PartOfSpeech.CONJUNCTION,
            "PREP" to PartOfSpeech.PREPOSITION, "PRT" to PartOfSpeech.PARTICLE, "INJ" to PartOfSpeech.INTERJECTION,
        )
        val TENSES = mapOf('P' to Tense.PRESENT, 'I' to Tense.IMPERFECT, 'F' to Tense.FUTURE, 'A' to Tense.AORIST, 'R' to Tense.PERFECT, 'L' to Tense.PLUPERFECT)
        val VOICES = mapOf(
            'A' to Voice.ACTIVE, 'M' to Voice.MIDDLE, 'P' to Voice.PASSIVE, 'E' to Voice.MIDDLE_OR_PASSIVE,
            'D' to Voice.MIDDLE_DEPONENT, 'O' to Voice.PASSIVE_DEPONENT, 'N' to Voice.MIDDLE_OR_PASSIVE_DEPONENT,
        )
        val MOODS = mapOf(
            'I' to Mood.INDICATIVE, 'S' to Mood.SUBJUNCTIVE, 'O' to Mood.OPTATIVE, 'M' to Mood.IMPERATIVE,
            'N' to Mood.INFINITIVE, 'P' to Mood.PARTICIPLE, 'R' to Mood.PARTICIPLE,
        )
        val CASES = mapOf('N' to Case.NOMINATIVE, 'G' to Case.GENITIVE, 'D' to Case.DATIVE, 'A' to Case.ACCUSATIVE, 'V' to Case.VOCATIVE)
        val GREEK_GENDERS = mapOf('M' to Gender.MASCULINE, 'F' to Gender.FEMININE, 'N' to Gender.NEUTER)
        val GREEK_NUMBERS = mapOf('S' to Number.SINGULAR, 'P' to Number.PLURAL)
        val STATES = mapOf('a' to State.ABSOLUTE, 'c' to State.CONSTRUCT, 'd' to State.DETERMINED)
        val VERB_FORMS = mapOf(
            'p' to VerbForm.PERFECT, 'q' to VerbForm.SEQUENTIAL_PERFECT, 'i' to VerbForm.IMPERFECT, 'w' to VerbForm.SEQUENTIAL_IMPERFECT,
            'u' to VerbForm.CONJUNCTIVE_IMPERFECT, 'h' to VerbForm.COHORTATIVE, 'j' to VerbForm.JUSSIVE, 'v' to VerbForm.IMPERATIVE,
            'r' to VerbForm.ACTIVE_PARTICIPLE, 's' to VerbForm.PASSIVE_PARTICIPLE, 'a' to VerbForm.INFINITIVE_ABSOLUTE, 'c' to VerbForm.INFINITIVE_CONSTRUCT,
        )
        val HEBREW_STEMS = mapOf(
            'q' to "Qal", 'N' to "Niphal", 'p' to "Piel", 'P' to "Pual", 'h' to "Hiphil", 'H' to "Hophal",
            't' to "Hithpael", 'o' to "Polel", 'O' to "Polal", 'r' to "Hithpolel", 'm' to "Poel", 'M' to "Poal",
            'k' to "Palel", 'K' to "Pulal", 'Q' to "Qal passive", 'l' to "Pilpel", 'L' to "Polpal",
            'f' to "Hithpalpel", 'D' to "Nithpael", 'j' to "Pealal", 'i' to "Pilel", 'u' to "Hothpaal",
            'c' to "Tiphil", 'v' to "Hishtaphel", 'w' to "Nithpalel", 'y' to "Nithpoel", 'z' to "Hithpoel",
        )
        val ARAMAIC_STEMS = mapOf(
            'q' to "Peal", 'Q' to "Peil", 'u' to "Hithpeel", 'p' to "Pael", 'P' to "Ithpaal", 'M' to "Hithpaal",
            'a' to "Aphel", 'h' to "Haphel", 's' to "Saphel", 'e' to "Shaphel", 'H' to "Hophal", 'i' to "Ithpeel",
            't' to "Hishtaphel", 'v' to "Ishtaphel", 'w' to "Hithaphel", 'o' to "Polel", 'z' to "Ithpoel",
            'r' to "Hithpolel", 'f' to "Hithpalpel", 'b' to "Hephal", 'c' to "Tiphel", 'm' to "Poel",
            'l' to "Palpel", 'L' to "Ithpalpel", 'O' to "Ithpolel", 'G' to "Ittaphal",
        )
    }
}
