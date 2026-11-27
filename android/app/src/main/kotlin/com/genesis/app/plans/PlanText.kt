package com.genesis.app.plans

import android.icu.text.ListFormatter
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.genesis.app.R
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.plans.PlanEnrollment
import com.genesis.core.domain.plans.ReadingPlan
import java.util.Locale

/** The language book names follow on plan screens: the app's own, as on iOS. */
@Composable
internal fun appLanguage(): String = LocalContext.current.resources.configuration.locales[0].language

/** A plan's name: a built-in plan's in the app's language, a custom one as the person named it. */
@Composable
internal fun planTitle(plan: ReadingPlan): String =
    plan.custom?.title ?: builtInTitle(plan.id)?.let { stringResource(it) } ?: plan.id

@Composable
internal fun enrollmentTitle(enrollment: PlanEnrollment): String =
    enrollment.plan?.let { planTitle(it) } ?: enrollment.title

@Composable
internal fun planSummary(plan: ReadingPlan): String {
    plan.custom?.let { return customSummary(it.books, it.days) }
    return builtInSummary(plan.id)?.let { stringResource(it) }.orEmpty()
}

/** "Romans and Galatians, 22 chapters over 10 days.", as ReadingPlan.customSummary on iOS. */
@Composable
internal fun customSummary(books: List<Int>, days: Int): String {
    val language = appLanguage()
    val chapters = books.sumOf { BibleBooks.withNumber(it).chapterCount }
    val names = if (books.size <= 3) {
        ListFormatter.getInstance(Locale.forLanguageTag(language)).format(books.map { BibleBooks.withNumber(it).name(language) })
    } else {
        stringResource(R.string.books_count, books.size)
    }
    return stringResource(R.string.custom_plan_summary, names, chapters, days)
}

private fun builtInTitle(id: String): Int? = when (id) {
    ReadingPlan.ONE_YEAR -> R.string.plan_one_year
    ReadingPlan.NEW_TESTAMENT_90 -> R.string.plan_nt90
    ReadingPlan.CHRONOLOGICAL -> R.string.plan_chronological
    ReadingPlan.GOSPELS -> R.string.plan_gospels
    ReadingPlan.PSALMS -> R.string.plan_psalms
    else -> null
}

private fun builtInSummary(id: String): Int? = when (id) {
    ReadingPlan.ONE_YEAR -> R.string.plan_one_year_summary
    ReadingPlan.NEW_TESTAMENT_90 -> R.string.plan_nt90_summary
    ReadingPlan.CHRONOLOGICAL -> R.string.plan_chronological_summary
    ReadingPlan.GOSPELS -> R.string.plan_gospels_summary
    ReadingPlan.PSALMS -> R.string.plan_psalms_summary
    else -> null
}
