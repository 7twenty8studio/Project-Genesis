package com.genesis.app.original

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.original.GreekEdition
import com.genesis.core.domain.original.Morphology
import com.genesis.core.domain.original.OriginalLanguage
import com.genesis.core.domain.original.OriginalSource
import com.genesis.core.domain.original.PartOfSpeech

/**
 * Typefaces for the original languages, shared with iOS: Noto Serif Hebrew
 * (every vowel point and cantillation mark) and EB Garamond (polytonic
 * Greek), both under the SIL Open Font License.
 */
@Composable
internal fun originalFont(language: OriginalLanguage): FontFamily {
    val assets = LocalContext.current.assets
    return remember(language) {
        FontFamily(Font(if (language == OriginalLanguage.HEBREW) "NotoSerifHebrew-Regular.ttf" else "EBGaramond-Regular.ttf", assets))
    }
}

/** Pointed Hebrew needs more size than English to read comfortably. */
internal fun originalReadingSize(size: Double, language: OriginalLanguage): Double =
    if (language == OriginalLanguage.HEBREW) size * 1.3 else size * 1.08

/** A Premium part of a free screen: what it offers; tapping it opens the Premium screen. */
@Composable
internal fun PremiumTeaser(message: String, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.surface)
            .clickable { com.genesis.app.premium.Paywall.open() }.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(stringResource(R.string.premium), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = colors.accent)
        Text(message, style = MaterialTheme.typography.bodyMedium, color = colors.text)
    }
}

/** A speaker button that says the word aloud; pauses listening first. */
@Composable
internal fun PronounceButton(word: String, language: OriginalLanguage) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val speaking by app.pronouncer.speaking.collectAsStateWithLifecycle()
    val isSpeaking = speaking == word
    val colors = LocalReaderColors.current
    val label = stringResource(if (isSpeaking) R.string.stop else R.string.pronounce)
    IconButton(
        onClick = {
            if (isSpeaking) app.pronouncer.stop()
            else {
                if (app.listening.state.value.isPlaying) app.listening.pause()
                app.pronouncer.say(word, language)
            }
        },
        modifier = Modifier.size(44.dp).semantics { contentDescription = label },
    ) {
        Text(if (isSpeaking) "■" else "🔊", fontSize = 20.sp, color = colors.accent)
    }
}

/** Under a word with a [PronounceButton]: which pronunciation, or how to add a voice. */
@Composable
internal fun PronunciationNote(language: OriginalLanguage) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val missing by app.pronouncer.missingVoice.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val text = when {
        missing == language && language == OriginalLanguage.HEBREW -> R.string.pronunciation_missing_hebrew_android
        missing == language -> R.string.pronunciation_missing_greek_android
        language == OriginalLanguage.HEBREW -> R.string.pronunciation_hebrew
        else -> R.string.pronunciation_greek
    }
    Text(
        stringResource(text),
        style = MaterialTheme.typography.bodySmall,
        color = if (missing == language) Color(0xFFC2410C) else colors.secondaryText,
    )
}

/** A label and its value on one row, as LabeledContent on iOS. */
@Composable
internal fun Labeled(label: String, value: String) {
    val colors = LocalReaderColors.current
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodyLarge, color = colors.secondaryText, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.End)
    }
}

@Composable
internal fun languageName(language: OriginalLanguage): String =
    stringResource(if (language == OriginalLanguage.GREEK) R.string.greek else R.string.hebrew)

@Composable
internal fun GreekEdition.title(): String = stringResource(
    when (this) {
        GreekEdition.NESTLE_ALAND -> R.string.edition_na
        GreekEdition.WESTCOTT_HORT -> R.string.edition_wh
        GreekEdition.TEXTUS_RECEPTUS -> R.string.edition_tr
        GreekEdition.BYZANTINE -> R.string.edition_byz
    },
)

@Composable
internal fun GreekEdition.fullName(): String = stringResource(
    when (this) {
        GreekEdition.NESTLE_ALAND -> R.string.edition_na_full
        GreekEdition.WESTCOTT_HORT -> R.string.edition_wh_full
        GreekEdition.TEXTUS_RECEPTUS -> R.string.edition_tr_full
        GreekEdition.BYZANTINE -> R.string.edition_byz_full
    },
)

@Composable
internal fun GreekEdition.about(): String = stringResource(
    when (this) {
        GreekEdition.NESTLE_ALAND -> R.string.edition_na_about
        GreekEdition.WESTCOTT_HORT -> R.string.edition_wh_about
        GreekEdition.TEXTUS_RECEPTUS -> R.string.edition_tr_about
        GreekEdition.BYZANTINE -> R.string.edition_byz_about
    },
)

