package com.genesis.core.domain.reader

/**
 * One verse number with its text in each Bible read in parallel (null where
 * a Bible has no verse with that number in the chapter), as ParallelRow on iOS.
 */
data class ParallelRow(val number: Int, val primary: String?, val secondary: String?) {
    companion object {
        /** Pairs verses by number; a number only one side uses gets an empty partner. */
        fun merge(first: List<Pair<Int, String>>, second: List<Pair<Int, String>>): List<ParallelRow> {
            val one = LinkedHashMap<Int, String>().apply { first.forEach { (n, t) -> putIfAbsent(n, t) } }
            val two = LinkedHashMap<Int, String>().apply { second.forEach { (n, t) -> putIfAbsent(n, t) } }
            return (one.keys + two.keys).toSortedSet().map { ParallelRow(it, one[it], two[it]) }
        }
    }
}
