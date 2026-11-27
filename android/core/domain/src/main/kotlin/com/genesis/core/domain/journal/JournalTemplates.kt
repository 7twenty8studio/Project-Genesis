package com.genesis.core.domain.journal

/**
 * Starting shapes for a prayer or sermon notes (Premium, `.journalExtras`),
 * as JournalTemplate on iOS: headings with a short prompt under each, in the
 * app's language. The app's own words, never Scripture. The words are string
 * resources; this holds the shapes and how a template goes into a body.
 */
enum class JournalTemplate(val rawValue: String, val isSermon: Boolean, val parts: Int) {
    ACTS("acts", false, 4),
    GRATITUDE("gratitude", false, 3),
    FOR_OTHERS("forOthers", false, 4),
    LAMENT("lament", false, 4),
    MORNING_OFFERING("morningOffering", false, 3),
    MAIN_POINTS("mainPoints", true, 3),
    OBSERVATION("observation", true, 3),
    DISCUSSION("discussion", true, 3),
    OUTLINE("outline", true, 3);

    data class Part(val heading: String, val prompt: String)

    /** Plain headings for a prayer, Markdown ("## ", italic prompt) for sermon notes. */
    fun text(parts: List<Part>): String = parts.joinToString("\n") { part ->
        if (isSermon) "## ${part.heading}\n*${part.prompt}*\n" else "${part.heading}\n${part.prompt}\n"
    }

    data class Inserted(val text: String, val cursor: Int)

    companion object {
        fun templates(sermon: Boolean): List<JournalTemplate> = entries.filter { it.isSermon == sermon }

        /**
         * The template in place of an empty body, or as new paragraphs at
         * `offset` (the cursor) or at the end. The cursor goes to the end of
         * the inserted template.
         */
        fun inserting(template: String, body: String, offset: Int? = null): Inserted {
            if (body.isBlank()) return Inserted(template, template.length)
            val position = (offset ?: body.length).coerceIn(0, body.length)
            val before = body.substring(0, position)
            val after = body.substring(position)
            val (prefix, suffix) = separators(before, after)
            return Inserted(before + prefix + template + suffix + after, before.length + prefix.length + template.length)
        }

        /** A blank line before, unless a paragraph starts there already; a line break after when text follows. */
        fun separators(before: String, after: String): Pair<String, String> {
            val prefix = when {
                before.isEmpty() || before.endsWith("\n\n") -> ""
                before.endsWith("\n") -> "\n"
                else -> "\n\n"
            }
            val suffix = if (after.isNotEmpty() && !after.startsWith("\n")) "\n" else ""
            return prefix to suffix
        }
    }
}
