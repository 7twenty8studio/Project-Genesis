package com.genesis.core.domain.studyresources

import com.genesis.core.domain.bible.VerseId
import java.security.MessageDigest
import java.util.zip.Deflater
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

class StudyResourcesTest {
    @Test fun blocks() {
        val blocks = StudyMarkup.blocks("## Title\n\n- one\n\nA paragraph.\n\n  \n\n")
        assertEquals(listOf(StudyMarkup.Block.Heading("Title"), StudyMarkup.Block.ListItem("one"), StudyMarkup.Block.Paragraph("A paragraph.")), blocks)
    }

    @Test fun inlineMarkup() {
        val runs = StudyMarkup.runs("God *said*, **Let there** be \\*light\\* [Gen 1:3](verse:1001003) and [*Aaron*](article:tyndale-dictionary/Aaron).")
        assertEquals("God said, Let there be *light* Gen 1:3 and Aaron.", runs.joinToString("") { it.text })
        assertEquals(true, runs.first { it.text == "said" }.italic)
        assertEquals(true, runs.first { it.text == "Let there" }.bold)
        assertEquals("verse:1001003", runs.first { it.text == "Gen 1:3" }.url)
        val aaron = runs.first { it.text == "Aaron" }
        assertEquals(true, aaron.italic)
        assertEquals("article:tyndale-dictionary/Aaron", aaron.url)
        assertEquals("a_b [c]", StudyMarkup.plain("a\\_b \\[c\\]"))
    }

    @Test fun links() {
        assertEquals(StudyMarkup.Link.Verses(StudyRange(VerseId(1, 1, 1), VerseId(1, 2, 3))), StudyMarkup.link("verse:1001001-1002003"))
        assertEquals(StudyMarkup.Link.Verses(StudyRange(VerseId(43, 3, 16), VerseId(43, 3, 16))), StudyMarkup.link("verse:43003016"))
        assertEquals(StudyMarkup.Link.Article("es-palabras", "kt/dios"), StudyMarkup.link("article:es-palabras/kt%2Fdios"))
        assertNull(StudyMarkup.link("verse:12"))
        assertNull(StudyMarkup.link("https://example.com"))
    }

    @Test fun ranges() {
        assertEquals("Genesis 1:1–2:3", StudyRange(VerseId(1, 1, 1), VerseId(1, 2, 3)).description("en"))
        assertEquals("John 3:16", StudyRange(VerseId(43, 3, 16), VerseId(43, 3, 16)).description("en"))
        assertEquals("Psalms 23", StudyRange(VerseId(19, 23, 0), VerseId(19, 23, 6)).description("en"))
        assertEquals("Jude 3", StudyRange(VerseId(65, 1, 3), VerseId(65, 1, 3)).description("en"))
    }

    @Test fun foldingAndLike() {
        assertEquals("genesis", StudyMarkup.folded(" Génesis "))
        assertEquals("50\\%\\_a\\\\", StudyMarkup.likeEscaped("50%_a\\"))
    }

    @Test fun unpacksRawDeflateAndChecksIt() {
        val database = "SQLite format 3".repeat(100).toByteArray()
        val deflater = Deflater(Deflater.BEST_COMPRESSION, true)
        deflater.setInput(database)
        deflater.finish()
        val buffer = ByteArray(4096)
        val packed = buffer.copyOf(deflater.deflate(buffer))
        val sha = MessageDigest.getInstance("SHA-256").digest(database).joinToString("") { "%02x".format(it) }
        assertEquals(database.toList(), PackedFile.unpack(packed, database.size.toLong(), sha).toList())
        assertFailsWith<PackedFile.Damaged> { PackedFile.unpack(packed, database.size.toLong(), "00") }
        assertFailsWith<PackedFile.Damaged> { PackedFile.unpack(packed, database.size.toLong() + 1, sha) }
        assertFailsWith<PackedFile.Damaged> { PackedFile.unpack(byteArrayOf(1, 2, 3), 10, sha) }
    }
}
