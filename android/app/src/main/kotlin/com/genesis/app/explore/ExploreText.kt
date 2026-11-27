package com.genesis.app.explore

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.genesis.app.R
import com.genesis.core.domain.study.ApproximateYear
import com.genesis.core.domain.study.Person
import com.genesis.core.domain.study.PlaceCertainty
import com.genesis.core.domain.study.TimelineEvent

/** "c. 1491 BC" or "c. AD 30". Dates are approximate and follow a traditional chronology. */
@Composable
internal fun yearLabel(year: Int): String {
    val approximate = ApproximateYear.of(year)
    return stringResource(if (approximate.beforeChrist) R.string.year_bc else R.string.year_ad, approximate.digits)
}

@Composable
internal fun yearLabel(event: TimelineEvent): String? = event.year?.let { yearLabel(it) }

/** "c. 1085 BC – c. 1015 BC", "Born c. 4 BC", or null. */
@Composable
internal fun lifespan(person: Person): String? {
    val born = person.birthYear?.let { yearLabel(it) }
    val died = person.deathYear?.let { yearLabel(it) }
    return when {
        born != null && died != null -> "$born – $died"
        born != null -> stringResource(R.string.born_year, born)
        died != null -> stringResource(R.string.died_year, died)
        else -> null
    }
}

/** Theographic's groups in the app's language, "Tribe of Judah · Apostles"; null when none. */
@Composable
internal fun groupTitle(person: Person): String? {
    val titles = person.groups.map { group ->
        groupTitles[group]?.let { stringResource(it) } ?: group
    }
    return titles.takeIf { it.isNotEmpty() }?.joinToString(" · ")
}

private val groupTitles = mapOf(
    "Apostles" to R.string.group_apostles,
    "Apostles (Post-Ascension)" to R.string.group_apostles_after,
    "Apostles (The Eleven)" to R.string.group_apostles_eleven,
    "Genealogy of Jesus" to R.string.group_genealogy_jesus,
    "Line of Cain" to R.string.group_line_cain,
    "Tribe of Asher" to R.string.group_asher,
    "Tribe of Benjamin" to R.string.group_benjamin,
    "Tribe of Dan" to R.string.group_dan,
    "Tribe of Gad" to R.string.group_gad,
    "Tribe of Issachar" to R.string.group_issachar,
    "Tribe of Joseph" to R.string.group_joseph,
    "Tribe of Judah" to R.string.group_judah,
    "Tribe of Levi" to R.string.group_levi,
    "Tribe of Naphtali" to R.string.group_naphtali,
    "Tribe of Reuben" to R.string.group_reuben,
    "Tribe of Simeon" to R.string.group_simeon,
    "Tribe of Zebulun" to R.string.group_zebulun,
)

/** "City", "Region", …; "Place" where the data doesn't say. */
@Composable
internal fun kindTitle(kind: String): String = when (kind) {
    "" -> stringResource(R.string.place_kind_place)
    "City" -> stringResource(R.string.place_kind_city)
    "Mountain" -> stringResource(R.string.place_kind_mountain)
    "Valley" -> stringResource(R.string.place_kind_valley)
    "Water" -> stringResource(R.string.place_kind_water)
    "Region" -> stringResource(R.string.place_kind_region)
    "Landmark" -> stringResource(R.string.place_kind_landmark)
    "Island" -> stringResource(R.string.place_kind_island)
    "Path" -> stringResource(R.string.place_kind_path)
    else -> kind
}

internal val PlaceCertainty.title: Int
    get() = when (this) {
        PlaceCertainty.KNOWN -> R.string.known_location
        PlaceCertainty.LIKELY -> R.string.likely_location
        PlaceCertainty.UNCERTAIN -> R.string.uncertain_location
    }

internal val PlaceCertainty.explanation: Int
    get() = when (this) {
        PlaceCertainty.KNOWN -> R.string.known_location_detail
        PlaceCertainty.LIKELY -> R.string.likely_location_detail
        PlaceCertainty.UNCERTAIN -> R.string.uncertain_location_detail
    }