@Composable
internal fun GreekEdition.dottedWords(): String = stringResource(
    when (this) {
        GreekEdition.NESTLE_ALAND -> R.string.edition_dotted_na
        GreekEdition.WESTCOTT_HORT -> R.string.edition_dotted_wh
        GreekEdition.TEXTUS_RECEPTUS -> R.string.edition_dotted_tr
        GreekEdition.BYZANTINE -> R.string.edition_dotted_byz
    },
)

@Composable
internal fun GreekEdition.lacksWord(): String = stringResource(
    when (this) {
        GreekEdition.NESTLE_ALAND -> R.string.edition_lacks_na
        GreekEdition.WESTCOTT_HORT -> R.string.edition_lacks_wh
        GreekEdition.TEXTUS_RECEPTUS -> R.string.edition_lacks_tr
        GreekEdition.BYZANTINE -> R.string.edition_lacks_byz
    },
)

@Composable
internal fun GreekEdition.readsInstead(reading: String): String = stringResource(
    when (this) {
        GreekEdition.NESTLE_ALAND -> R.string.edition_instead_na
        GreekEdition.WESTCOTT_HORT -> R.string.edition_instead_wh
        GreekEdition.TEXTUS_RECEPTUS -> R.string.edition_instead_tr
        GreekEdition.BYZANTINE -> R.string.edition_instead_byz
    },
    reading,
)

/** "Hebrew: Leningrad Codex", "Greek: Textus Receptus (the KJV's source)". */
@Composable
internal fun sourceHeading(language: OriginalLanguage, greek: OriginalSource.Greek, abbreviation: String): String {
    if (language != OriginalLanguage.GREEK) return stringResource(R.string.hebrew_leningrad)
    val name = greek.edition.title()
    return when {
        !greek.isKnownSource -> stringResource(R.string.greek_edition_heading, name)
        greek.isExact -> stringResource(R.string.greek_edition_exact, name, abbreviation)
        else -> stringResource(R.string.greek_edition_closest, name, abbreviation)
    }
}

/** A grammar line in plain words: its label and value. */
@Composable
internal fun Morphology.Detail.line(): Pair<String, String> = when (this) {
    is Morphology.Detail.Part -> stringResource(R.string.part_of_speech) to stringResource(value.title)
    is Morphology.Detail.Stem -> stringResource(R.string.stem) to name
    is Morphology.Detail.Form -> stringResource(R.string.form) to stringResource(value.title)
    is Morphology.Detail.TenseOf -> stringResource(R.string.tense) to stringResource(value.title)
    is Morphology.Detail.VoiceOf -> stringResource(R.string.voice) to stringResource(value.title)
    is Morphology.Detail.MoodOf -> stringResource(R.string.mood) to stringResource(value.title)
    is Morphology.Detail.Person -> stringResource(R.string.person) to stringResource(personTitle(value))
    is Morphology.Detail.CaseOf -> stringResource(R.string.grammar_case) to stringResource(value.title)
    is Morphology.Detail.GenderOf -> stringResource(R.string.gender) to stringResource(value.title)
    is Morphology.Detail.NumberOf -> stringResource(R.string.number) to stringResource(value.title)
    is Morphology.Detail.StateOf -> stringResource(R.string.state) to stringResource(value.title)
    is Morphology.Detail.JoinedTo -> stringResource(R.string.joined_to) to joinedList(prefixes.map { stringResource(it.title) })
    is Morphology.Detail.PronounSuffix -> stringResource(R.string.pronoun_suffix) to listOfNotNull(
        suffix.person?.takeIf { it in 1..3 }?.let { stringResource(personTitle(it)) },
        suffix.gender?.let { stringResource(it.title) },
        suffix.number?.let { stringResource(it.title) },
    ).joinToString(", ")
}

/** "a, b and c" in the screen's language. */
@Composable
private fun joinedList(items: List<String>): String {
    if (items.size <= 1) return items.firstOrNull().orEmpty()
    return stringResource(R.string.bible_and_language, items.dropLast(1).joinToString(", "), items.last())
}

@StringRes
private fun personTitle(person: Int): Int = when (person) {
    1 -> R.string.first_person
    2 -> R.string.second_person
    else -> R.string.third_person
}

@get:StringRes
private val PartOfSpeech.title: Int
    get() = when (this) {
        PartOfSpeech.NOUN -> R.string.pos_noun
        PartOfSpeech.PROPER_NOUN -> R.string.pos_proper_noun
        PartOfSpeech.VERB -> R.string.pos_verb
        PartOfSpeech.ADJECTIVE -> R.string.pos_adjective
        PartOfSpeech.ADVERB -> R.string.pos_adverb
        PartOfSpeech.PRONOUN -> R.string.pos_pronoun
        PartOfSpeech.PREPOSITION -> R.string.pos_preposition
        PartOfSpeech.CONJUNCTION -> R.string.pos_conjunction
        PartOfSpeech.ARTICLE -> R.string.pos_article
        PartOfSpeech.PARTICLE -> R.string.pos_particle
        PartOfSpeech.INTERJECTION -> R.string.pos_interjection
    }

