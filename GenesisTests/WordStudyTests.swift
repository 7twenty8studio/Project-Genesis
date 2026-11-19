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

    @Test func lexiconReadsInSpanishAndPortuguese() throws {
        let url = try #require(Bundle.main.url(forResource: "WordStudy", withExtension: "sqlite"))
        let english = try WordStudyRepository(url: url)
        let spanish = try WordStudyRepository(url: url, language: "es")
        let portuguese = try WordStudyRepository(url: url, language: "pt")
        #expect(english.language == nil)
        #expect(spanish.language == "es")
        #expect(try WordStudyRepository(url: url, language: "fr").language == nil)

        let create = try #require(try english.entry(strongs: "H1254A"))
        #expect(create.gloss == "to create")
        #expect(!create.isTranslated)
        let crear = try #require(try spanish.entry(strongs: "H1254A"))
        #expect(crear.gloss == "crear")
        #expect(crear.derivation == "raíz primitiva;")
        #expect(crear.isTranslated)
        // The Hebrew, the number and the KJV's renderings stay as they are.
        #expect(crear.lemma == create.lemma)
        #expect(crear.strongs == create.strongs)
        #expect(crear.usage == create.usage)
        #expect(try portuguese.entry(strongs: "H1254A")?.gloss == "criar")
        // A number with no entry of its own still falls back, translated.
        #expect(try spanish.entry(strongs: "H1254Z")?.isTranslated == true)

        let theos = try #require(try spanish.entry(strongs: "G2316"))
        #expect(theos.gloss == "Dios")
        #expect(theos.definition.hasPrefix("θεός, -οῦ, ὁ, ἡ"))
        #expect(try portuguese.entry(strongs: "G2316")?.gloss == "Deus")
    }

    @Test func entriesHoldOnlyTheirOwnArticle() throws {
        let url = try #require(Bundle.main.url(forResource: "WordStudy", withExtension: "sqlite"))
        for language in [nil, "es", "pt"] {
            let study = try WordStudyRepository(url: url, language: language)
            // STEPBible had appended the article on βασιλεία to οὐρανός's.
            let heaven = try #require(try study.entry(strongs: "G3772"))
            #expect(heaven.definition.hasPrefix("οὐρανός, -οῦ, ὁ,"))
            #expect(!heaven.definition.contains("βασιλεία, -ας, ἡ"))
            #expect(!heaven.definition.hasSuffix("\\"))
            // Forms of σύ carried αὐτός's article; now σύ's.
            let you = try #require(try study.entry(strongs: "G4571"))
            #expect(you.definition == (try study.entry(strongs: "G4771"))?.definition)
            #expect(!you.definition.contains("αὐτός, -ή, -ό"))
            // μόδιος held μοιχαλίς's article: only its gloss is left.
            #expect(try study.entry(strongs: "G3426")?.definition.isEmpty == true)
        }
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
