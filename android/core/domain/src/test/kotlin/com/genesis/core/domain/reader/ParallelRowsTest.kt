package com.genesis.core.domain.reader

import kotlin.test.Test
import kotlin.test.assertEquals

class ParallelRowsTest {
    @Test fun pairsByNumberAndLeavesGaps() {
        val rows = ParallelRow.merge(listOf(1 to "a", 2 to "b", 4 to "d"), listOf(1 to "A", 3 to "C", 4 to "D"))
        assertEquals(
            listOf(ParallelRow(1, "a", "A"), ParallelRow(2, "b", null), ParallelRow(3, null, "C"), ParallelRow(4, "d", "D")),
            rows,
        )
    }

    @Test fun keepsTheFirstOfARepeatedNumber() {
        assertEquals(listOf(ParallelRow(1, "a", null)), ParallelRow.merge(listOf(1 to "a", 1 to "x"), emptyList()))
    }
}
