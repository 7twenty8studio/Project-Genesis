package com.genesis.core.domain.studyresources

import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.security.MessageDigest
import java.text.Normalizer
import java.util.zip.Inflater

/** What a study pack holds. */
@Serializable
enum class StudyResourceKind {
    @SerialName("notes") NOTES,
    @SerialName("commentary") COMMENTARY,
    @SerialName("dictionary") DICTIONARY,
    @SerialName("lexicon") LEXICON,
}

/** A study pack that can be downloaded (public.study_resources), as on iOS. */
@Serializable
data class DownloadableStudyResource(
    val id: String,
    val kind: StudyResourceKind,
    val name: String,
    val author: String = "",
    val summary: String = "",
    /** The author's church tradition (evangelical, puritan…), shown so readers know the angle. */
    val tradition: String? = null,
    val language: String = "en",
    val year: String? = null,
    val license: String,
    val attribution: String = "",
    /** Needs Premium to download and read. */
    val premium: Boolean = false,
    @SerialName("file_url") val fileUrl: String,
    @SerialName("file_bytes") val fileBytes: Long,
    @SerialName("database_bytes") val databaseBytes: Long,
    val sha256: String,
    val version: Int,
)

/** A pack saved on this phone. */
@Serializable
data class InstalledStudyResource(val resource: DownloadableStudyResource, val fileName: String)

/** A passage a note or article covers, which can run across chapters. */
data class StudyRange(val start: VerseId, val end: VerseId) {
    /** Verse 0 starts a chapter introduction. */
    val isChapterIntroduction: Boolean get() = start.verse == 0

    fun covers(verse: VerseId): Boolean = verse in start..end

    /** "Genesis 1:1–2:3", "John 3:16", "Psalm 23" (an introduction), in a Bible's language. */
    fun description(language: String): String {
        val book = BibleBooks.withNumber(start.book)
        val name = book.name(language)
        if (isChapterIntroduction) return "$name ${start.chapter}"
        val first = if (book.chapterCount == 1) "$name ${start.verse}" else "$name ${start.chapter}:${start.verse}"
        return when {
            end == start -> first
            end.book != start.book -> "$first–${ReferenceParser.describe(end.rawValue, end.rawValue, language)}"
            end.chapter != start.chapter -> "$first–${end.chapter}:${end.verse}"
            else -> "$first–${end.verse}"
        }
    }

    companion object {
        fun of(start: VerseId, end: VerseId) = StudyRange(start, if (end > start) end else start)
    }
}

data class StudyNote(val id: Int, val range: StudyRange, val title: String?, val text: String)
data class StudyArticleSummary(val id: String, val title: String, val kind: String)
data class StudyArticle(val id: String, val title: String, val kind: String, val text: String)
data class StudyIntroduction(val book: Int, val title: String?, val text: String)

/** A Brown-Driver-Briggs ("bdb") or Liddell-Scott-Jones ("lsj") entry. */
data class StudyLexiconEntry(
    val id: Long,
    val strongs: String,
    val source: String,
    val lemma: String,
    val transliteration: String,
    val gloss: String,
    val definition: String,
)

/**
 * The study packs' light Markdown, as StudyMarkup.swift: one paragraph per
 * blank line, "## " a heading, "- " a list item, and inline only *italic*,
 * **bold** and links to verses ("verse:START-END") or articles
 * ("article:PACK/ID"). Everything else is escaped with a backslash.
 */
object StudyMarkup {
    sealed interface Block {
        val inline: String
        data class Heading(override val inline: String) : Block
        data class ListItem(override val inline: String) : Block
        data class Paragraph(override val inline: String) : Block
    }

    sealed interface Link {
        data class Verses(val range: StudyRange) : Link
        data class Article(val pack: String, val id: String) : Link
    }

    /** A run of inline text with its style; [url] for a link. */
    data class Run(val text: String, val bold: Boolean = false, val italic: Boolean = false, val url: String? = null)

    fun blocks(text: String): List<Block> = text.split("\n\n").mapNotNull { raw ->
        val block = raw.trim()
        when {
            block.isEmpty() -> null
            block.startsWith("## ") -> Block.Heading(block.drop(3))
            block.startsWith("- ") -> Block.ListItem(block.drop(2))
            else -> Block.Paragraph(block)
        }
    }

