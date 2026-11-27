package com.genesis.core.domain.reader

/**
 * Splits laid-out lines into pages: as many whole lines as fit the page's
 * height, never cutting a line, always at least one line per page. Pure, so
 * it's tested apart from the text engine; the reader gives it the lines'
 * tops and bottoms in pixels.
 */
object Pagination {
    fun pages(lineTops: List<Float>, lineBottoms: List<Float>, pageHeight: Float): List<IntRange> {
        require(lineTops.size == lineBottoms.size) { "Every line needs a top and a bottom" }
        if (lineTops.isEmpty()) return emptyList()
        val pages = mutableListOf<IntRange>()
        var first = 0
        while (first < lineTops.size) {
            val top = lineTops[first]
            var last = first
            while (last + 1 < lineTops.size && lineBottoms[last + 1] - top <= pageHeight) last++
            pages += first..last
            first = last + 1
        }
        return pages
    }
}
