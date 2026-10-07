import Foundation
import Testing
@testable import Genesis

/// Matching picked English words to the Hebrew or Greek behind them.
@Suite("Original word matching")
struct OriginalWordMatcherTests {
    // MARK: Fixtures

    private static let verse = VerseID(book: 43, chapter: 3, verse: 16)

    private func word(_ position: Int, _ gloss: String, _ strongs: String?, morphology: String = "N-NSM", verse: VerseID = OriginalWordMatcherTests.verse) -> OriginalWord {
        OriginalWord(verse: verse, position: position, text: "λόγος", transliteration: "logos", strongs: strongs, gloss: gloss, morphology: morphology)
    }

    private func entry(_ strongs: String, gloss: String, usage: String = "", definition: String = "", language: OriginalLanguage = .greek) -> LexiconEntry {
        LexiconEntry(strongs: strongs, lemma: "λόγος", transliteration: "logos", gloss: gloss, definition: definition, derivation: "", usage: usage, language: language)
    }

    private func numbers(_ matches: [OriginalWordMatch]) -> [String] {
        matches.compactMap(\.word.strongs)
    }

    private var johnThreeSixteen: [OriginalWord] {
        [
            word(1, "Thus", "G3779", morphology: "ADV"),
            word(2, "for", "G1063", morphology: "CONJ"),
            word(3, "loved", "G0025", morphology: "V-AAI-3S"),
            word(4, "<the>", "G3588", morphology: "T-NSM"),
            word(5, "God", "G2316", morphology: "N-NSM-T"),
            word(6, "the", "G3588", morphology: "T-ASM"),
            word(7, "world", "G2889", morphology: "N-ASM"),
            word(9, "the", "G3588", morphology: "T-ASM"),
            word(10, "Son", "G5207", morphology: "N-ASM"),
            word(13, "only begotten", "G3439", morphology: "A-ASM"),
        ]
    }

    // MARK: Normalising

    @Test func kjvVerbFormsShareAStem() {
        let love = OriginalWordMatcher.stem("love")
        #expect(love == "lov")
        #expect(OriginalWordMatcher.stem("loved") == love)
        #expect(OriginalWordMatcher.stem("loveth") == love)
        #expect(OriginalWordMatcher.stem("lovedst") == love)
        #expect(OriginalWordMatcher.stem("lovest") == love)
        #expect(OriginalWordMatcher.stem("loving") == love)
        #expect(OriginalWordMatcher.stem("loves") == love)
    }

    @Test func stemsStayConsistentForOtherShapes() {
        #expect(OriginalWordMatcher.stem("beginning") == OriginalWordMatcher.stem("begin"))
        #expect(OriginalWordMatcher.stem("cities") == OriginalWordMatcher.stem("city"))
        #expect(OriginalWordMatcher.stem("families") == OriginalWordMatcher.stem("family"))
        #expect(OriginalWordMatcher.stem("gave") == OriginalWordMatcher.stem("give"))
        #expect(OriginalWordMatcher.stem("begotten") == OriginalWordMatcher.stem("beget"))
        #expect(OriginalWordMatcher.stem("kingdoms") == "kingdom")
        #expect(OriginalWordMatcher.stem("spirit") == "spirit")
        #expect(OriginalWordMatcher.stem("glass") == "glass")
    }

    @Test func termsAreFoldedAndNormalised() {
        #expect(OriginalWordMatcher.terms(in: "God’s") == ["god"])
        #expect(OriginalWordMatcher.terms(in: "didn't") == ["did", "not"])
        #expect(OriginalWordMatcher.terms(in: "His") == ["he"])
        #expect(OriginalWordMatcher.terms(in: "Jehovah") == ["yahweh"])
        #expect(OriginalWordMatcher.terms(in: "everlasting") == ["eternal"])
        #expect(OriginalWordMatcher.terms(in: "“Thus,” saith") == ["thus", "saith"])
        #expect(OriginalWordMatcher.terms(in: "Élohim") == ["elohim"])
    }