    /** The inline Markdown as styled runs; links keep their verse: and article: URLs. */
    fun runs(inline: String): List<Run> {
        val runs = mutableListOf<Run>()
        var bold = false
        var italic = false
        var url: String? = null
        val text = StringBuilder()
        fun flush() {
            if (text.isNotEmpty()) runs += Run(text.toString(), bold, italic, url)
            text.clear()
        }
        var i = 0
        while (i < inline.length) {
            val c = inline[i]
            when {
                c == '\\' && i + 1 < inline.length && !inline[i + 1].isLetterOrDigit() && !inline[i + 1].isWhitespace() -> {
                    text.append(inline[i + 1]); i += 2; continue
                }
                c == '*' && inline.startsWith("**", i) && (bold || inline.indexOf("**", i + 2) > 0) -> {
                    flush(); bold = !bold; i += 2; continue
                }
                c == '*' && (italic || inline.indexOf('*', i + 1) > 0) -> {
                    flush(); italic = !italic; i += 1; continue
                }
                c == '[' && url == null -> {
                    val close = closingBracket(inline, i)
                    if (close > 0 && close + 1 < inline.length && inline[close + 1] == '(') {
                        val end = inline.indexOf(')', close + 2)
                        if (end > 0) {
                            flush()
                            val target = inline.substring(close + 2, end)
                            for (inner in runs(inline.substring(i + 1, close))) {
                                runs += inner.copy(bold = inner.bold || bold, italic = inner.italic || italic, url = target)
                            }
                            i = end + 1
                            continue
                        }
                    }
                }
            }
            text.append(c)
            i++
        }
        flush()
        return runs
    }

    private fun closingBracket(text: String, open: Int): Int {
        var i = open + 1
        while (i < text.length) {
            when (text[i]) {
                '\\' -> i++
                ']' -> return i
            }
            i++
        }
        return -1
    }

    /** The text without any markup, for search and accessibility. */
    fun plain(inline: String): String = runs(inline).joinToString("") { it.text }

    fun link(url: String): Link? = when {
        url.startsWith("verse:") -> {
            val parts = url.removePrefix("verse:").split('-')
            val first = parts.firstOrNull()?.toIntOrNull()
            if (first == null || first <= 1_000_000) null
            else {
                val last = parts.getOrNull(1)?.toIntOrNull() ?: first
                Link.Verses(StudyRange.of(VerseId(first), VerseId(last)))
            }
        }
        url.startsWith("article:") -> {
            val path = url.removePrefix("article:")
            val slash = path.indexOf('/')
            if (slash <= 0) null
            else {
                val pack = path.substring(0, slash)
                val id = runCatching { java.net.URLDecoder.decode(path.substring(slash + 1).replace("+", "%2B"), Charsets.UTF_8) }.getOrDefault("")
                if (id.isEmpty()) null else Link.Article(pack, id)
            }
        }
        else -> null
    }

    /** Lower case without accents, as the packs' sort keys are. */
    fun folded(text: String): String =
        Normalizer.normalize(text.lowercase(), Normalizer.Form.NFKD).filter { Character.getType(it) != Character.NON_SPACING_MARK.toInt() }.trim()

    /** Escapes LIKE's wildcards (with "\" as the escape character). */
    fun likeEscaped(text: String): String = text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
}

/** Names for the packs' article kinds. */
enum class StudyArticleKind(val raw: String) {
    PROFILE("profile"), THEME("theme"), KEY_TERM("keyterm"), NAME("name"), TERM("term");

    companion object {
        fun of(raw: String): StudyArticleKind? = entries.firstOrNull { it.raw == raw }
    }
}

/** A downloaded pack (or Bible): raw DEFLATE of the database, checked by size and SHA-256. */
object PackedFile {
    class Damaged : Exception("The download was damaged")

    fun unpack(data: ByteArray, expectedBytes: Long, sha256: String): ByteArray {
        if (expectedBytes <= 0 || expectedBytes > Int.MAX_VALUE) throw Damaged()
        val inflater = Inflater(true)
        val output = ByteArray(expectedBytes.toInt())
        try {
            inflater.setInput(data)
            var written = 0
            while (written < output.size && !inflater.finished()) {
                val count = inflater.inflate(output, written, output.size - written)
                if (count == 0 && (inflater.needsInput() || inflater.needsDictionary())) break
                written += count
            }
            if (written != output.size) throw Damaged()
            // Nothing may follow the expected size.
            if (!inflater.finished() && inflater.inflate(ByteArray(1)) > 0) throw Damaged()
        } catch (error: java.util.zip.DataFormatException) {
            throw Damaged()
        } finally {
            inflater.end()
        }
        val digest = MessageDigest.getInstance("SHA-256").digest(output).joinToString("") { "%02x".format(it) }
        if (digest != sha256.lowercase()) throw Damaged()
        return output
    }
}
