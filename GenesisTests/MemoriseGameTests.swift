import Foundation
import SwiftData
import Testing
@testable import Genesis

// Verbatim verses (KJV, RV1909) plus awkward spacing and punctuation.
private let memoriseSamples = [
    "Trust in the LORD with all thine heart; and lean not unto thine own understanding.",
    "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.",
    "Porque de tal manera amó Dios al mundo, que ha dado á su Hijo unigénito, para que todo aquel que en él cree, no se pierda, mas tenga vida eterna.",
    "And he said \u{2014} Behold, I come.",
    "\u{2014} The LORD is my shepherd; I shall not want.",
    "  In the  beginning\tGod created the heaven and the earth. ",
    "Jesus wept.",
    "\u{2014} \u{2014}",
    "",
]

@Suite("Memorize games")
@MainActor
struct MemoriseGameTests {
    private var samples: [String] { memoriseSamples }

    // MARK: Tokenising

    @Test("Tokens rejoin to the exact verse", arguments: memoriseSamples)
    func tokensRejoinVerbatim(_ verse: String) {
        #expect(VerseWords(verse).text == verse)
    }

    @Test func punctuationStaysWithItsWord() {
        let words = VerseWords(samples[0]).tokens.map(\.text)
        #expect(words.contains("heart;"))
        #expect(words.contains("understanding."))
        #expect(words.count == 15)

        let dash = VerseWords(samples[3]).tokens
        #expect(dash.map(\.text) == ["And", "he", "said \u{2014}", "Behold,", "I", "come."], "A lone dash joins the word before it")
        let dashWords = dash.allSatisfy(\.hasLetters)
        #expect(dashWords)

        let opening = VerseWords(samples[4]).tokens
        #expect(opening.first?.text == "\u{2014} The", "A dash before the first word joins it")

        let token = VerseToken(text: "\u{201C}heart;", trailing: " ")
        #expect(token.core == "heart")
        #expect(token.leadingPunctuation == "\u{201C}")
        #expect(token.trailingPunctuation == ";")
        #expect(token.leadingPunctuation + token.core + token.trailingPunctuation == token.text)
    }

    // MARK: Word Order

    @Test("Solving Word Order rebuilds the exact verse", arguments: memoriseSamples)
    func wordOrderSolvesToTheVerse(_ verse: String) {
        var game = WordOrderGame(text: verse, seed: 7)
        #expect(game.shuffled.sorted() == Array(game.words.tokens.indices), "Every word appears once as a chip")
        while !game.isSolved {
            let expected = game.words.tokens[game.placed.count].text
            let chip = game.shuffled.first { !game.isPlaced($0) && game.words.tokens[$0].text == expected }!
            // Mutating calls stay outside #expect (its expansion can't mutate).
            let placed = game.tap(chip)
            #expect(placed)
        }
        #expect(game.builtText == verse)
        #expect(game.mistakes == 0)
        #expect(game.grade == .good)
    }

    @Test func wrongChipsDontAdvance() {
        var game = WordOrderGame(text: samples[0], seed: 3)
        let wrong = game.words.tokens.indices.first { game.words.tokens[$0].text != game.words.tokens[0].text }!
        let placedWrong = game.tap(wrong)
        #expect(!placedWrong)
        #expect(game.placed.isEmpty)
        #expect(game.mistakes == 1)
        #expect(game.builtText.isEmpty)
    }

    @Test func shufflingIsDeterministicAndNeverSolved() {
        for seed in UInt64(1)...40 {
            let game = WordOrderGame(text: samples[1], seed: seed)
            #expect(game.shuffled == WordOrderGame(text: samples[1], seed: seed).shuffled)
            #expect(game.shuffled != Array(game.words.tokens.indices))
        }
        #expect(WordOrderGame(text: "Jesus wept.", seed: 1).shuffled == [1, 0])
    }

    // MARK: Fill the Gaps

    @Test func gapsNeverExceedTheWords() {
        for verse in samples {
            let tokens = VerseWords(verse).tokens
            let wordCount = tokens.filter(\.hasLetters).count
            for count in 0...30 {
                for seed in UInt64(1)...5 {
                    let gaps = MemoryGame.gaps(in: tokens, count: count, seed: seed)
                    #expect(gaps.count <= wordCount)
                    #expect(gaps.count <= count)
                    #expect(Set(gaps).count == gaps.count)
                    #expect(gaps == gaps.sorted())
                    let allWords = gaps.allSatisfy { tokens[$0].hasLetters }
                    #expect(allWords)
                }
            }
        }
    }

    @Test func moreGapsAsMasteryGrows() {
        let masteries: [MemoryMastery] = [.new, .learning, .familiar, .memorised]
        let counts = masteries.map { MemoryGame.gapCount(wordCount: 20, mastery: $0) }
        #expect(counts == counts.sorted())
        #expect(counts.first! < counts.last!)
        #expect(MemoryGame.gapCount(wordCount: 0, mastery: .new) == 0)
        #expect(MemoryGame.gapCount(wordCount: 2, mastery: .new) == 1, "Always at least one gap")
        #expect(MemoryGame.gapCount(wordCount: 2, mastery: .memorised) <= 2)
        #expect(MemoryGame.gapCount(wordCount: 400, mastery: .memorised) == MemoryGame.maximumGaps)
    }

