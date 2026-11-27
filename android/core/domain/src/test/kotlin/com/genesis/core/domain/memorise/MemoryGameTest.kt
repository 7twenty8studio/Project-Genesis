package com.genesis.core.domain.memorise

import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MemoryGameTest {
    private val john316 = "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life."

    @Test fun wordsRebuildTheVerseExactly() {
        for (text in listOf(john316, "  Jesus wept.", "Selah — and then", "“For I know” — the plans;", "א ALEPH. Blessed")) {
            assertEquals(text, VerseWords(text).text)
        }
        val dash = VerseWords("word — next")
        assertEquals(listOf("word —", "next"), dash.tokens.map { it.text })
    }

    @Test fun tokenCoreAndPunctuation() {
        val token = VerseToken("“For;", " ")
        assertEquals("For", token.core)
        assertEquals("“", token.leadingPunctuation)
        assertEquals(";", token.trailingPunctuation)
    }

    @Test fun keyIgnoresCaseAndAccents() {
        assertEquals(MemoryGame.key("Señor"), MemoryGame.key("senor"))
        assertTrue(MemoryGame.matches("WORLD", VerseToken("world,", " ")))
    }

    @Test fun gapCountsGrowWithMastery() {
        assertEquals(5, MemoryGame.gapCount(25, MemoryMastery.NEW))
        assertEquals(12, MemoryGame.gapCount(100, MemoryMastery.MEMORISED))
        assertEquals(1, MemoryGame.gapCount(1, MemoryMastery.NEW))
        assertEquals(0, MemoryGame.gapCount(0, MemoryMastery.NEW))
    }

    @Test fun fillGapsUsesOnlyTheVersesWordsAndSolves() {
        var game = FillGapsGame.start(john316, MemoryMastery.LEARNING, seed = 42)
        val words = VerseWords(john316).tokens.map { it.core }.toSet()
        assertTrue(game.gaps.isNotEmpty())
        game.choiceSets.forEach { choices ->
            assertTrue(choices.all { it in words })
            assertEquals(choices.map(MemoryGame::key).toSet().size, choices.size)
        }
        val (wrong, ok) = game.choose("zzz")
        assertFalse(ok)
        assertEquals(1, wrong.mistakes)
        game = wrong
        while (!game.isSolved) game = game.choose(game.words.tokens[game.currentGap!!].core).first
        assertEquals(MemoryGrade.HARD, game.grade)
        assertEquals(john316, game.words.text)
    }

    @Test fun sameSeedSameGame() {
        assertEquals(FillGapsGame.start(john316, MemoryMastery.NEW, seed = 7).gaps, FillGapsGame.start(john316, MemoryMastery.NEW, seed = 7).gaps)
    }

    @Test fun wordOrderRebuildsTheVerse() {
        var game = WordOrderGame.start("the Lord is the light", seed = 3)
        assertTrue(game.shuffled != game.words.tokens.indices.toList())
        // Repeated words are interchangeable.
        while (!game.isSolved) {
            val wanted = game.words.tokens[game.placed.size].text
            val chip = game.shuffled.first { !game.isPlaced(it) && game.words.tokens[it].text == wanted }
            game = game.tap(chip).first
        }
        assertEquals("the Lord is the light", game.builtText)
        assertEquals(MemoryGrade.GOOD, game.grade)
    }

    @Test fun gradesFromMistakes() {
        assertEquals(MemoryGrade.GOOD, MemoryGame.grade(0, 8))
        assertEquals(MemoryGrade.HARD, MemoryGame.grade(2, 8))
        assertEquals(MemoryGrade.AGAIN, MemoryGame.grade(3, 8))
    }

    @Test fun scheduleSpacesReviews() {
        val zone = ZoneId.of("America/Chicago")
        val evening = ZonedDateTime.of(2026, 11, 27, 21, 0, 0, 0, zone).toInstant().toEpochMilli()
        val first = MemorySchedule(dueAt = evening).reviewed(MemoryGrade.GOOD, evening, zone)
        assertEquals(1.0, first.intervalDays)
        assertEquals(ZonedDateTime.of(2026, 11, 28, 0, 0, 0, 0, zone).toInstant().toEpochMilli(), first.dueAt)
        val second = first.reviewed(MemoryGrade.GOOD, evening, zone)
        assertEquals(3.0, second.intervalDays)
        assertEquals(8.0, second.reviewed(MemoryGrade.GOOD, evening, zone).intervalDays)
        val again = second.reviewed(MemoryGrade.AGAIN, evening, zone)
        assertEquals(0, again.repetitions)
        assertEquals(evening + 600_000, again.dueAt)
        assertEquals(MemoryMastery.NEW, again.mastery)
    }

    @Test fun hints() {
        assertEquals("For God so loved…", MemoryHint.opening(john316, 4))
        assertEquals("Jesus wept.", MemoryHint.opening("Jesus wept.", 4))
        assertTrue(MemoryHint.isComplete("Jesus wept.", 2))
    }

    @Test fun levels() {
        assertEquals(MemoryLevel.SEED, MemoryLevel.level(0))
        assertEquals(MemoryLevel.SAPLING, MemoryLevel.level(6))
        assertEquals(1f / 7, MemoryLevel.progress(6))
        assertEquals(1f, MemoryLevel.progress(30))
    }

    @Test fun streak() {
        val day = LocalDate.of(2026, 11, 27)
        val one = PracticeStreak().recording(day)
        assertEquals(1, one.count)
        assertEquals(one, one.recording(day))
        val two = one.recording(day.plusDays(1))
        assertEquals(2, two.current(day.plusDays(2)))
        assertEquals(0, two.current(day.plusDays(3)))
        assertEquals(1, two.recording(day.plusDays(4)).count)
        assertEquals(two, PracticeStreak.decode(two.encode()))
    }
}