    @Test func glossesDropSuppliedAndUntranslatedWords() {
        #expect(OriginalWordMatcher.glossTerms("[is] shepherd my") == ["shepherd", "i"])
        #expect(OriginalWordMatcher.glossTerms("<obj.>").isEmpty)
        #expect(OriginalWordMatcher.glossTerms("Yahweh") == ["yahweh", "lord"])
        #expect(OriginalWordMatcher.isFunctionWord("unto"))
        #expect(!OriginalWordMatcher.isFunctionWord("world"))
    }

    @Test func strongsShorthandIsSpelledOut() {
        #expect(OriginalWordMatcher.expandingStrongsSuffixes("bull(-ock), cow") == "bull bullock, cow")
        #expect(OriginalWordMatcher.expandingStrongsSuffixes("who(-m, -se)") == "who whom whose")
        #expect(OriginalWordMatcher.expandingStrongsSuffixes("(young) calf") == "(young) calf")
    }

    // MARK: Matching (fixtures)

    @Test func aWordMatchesItsGloss() throws {
        let matches = OriginalWordMatcher.matches(for: "loved", in: johnThreeSixteen, lexicon: [:])
        let first = try #require(matches.first)
        #expect(first.word.strongs == "G0025")
        #expect(first.isLikely)
        #expect(matches.count == 1)
    }

    @Test func functionWordsAreIgnoredBesideOthers() {
        let matches = OriginalWordMatcher.matches(for: "the world", in: johnThreeSixteen, lexicon: [:])
        #expect(numbers(matches) == ["G2889"])
    }

    @Test func functionWordsAloneStillMatchOncePerNumber() throws {
        let matches = OriginalWordMatcher.matches(for: "the", in: johnThreeSixteen, lexicon: [:])
        #expect(matches.count == 1)
        let first = try #require(matches.first)
        #expect(first.word.position == 6)
    }

    @Test func phrasesRankByOverlap() {
        let matches = OriginalWordMatcher.matches(for: "only begotten Son", in: johnThreeSixteen, lexicon: [:])
        #expect(numbers(matches) == ["G3439", "G5207"])
    }

    @Test func atMostThreeMatchesInWordOrderOnTies() {
        let matches = OriginalWordMatcher.matches(for: "Thus loved God world", in: johnThreeSixteen, lexicon: [:])
        #expect(numbers(matches) == ["G3779", "G0025", "G2316"])
    }

    @Test func nothingMatchesGibberishOrPunctuation() {
        let gibberish = OriginalWordMatcher.matches(for: "xyzzy", in: johnThreeSixteen, lexicon: [:])
        let punctuation = OriginalWordMatcher.matches(for: " ,.; ", in: johnThreeSixteen, lexicon: [:])
        let noWords = OriginalWordMatcher.matches(for: "loved", in: [], lexicon: [:])
        #expect(gibberish.isEmpty)
        #expect(punctuation.isEmpty)
        #expect(noWords.isEmpty)
    }

    @Test func lexiconFallbackIsOnlyTheClosestMatch() throws {
        let psalm = VerseID(book: 19, chapter: 23, verse: 1)
        let words = [
            word(5, "not", "H3808", morphology: "HTn", verse: psalm),
            word(6, "I lack", "H2637", morphology: "HVqi1cs", verse: psalm),
        ]
        let lexicon = [
            "H3808": entry("H3808", gloss: "not", usage: "nay, neither, never, no, nothing, for want, without", language: .hebrew),
            "H2637": entry("H2637", gloss: "to lack", usage: "(have) lack, make lower, want.", language: .hebrew),
        ]
        let matches = OriginalWordMatcher.matches(for: "want", in: words, lexicon: lexicon)
        let first = try #require(matches.first)
        #expect(first.word.strongs == "H2637")
        #expect(!first.isLikely)
        #expect(numbers(matches) == ["H2637", "H3808"])
    }

    @Test func aGlossMatchSilencesTheLexiconForThatWord() {
        let words = [
            word(9, "and he blew", "H5301", morphology: "Hc/Vqw3ms"),
            word(11, "[the] breath of", "H5397", morphology: "HNcfsc"),
        ]
        let lexicon = ["H5301": entry("H5301", gloss: "to breathe", usage: "blow, breath, give up", language: .hebrew)]
        let matches = OriginalWordMatcher.matches(for: "breath", in: words, lexicon: lexicon)
        #expect(numbers(matches) == ["H5397"])
    }