    @Test func choicesAreRealWordsAndIncludeTheAnswer() {
        let passage = samples[0]
        let nearby = "In all thy ways acknowledge him, and he shall direct thy paths."
        let tokens = VerseWords(passage).tokens
        let extra = VerseWords(nearby).tokens
        let realWords = Set((tokens + extra).map(\.core))
        for (index, answer) in tokens.enumerated() {
            for seed in UInt64(1)...10 {
                let choices = MemoryGame.choices(for: answer, among: tokens, extra: extra, seed: seed &+ UInt64(index))
                #expect(choices.contains(answer.core))
                #expect(choices.count <= MemoryGame.choiceCount)
                // Closures stay outside #expect so its expansion stays simple.
                let onlyRealWords = choices.allSatisfy { realWords.contains($0) }
                let fromTheVerses = choices.allSatisfy { passage.contains($0) || nearby.contains($0) }
                let rightAnswers = choices.filter { MemoryGame.matches($0, answer) }.count
                #expect(onlyRealWords, "Only the verses' own words")
                #expect(fromTheVerses)
                #expect(rightAnswers == 1, "Exactly one right answer")
                let keys = Set(choices.map(MemoryGame.key))
                #expect(keys.count == choices.count)
            }
        }
        // A two-word verse with nothing nearby still works.
        let short = VerseWords("Jesus wept.").tokens
        #expect(Set(MemoryGame.choices(for: short[0], among: short, seed: 1)) == ["Jesus", "wept"])
    }

    @Test func fillingTheGapsCountsMistakes() throws {
        var game = FillGapsGame(text: samples[1], mastery: .learning, seed: 11)
        #expect(!game.gaps.isEmpty)
        #expect(game.choiceSets.count == game.gaps.count)
        let firstGap = try #require(game.currentGap)
        #expect(game.isHidden(firstGap))
        let wrong = game.currentChoices.first { !MemoryGame.matches($0, game.words.tokens[firstGap]) }!
        let choseWrong = game.choose(wrong)
        #expect(!choseWrong)
        #expect(game.currentGap == firstGap, "A wrong word leaves the gap open")
        while let gap = game.currentGap {
            let chose = game.choose(game.words.tokens[gap].core)
            #expect(chose)
            #expect(game.wasFilled(gap))
        }
        #expect(game.isSolved)
        #expect(game.mistakes == 1)
        #expect(game.words.text == samples[1])
    }

    @Test func gameResultsMapToReviewGrades() {
        #expect(MemoryGame.grade(mistakes: 0, steps: 10) == .good)
        #expect(MemoryGame.grade(mistakes: 1, steps: 10) == .hard)
        #expect(MemoryGame.grade(mistakes: 1, steps: 2) == .hard)
        #expect(MemoryGame.grade(mistakes: 5, steps: 10) == .again)
        #expect(MemoryGame.speedGrade(knewIt: true) == .good)
        #expect(MemoryGame.speedGrade(knewIt: false) == .again)
    }

    @Test func gamesOnlyMoveTheScheduleWhenDue() throws {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = StudyStore(context: container.mainContext)
        let verse = store.memorise(from: VerseID(book: 43, chapter: 3, verse: 16), through: VerseID(book: 43, chapter: 3, verse: 16), translationID: "KJV")
        let movedFirst = store.recordGame(verse, .good)
        #expect(movedFirst, "A new verse is due")
        #expect(verse.reviewCount == 1)
        let due = verse.dueAt
        let movedAgain = store.recordGame(verse, .good)
        #expect(!movedAgain, "Extra practice leaves the schedule alone")
        #expect(verse.reviewCount == 1)
        #expect(verse.dueAt == due)
    }

    // MARK: Progress

    @Test func levelsFollowPassagesMemorised() {
        #expect(MemoryLevel.level(memorised: 0) == .seed)
        #expect(MemoryLevel.level(memorised: 1) == .sprout)
        #expect(MemoryLevel.level(memorised: 4) == .sprout)
        #expect(MemoryLevel.level(memorised: 5) == .sapling)
        #expect(MemoryLevel.level(memorised: 12) == .tree)
        #expect(MemoryLevel.level(memorised: 25) == .cedar)
        #expect(MemoryLevel.level(memorised: 400) == .cedar)
        #expect(MemoryLevel.allCases.map(\.threshold) == MemoryLevel.allCases.map(\.threshold).sorted())
        #expect(MemoryLevel.progress(memorised: 0) == 0)
        #expect(MemoryLevel.progress(memorised: 3) == 0.5, "Halfway from Sprout (1) to Sapling (5)")
        #expect(MemoryLevel.progress(memorised: 30) == 1)
        #expect(MemoryLevel.cedar.next == nil)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func day(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func streakContinuesAndBreaks() {
        var streak = PracticeStreak()
        #expect(streak.current(on: day(1), calendar: calendar) == 0)

        streak = streak.recording(on: day(1), calendar: calendar)
        #expect(streak.current(on: day(1), calendar: calendar) == 1)
        streak = streak.recording(on: day(1, hour: 22), calendar: calendar)
        #expect(streak.count == 1, "Twice in a day is still one day")
        #expect(streak.hasPractised(on: day(1, hour: 23), calendar: calendar))

        // 1 November 2026 is the end of daylight saving time in New York.
        streak = streak.recording(on: day(2, hour: 7), calendar: calendar)
        #expect(streak.count == 2)
        #expect(streak.current(on: day(3, hour: 23), calendar: calendar) == 2, "Still alive the next day")
        #expect(!streak.hasPractised(on: day(3), calendar: calendar))
        #expect(streak.current(on: day(4), calendar: calendar) == 0, "A missed day ends it")

        streak = streak.recording(on: day(4), calendar: calendar)
        #expect(streak.count == 1)
        #expect(streak.longest == 2)
    }

    @Test func streakIsStoredAsText() {
        let streak = PracticeStreak().recording(on: day(5), calendar: calendar).recording(on: day(6), calendar: calendar)
        #expect(PracticeStreak(rawValue: streak.rawValue) == streak)
        #expect(PracticeStreak(rawValue: PracticeStreak().rawValue) == PracticeStreak())
        #expect(PracticeStreak(rawValue: "nonsense") == nil)
    }
}
