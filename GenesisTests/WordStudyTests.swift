import Foundation
import Testing
@testable import Genesis

/// The bundled WordStudy.sqlite: original-language words, lexicon and commentary.
@Suite("Word study data")
struct WordStudyTests {
    private func repository() throws -> WordStudyRepository {
        let url = try #require(Bundle.main.url(forResource: "WordStudy", withExtension: "sqlite"))
        return try WordStudyRepository(url: url)
    }

    @Test func genesisOneOneHasElohim() throws {
        let study = try repository()
        let words = try study.words(in: VerseID(book: 1, chapter: 1, verse: 1))
        #expect(words.count == 7)
        #expect(words.map(\.position) == Array(1...7))
        let god = try #require(words.first { $0.strongs?.hasPrefix("H0430") == true })
        #expect(god.position == 3)
        #expect(god.text == "אֱלֹהִ֑ים")
        #expect(god.gloss == "God")
        #expect(god.language == .hebrew)

        let entry = try #require(try study.entry(strongs: "H430"))
        #expect(entry.strongs.hasPrefix("H0430"))
        #expect(entry.lemma == "אֱלֹהִים")
        #expect(entry.definition.contains("God"))
        #expect(entry.language == .hebrew)
        #expect(try study.occurrences(of: "H430") > 2000)
    }

    @Test func johnThreeSixteenHasTheosAndCommentary() throws {
        let study = try repository()
        let verse = VerseID(book: 43, chapter: 3, verse: 16)
        let words = try study.words(in: verse)
        let theos = try #require(words.first { $0.strongs == "G2316" })
        #expect(theos.language == .greek)
        #expect(theos.transliteration == "theos")

        let entry = try #require(try study.entry(strongs: "g2316"))
        #expect(entry.lemma == "θε\u{1F79}ς") // θεός, accented as in the source
        #expect(entry.language == .greek)
        #expect(!entry.definition.isEmpty)
        #expect(try study.occurrences(of: "G2316") > 1000)
        let verses = try study.verses(using: "G2316", limit: 5000)
        #expect(verses.contains(verse))
        #expect(verses == verses.sorted())
        #expect(verses.allSatisfy { $0.book >= 40 })

        let passages = try study.commentary(for: verse)
        let passage = try #require(passages.first)
        #expect(passage.covers(verse))
        #expect(passage.source == "mhcc")
        #expect(!passage.text.isEmpty)
    }

    @Test func extendedNumbersFallBackToTheirBase() throws {
        let study = try repository()
        let create = try #require(try study.entry(strongs: "H1254A"))
        #expect(create.strongs == "H1254A")
        // No such letter: the plain number's first entry stands in.
        let fallback = try #require(try study.entry(strongs: "H1254Z"))
        #expect(fallback.strongs.hasPrefix("H1254"))
        #expect(try study.entry(strongs: "not a number") == nil)
        #expect(try study.occurrences(of: "H1254A") <= study.occurrences(of: "H1254"))
    }

    @Test func versesFollowTheKJV() throws {
        let study = try repository()
        // Psalm titles belong to verse 1, as in the KJV.
        #expect(try study.words(in: VerseID(book: 19, chapter: 3, verse: 1)).count > 6)
        #expect(try study.words(in: VerseID(book: 19, chapter: 3, verse: 0)).isEmpty)
        // 3 John has 14 verses in the KJV (15 in some modern Bibles).
        #expect(try !study.words(in: VerseID(book: 64, chapter: 1, verse: 14)).isEmpty)
        #expect(try study.words(in: VerseID(book: 64, chapter: 1, verse: 15)).isEmpty)
    }

    @Test func commentaryCoversWholeChapters() throws {
        let study = try repository()
        let genesisOne = try study.commentary(inChapter: ChapterID(book: 1, chapter: 1))
        #expect(genesisOne.count == 8)
        #expect(genesisOne.first?.start == VerseID(book: 1, chapter: 1, verse: 1))
        #expect(genesisOne.last?.end == VerseID(book: 1, chapter: 1, verse: 31))
        #expect(genesisOne.allSatisfy { $0.title != nil })
        #expect(try study.introduction(toBook: 43)?.isEmpty == false)
    }

    @Test func strongsNumbersAreNormalised() {
        #expect(StrongsNumber.normalized("H430") == "H0430")
        #expect(StrongsNumber.normalized(" h0430g ") == "H0430G")
        #expect(StrongsNumber.normalized("G2316") == "G2316")
        #expect(StrongsNumber.normalized("G10005") == "G10005")
        #expect(StrongsNumber.normalized("X12") == nil)
        #expect(StrongsNumber.normalized("H12AB") == nil)
        #expect(StrongsNumber.base(of: "H1254A") == "H1254")
        #expect(StrongsNumber.base(of: "G2316") == "G2316")
        #expect(WordStudyRepository.decodeVerses("1001001,2,998") == [1001001, 1001003, 1002001])
    }
}