@get:StringRes
private val Morphology.Gender.title: Int
    get() = when (this) {
        Morphology.Gender.MASCULINE -> R.string.gender_masculine
        Morphology.Gender.FEMININE -> R.string.gender_feminine
        Morphology.Gender.NEUTER -> R.string.gender_neuter
        Morphology.Gender.COMMON -> R.string.gender_common
    }

@get:StringRes
private val Morphology.Number.title: Int
    get() = when (this) {
        Morphology.Number.SINGULAR -> R.string.number_singular
        Morphology.Number.PLURAL -> R.string.number_plural
        Morphology.Number.DUAL -> R.string.number_dual
    }

@get:StringRes
private val Morphology.Case.title: Int
    get() = when (this) {
        Morphology.Case.NOMINATIVE -> R.string.case_nominative
        Morphology.Case.GENITIVE -> R.string.case_genitive
        Morphology.Case.DATIVE -> R.string.case_dative
        Morphology.Case.ACCUSATIVE -> R.string.case_accusative
        Morphology.Case.VOCATIVE -> R.string.case_vocative
    }

@get:StringRes
private val Morphology.State.title: Int
    get() = when (this) {
        Morphology.State.ABSOLUTE -> R.string.state_absolute
        Morphology.State.CONSTRUCT -> R.string.state_construct
        Morphology.State.DETERMINED -> R.string.state_determined
    }

@get:StringRes
private val Morphology.Tense.title: Int
    get() = when (this) {
        Morphology.Tense.PRESENT -> R.string.tense_present
        Morphology.Tense.IMPERFECT -> R.string.tense_imperfect
        Morphology.Tense.FUTURE -> R.string.tense_future
        Morphology.Tense.AORIST -> R.string.tense_aorist
        Morphology.Tense.PERFECT -> R.string.tense_perfect
        Morphology.Tense.PLUPERFECT -> R.string.tense_pluperfect
    }

@get:StringRes
private val Morphology.Voice.title: Int
    get() = when (this) {
        Morphology.Voice.ACTIVE -> R.string.voice_active
        Morphology.Voice.MIDDLE -> R.string.voice_middle
        Morphology.Voice.PASSIVE -> R.string.voice_passive
        Morphology.Voice.MIDDLE_OR_PASSIVE -> R.string.voice_middle_or_passive
        Morphology.Voice.MIDDLE_DEPONENT -> R.string.voice_middle_deponent
        Morphology.Voice.PASSIVE_DEPONENT -> R.string.voice_passive_deponent
        Morphology.Voice.MIDDLE_OR_PASSIVE_DEPONENT -> R.string.voice_middle_or_passive_deponent
    }

@get:StringRes
private val Morphology.Mood.title: Int
    get() = when (this) {
        Morphology.Mood.INDICATIVE -> R.string.mood_indicative
        Morphology.Mood.SUBJUNCTIVE -> R.string.mood_subjunctive
        Morphology.Mood.OPTATIVE -> R.string.mood_optative
        Morphology.Mood.IMPERATIVE -> R.string.mood_imperative
        Morphology.Mood.INFINITIVE -> R.string.mood_infinitive
        Morphology.Mood.PARTICIPLE -> R.string.mood_participle
    }

@get:StringRes
private val Morphology.VerbForm.title: Int
    get() = when (this) {
        Morphology.VerbForm.PERFECT -> R.string.tense_perfect
        Morphology.VerbForm.SEQUENTIAL_PERFECT -> R.string.form_sequential_perfect
        Morphology.VerbForm.IMPERFECT -> R.string.tense_imperfect
        Morphology.VerbForm.SEQUENTIAL_IMPERFECT -> R.string.form_sequential_imperfect
        Morphology.VerbForm.CONJUNCTIVE_IMPERFECT -> R.string.form_conjunctive_imperfect
        Morphology.VerbForm.COHORTATIVE -> R.string.form_cohortative
        Morphology.VerbForm.JUSSIVE -> R.string.form_jussive
        Morphology.VerbForm.IMPERATIVE -> R.string.mood_imperative
        Morphology.VerbForm.ACTIVE_PARTICIPLE -> R.string.form_active_participle
        Morphology.VerbForm.PASSIVE_PARTICIPLE -> R.string.form_passive_participle
        Morphology.VerbForm.INFINITIVE_ABSOLUTE -> R.string.form_infinitive_absolute
        Morphology.VerbForm.INFINITIVE_CONSTRUCT -> R.string.form_infinitive_construct
    }

@get:StringRes
private val Morphology.Prefix.title: Int
    get() = when (this) {
        Morphology.Prefix.CONJUNCTION -> R.string.pos_conjunction
        Morphology.Prefix.PREPOSITION -> R.string.pos_preposition
        Morphology.Prefix.ARTICLE -> R.string.pos_article
        Morphology.Prefix.INTERROGATIVE -> R.string.prefix_interrogative
    }
