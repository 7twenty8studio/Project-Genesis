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

    @Test func commentaryReadsInSpanishAndPortuguese() throws {
        let url = try #require(Bundle.main.url(forResource: "WordStudy", withExtension: "sqlite"))
        let english = try WordStudyRepository(url: url)
        let spanish = try WordStudyRepository(url: url, language: "es")
        let portuguese = try WordStudyRepository(url: url, language: "pt")
        #expect(english.commentaryLanguage == nil)
        #expect(spanish.commentaryLanguage == "es")
        #expect(try WordStudyRepository(url: url, language: "fr").commentaryLanguage == nil)

        let light = VerseID(book: 1, chapter: 1, verse: 3)
        let henry = try #require(try english.commentary(for: light).first)
        #expect(henry.title == "The creation of light.")
        #expect(!henry.isTranslated)
        #expect(henry.quotations.isEmpty)
        let luz = try #require(try spanish.commentary(for: light).first)
        #expect(luz.id == henry.id)
        #expect(luz.start == henry.start && luz.end == henry.end)
        #expect(luz.isTranslated)
        #expect(luz.title != henry.title)
        // The RV1909's own words, quoted verbatim, in italics.
        #expect(luz.quotations.contains("dijo Dios: Sea la luz"))
        #expect(luz.quotationLanguage == "es")
        let quoted = try #require(luz.paragraphs.first { $0.contains("dijo Dios: Sea la luz") })
        let marked = luz.attributed(quoted)
        let range = try #require(marked.range(of: "dijo Dios: Sea la luz"))
        #expect(marked[range].inlinePresentationIntent == .emphasized)
        let haja = try #require(try portuguese.commentary(for: light).first)
        #expect(haja.quotations.contains("disse Deus: Haja luz"))
        #expect(WordStudyRepository.quotationCredit(language: "pt")?.contains("Bíblia Livre") == true)
        #expect(WordStudyRepository.quotationCredit(language: "en") == nil)

        // Henry's introductions too, labelled as translated.
        let john = try #require(try spanish.bookIntroduction(43))
        #expect(john.isTranslated)
        #expect(john.text.hasPrefix("El apóstol y evangelista Juan"))
        #expect(try english.bookIntroduction(43)?.isTranslated == false)
        #expect(try portuguese.introduction(toBook: 43)?.hasPrefix("O apóstolo e evangelista João") == true)

        // Every section in both languages.
        let genesisOne = try spanish.commentary(inChapter: ChapterID(book: 1, chapter: 1))
        #expect(genesisOne.count == 8)
        #expect(genesisOne.allSatisfy(\.isTranslated))
    }

    @Test func commentaryShipsWithoutEditorialNotes() throws {
        // The owner paused passage-specific notes (19 November 2026): the
        // proposals wait in Tools/StudyData/translations/commentary.
        let url = try #require(Bundle.main.url(forResource: "WordStudy", withExtension: "sqlite"))
        for language in [nil, "es", "pt"] {
            let study = try WordStudyRepository(url: url, language: language)
            let noah = try study.commentary(inChapter: ChapterID(book: 1, chapter: 9))
            #expect(!noah.isEmpty)
            #expect(noah.allSatisfy { $0.editorialNotes.isEmpty })
        }
    }

    @Test func commentarySourceFixesShip() throws {
        // Lines the SWORD module lost or printed twice, restored from an
        // independent copy (Tools/StudyData/translations/commentary/source_fixes.json).
        let url = try #require(Bundle.main.url(forResource: "WordStudy", withExtension: "sqlite"))
        let psalmFour = VerseID(book: 19, chapter: 4, verse: 4)
        let english = try #require(try WordStudyRepository(url: url).commentary(for: psalmFour).first)
        #expect(english.text.contains("All confidence must be placed on God's free grace"))
        #expect(!english.text.contains("pan answer"))
        let spanish = try #require(try WordStudyRepository(url: url, language: "es").commentary(for: psalmFour).first)
        #expect(spanish.text.contains("libre gracia de Dios"))
        let portuguese = try #require(try WordStudyRepository(url: url, language: "pt").commentary(for: psalmFour).first)
        #expect(portuguese.text.contains("livre graça de Deus"))
    }

    @MainActor @Test func commentaryAboutSheetNamesTheEdition() {
        let about = CommentaryAboutSheet.sentences.joined(separator: " ")
        #expect(about.contains("Concise Commentary on the Whole Bible"))
        #expect(about.contains("abridgment"))
        #expect(!about.contains("as he wrote it"))
    }

    /// Mistakes found when every Spanish and Portuguese entry was read
    /// against the English (translations/lexicon/ai-review/fixes.jsonl).
    @Test func lexiconTranslationReviewFixes() throws {
        let url = try #require(Bundle.main.url(forResource: "WordStudy", withExtension: "sqlite"))
        let spanish = try WordStudyRepository(url: url, language: "es")
        let portuguese = try WordStudyRepository(url: url, language: "pt")
        // "thou" is singular, "ye" plural.
        #expect(try spanish.entry(strongs: "H0607")?.gloss == "tú")
        #expect(try portuguese.entry(strongs: "H0608")?.gloss == "vós")
        // "late fig", not an early one.
        #expect(try portuguese.entry(strongs: "G3653")?.gloss == "figo tardio")
        // STEPBible's garbled "of person(s) pron." is the personal pronoun.
        let yo = try #require(try spanish.entry(strongs: "G1473"))
        #expect(yo.definition.contains("pron. personal\nyo."))
        let eu = try #require(try portuguese.entry(strongs: "G1473"))
        #expect(eu.definition.contains("pron. pessoal\neu."))
        #expect(!eu.definition.contains("pessoa(s)"))
    }

    @Test func lexiconQueriesAnswered() throws {
        // The AI review's open queries settled where the English is clear
        // (translations/lexicon/ai-review/queries.jsonl).
        let url = try #require(Bundle.main.url(forResource: "WordStudy", withExtension: "sqlite"))
        let english = try WordStudyRepository(url: url)
        let spanish = try WordStudyRepository(url: url, language: "es")
        let portuguese = try WordStudyRepository(url: url, language: "pt")
        // Strong's "a plural of 929", not "or".
        #expect(try english.entry(strongs: "H0930")?.derivation.contains("a plural of 929") == true)
        #expect(try spanish.entry(strongs: "H0930")?.derivation.contains("un plural de 929") == true)
        // Purah is "Phara" in the RV1909 (Judges 7:10), modernized.
        #expect(try spanish.entry(strongs: "H6513")?.gloss == "Fara")
        // STEPBible's "bridegroom" for νυμφών, the bride-chamber.
        #expect(try portuguese.entry(strongs: "G3567")?.gloss == "câmara nupcial")
        #expect(try portuguese.entry(strongs: "H8279")?.gloss == "estilete")
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
