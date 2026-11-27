package com.genesis.core.domain.reader

import kotlin.test.Test
import kotlin.test.assertEquals

class PaginationTest {
    private fun lines(count: Int, height: Float) =
        List(count) { it * height } to List(count) { (it + 1) * height }

    @Test fun wholeLinesFillEachPage() {
        val (tops, bottoms) = lines(10, 30f)
        assertEquals(listOf(0..3, 4..7, 8..9), Pagination.pages(tops, bottoms, 120f))
    }

    @Test fun aLineThatDoesNotFitStartsTheNextPage() {
        val (tops, bottoms) = lines(5, 30f)
        assertEquals(listOf(0..2, 3..4), Pagination.pages(tops, bottoms, 119f))
    }

    @Test fun aLineTallerThanThePageStillGetsAPage() {
        assertEquals(listOf(0..0, 1..1), Pagination.pages(listOf(0f, 500f), listOf(500f, 530f), 100f))
    }

    @Test fun noLinesNoPages() {
        assertEquals(emptyList(), Pagination.pages(emptyList(), emptyList(), 100f))
    }

    @Test fun everyLineIsOnExactlyOnePage() {
        val heights = listOf(31f, 31f, 18f, 31f, 44f, 31f, 31f, 31f, 18f, 31f, 31f)
        val tops = heights.runningFold(0f) { y, h -> y + h }.dropLast(1)
        val bottoms = tops.zip(heights) { t, h -> t + h }
        val pages = Pagination.pages(tops, bottoms, 100f)
        assertEquals((0..10).toList(), pages.flatMap { it.toList() })
        pages.forEach { page -> assert(bottoms[page.last] - tops[page.first] <= 100f || page.first == page.last) }
    }
}