    // MARK: Verse words and parts of speech

    @Test func verseWordsKeepApostrophesAndHyphens() {
        let text = "“Don’t fear,” said the LORD—self-control rest."
        let words = VerseWords.ranges(in: text).map { String(text[$0]) }
        #expect(words == ["Don’t", "fear", "said", "the", "LORD", "self-control", "rest"])
    }

    @Test func thePressedCopyOfAWordIsPicked() {
        let text = "The man and the woman"
        let ranges = VerseWords.ranges(in: text)
        let verse = VerseID(book: 1, chapter: 2, verse: 25)
        let second = VerseWords.index(of: PressedWord(verse: verse, text: "the", occurrence: 1), in: text, ranges: ranges)
        let first = VerseWords.index(of: PressedWord(verse: verse, text: "THE", occurrence: 0), in: text, ranges: ranges)
        let beyond = VerseWords.index(of: PressedWord(verse: verse, text: "the", occurrence: 7), in: text, ranges: ranges)
        let missing = VerseWords.index(of: PressedWord(verse: verse, text: "garden", occurrence: 0), in: text, ranges: ranges)
        #expect(second == 3)
        #expect(first == 0)
        #expect(beyond == 3)
        #expect(missing == nil)
    }

    @Test func partsOfSpeechComeFromMorphology() {
        #expect(PartOfSpeech(morphology: "V-AAI-3S", language: .greek) == .verb)
        #expect(PartOfSpeech(morphology: "N-NSM-T", language: .greek) == .noun)
        #expect(PartOfSpeech(morphology: "T-ASM", language: .greek) == .article)
        #expect(PartOfSpeech(morphology: "A-ASF", language: .greek) == .adjective)
        #expect(PartOfSpeech(morphology: "CONJ", language: .greek) == .conjunction)
        #expect(PartOfSpeech(morphology: "PRT-N", language: .greek) == .particle)
        #expect(PartOfSpeech(morphology: "HVqp3ms", language: .hebrew) == .verb)
        #expect(PartOfSpeech(morphology: "HTd/Ncfsa", language: .hebrew) == .noun)
        #expect(PartOfSpeech(morphology: "HR/Ncmdc/Sp3ms", language: .hebrew) == .noun)
        #expect(PartOfSpeech(morphology: "HNpt", language: .hebrew) == .properNoun)
        #expect(PartOfSpeech(morphology: "HTo", language: .hebrew) == .particle)
        #expect(PartOfSpeech(morphology: "HR", language: .hebrew) == .preposition)
        #expect(PartOfSpeech(morphology: "Hc/Vqw3ms", language: .hebrew) == .verb)
        #expect(PartOfSpeech(morphology: "", language: .hebrew) == nil)
    }
}

/// The matcher on the bundled WordStudy.sqlite, with words as the KJV, ASV
/// and WEB print them.
@Suite("Original word matching (bundled data)")
struct OriginalWordMatcherDataTests {
    private func matches(_ selection: String, in verse: VerseID) throws -> [OriginalWordMatch] {
        let url = try #require(Bundle.main.url(forResource: "WordStudy", withExtension: "sqlite"))
        let study = try WordStudyRepository(url: url)
        let words = try study.words(in: verse)
        var lexicon: [String: LexiconEntry] = [:]
        for strongs in Set(words.compactMap(\.strongs)) {
            lexicon[strongs] = try study.entry(strongs: strongs)
        }
        return OriginalWordMatcher.matches(for: selection, in: words, lexicon: lexicon)
    }

    private func best(_ selection: String, in verse: VerseID) throws -> OriginalWordMatch {
        let found = try matches(selection, in: verse)
        return try #require(found.first)
    }

    private let john316 = VerseID(book: 43, chapter: 3, verse: 16)
    private let genesis11 = VerseID(book: 1, chapter: 1, verse: 1)
    private let psalm231 = VerseID(book: 19, chapter: 23, verse: 1)

    @Test func johnThreeSixteen() throws {
        let loved = try best("loved", in: john316)
        #expect(loved.word.strongs == "G0025") // agapaō
        #expect(loved.word.transliteration == "ēgapēsen")
        #expect(loved.isLikely)
        let world = try best("world", in: john316)
        #expect(world.word.strongs == "G2889") // kosmos
        let everlasting = try best("everlasting", in: john316) // "eternal" in the gloss
        #expect(everlasting.word.strongs == "G0166")
        let whosoever = try best("whosoever", in: john316)
        #expect(whosoever.word.strongs == "G3956")
        let believeth = try best("believeth", in: john316) // "is believing"
        #expect(believeth.word.strongs == "G4100")
        let phrase = try matches("only begotten Son", in: john316)
        let numbers = phrase.compactMap(\.word.strongs)
        #expect(numbers == ["G3439", "G5207"])
    }

    @Test func genesisOneOne() throws {
        let god = try best("God", in: genesis11)
        #expect(god.word.strongs == "H0430G") // Elohim
        #expect(god.word.language == .hebrew)
        let beginning = try best("beginning", in: genesis11)
        #expect(beginning.word.strongs == "H7225G") // reshit
        let phrase = try best("In the beginning", in: genesis11)
        #expect(phrase.word.strongs == "H7225G")
        let created = try best("created", in: genesis11)
        #expect(created.word.strongs == "H1254A") // bara
        let heaven = try best("heaven", in: genesis11) // "the heavens"
        #expect(heaven.word.strongs == "H8064")
    }

    @Test func theDivineNameInEachEnglishBible() throws {
        let kjv = try best("Lord", in: psalm231)
        let asv = try best("Jehovah", in: psalm231)
        let web = try best("Yahweh", in: psalm231)
        #expect(kjv.word.strongs == "H3068G")
        #expect(asv.word.strongs == "H3068G")
        #expect(web.word.strongs == "H3068G")
        let shepherd = try best("shepherd", in: psalm231)
        #expect(shepherd.word.strongs == "H7462B")
        #expect(shepherd.isLikely)
    }

    @Test func kjvWantFindsLackThroughStrongs() throws {
        let want = try best("want", in: psalm231)
        #expect(want.word.strongs == "H2637") // "I lack"; the KJV's "want" is in Strong's renderings
        #expect(!want.isLikely)
        let lack = try best("lack", in: psalm231) // the WEB's word
        #expect(lack.word.strongs == "H2637")
        #expect(lack.isLikely)
    }

    @Test func olderVerbEndings() throws {
        let loveth = try best("loveth", in: VerseID(book: 43, chapter: 3, verse: 35))
        #expect(loveth.word.strongs == "G0025")
        let lovedst = try best("lovedst", in: VerseID(book: 43, chapter: 17, verse: 24))
        #expect(lovedst.word.strongs == "G0025")
        // "Lovest thou me?" and Peter's answer use two different verbs.
        let lovest = try matches("lovest", in: VerseID(book: 43, chapter: 21, verse: 15))
        let numbers = lovest.compactMap(\.word.strongs)
        #expect(numbers.contains("G0025"))
        #expect(numbers.contains("G5368"))
    }

    @Test func phrasesAcrossWords() throws {
        let breath = try matches("breath of life", in: VerseID(book: 1, chapter: 2, verse: 7))
        let breathNumbers = breath.compactMap(\.word.strongs)
        #expect(breathNumbers == ["H5397", "H2416E"])
        let poor = try matches("poor in spirit", in: VerseID(book: 40, chapter: 5, verse: 3))
        let poorNumbers = poor.compactMap(\.word.strongs)
        #expect(poorNumbers == ["G4434", "G4151G"])
        let nostrils = try best("his nostrils", in: VerseID(book: 1, chapter: 2, verse: 7))
        #expect(nostrils.word.strongs == "H0639H")
    }

    @Test func commendethIsAClosestMatch() throws {
        let commendeth = try best("commendeth", in: VerseID(book: 45, chapter: 5, verse: 8))
        #expect(commendeth.word.strongs == "G4921") // "Demonstrates"
        #expect(!commendeth.isLikely)
    }

    @Test func noMatchIsEmpty() throws {
        let none = try matches("xyzzy", in: john316)
        #expect(none.isEmpty)
    }
}
