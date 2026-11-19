import Foundation
import Testing
@testable import Genesis

/// The bundled Glosses.sqlite: the Original view's glosses in Spanish and
/// Portuguese (Tools/StudyData/glosses.py).
@Suite("Original glosses")
struct OriginalGlossesTests {
    @Test func keyMatchesTheBuildScript() {
        // Tools/StudyData/test_glosses.py expects the same numbers.
        #expect(OriginalGlosses.key(strongs: "H0430G", morphology: "HNcmpa", gloss: "God") == 4_483_138_548_866_997_674)
        #expect(OriginalGlosses.key(strongs: "", morphology: "", gloss: "") == 610_775_443_798_759_267)
    }

    @Test func genesisOneOneReadsInSpanishAndPortuguese() throws {
        let wordStudy = try #require(Bundle.main.url(forResource: "WordStudy", withExtension: "sqlite"))
        let url = try #require(Bundle.main.url(forResource: "Glosses", withExtension: "sqlite"))
        let glosses = try OriginalGlosses(url: url)
        let english = try WordStudyRepository(url: wordStudy).words(in: VerseID(book: 1, chapter: 1, verse: 1))
        #expect(english.allSatisfy { $0.englishGloss == nil })

        let spanish = try glosses.translated(english, into: "es")
        #expect(spanish.count == english.count)
        #expect(spanish.allSatisfy { $0.englishGloss != nil })
        // The Hebrew, its number and grammar stay as they are.
        #expect(spanish.map(\.text) == english.map(\.text))
        #expect(spanish.map(\.strongs) == english.map(\.strongs))
        #expect(spanish.map(\.englishGloss) == english.map(\.gloss))
        #expect(spanish.first { $0.strongs == "H0430G" }?.gloss == "Dios")
        #expect(try glosses.translated(english, into: "pt").first { $0.strongs == "H0430G" }?.gloss == "Deus")

        // English, and any other language, keeps STEPBible's glosses.
        #expect(try glosses.translated(english, into: "fr") == english)
        #expect(try glosses.translated(english, into: "en") == english)
    }

    @Test func johnOneOneReadsInSpanish() throws {
        let wordStudy = try #require(Bundle.main.url(forResource: "WordStudy", withExtension: "sqlite"))
        let url = try #require(Bundle.main.url(forResource: "Glosses", withExtension: "sqlite"))
        let words = try WordStudyRepository(url: wordStudy).words(in: VerseID(book: 43, chapter: 1, verse: 1))
        let spanish = try OriginalGlosses(url: url).translated(words, into: "es")
        #expect(spanish.contains { $0.strongs == "G2316" && $0.gloss.contains("Dios") })
        #expect(spanish.filter { $0.englishGloss != nil }.count == words.count)
    }
}

/// The word meanings' language is the reader's, apart from the app's:
/// by default it follows the Bible being read (GlossLanguage).
@Suite("Gloss language")
struct GlossLanguageTests {
    /// The Reina-Valera 1909's language (its catalog row; it's downloaded).
    static let reinaValera = "es"

    @Test func followsTheBibleNotTheApp() {
        // An English app reading the Reina-Valera gets Spanish meanings…
        #expect(GlossLanguage.code(for: .bible, bibleLanguage: Self.reinaValera) == "es")
        // …and a Spanish app reading the Bíblia Livre gets Portuguese ones.
        #expect(GlossLanguage.code(for: .bible, bibleLanguage: Translation.bibliaLivre.language) == "pt")
        // O Livro (pt-PT) has the Portuguese; the KJV and others keep English.
        #expect(GlossLanguage.code(for: .bible, bibleLanguage: "pt-PT") == "pt")
        #expect(GlossLanguage.code(for: .bible, bibleLanguage: "en") == "en")
        #expect(GlossLanguage.code(for: .bible, bibleLanguage: "fr") == "en")
    }

    @Test func aChosenLanguageWins() {
        #expect(GlossLanguage.code(for: .english, bibleLanguage: "es") == "en")
        #expect(GlossLanguage.code(for: .spanish, bibleLanguage: "en") == "es")
        #expect(GlossLanguage.code(for: .portuguese, bibleLanguage: "es") == "pt")
        #expect(GlossLanguageChoice(rawValue: "bible") == .bible)
    }

    @Test func theSavedChoiceStartsAtTheBible() throws {
        let defaults = try #require(UserDefaults(suiteName: "GlossLanguageTests"))
        defaults.removePersistentDomain(forName: "GlossLanguageTests")
        #expect(GlossLanguage.savedChoice(in: defaults) == .bible)
        defaults.set("pt", forKey: GlossLanguage.storageKey)
        #expect(GlossLanguage.savedChoice(in: defaults) == .portuguese)
        defaults.removePersistentDomain(forName: "GlossLanguageTests")
    }

    /// The repository gives the meanings in the language asked for, whatever
    /// language it (and the app) was opened in.
    @Test func wordsComeInTheGlossLanguage() throws {
        let url = try #require(Bundle.main.url(forResource: "WordStudy", withExtension: "sqlite"))
        let genesis = VerseID(book: 1, chapter: 1, verse: 1)
        // A repository opened in English (an English app) reading the RV1909.
        let english = try WordStudyRepository(url: url, language: "en")
        let rv1909 = GlossLanguage.code(for: .bible, bibleLanguage: Self.reinaValera)
        #expect(try english.words(in: genesis, glossLanguage: rv1909).first { $0.strongs == "H0430G" }?.gloss == "Dios")
        // One opened in Spanish (a Spanish app) reading the Bíblia Livre.
        let spanish = try WordStudyRepository(url: url, language: "es")
        let blivre = GlossLanguage.code(for: .bible, bibleLanguage: Translation.bibliaLivre.language)
        #expect(try spanish.words(in: genesis, glossLanguage: blivre).first { $0.strongs == "H0430G" }?.gloss == "Deus")
        // A Spanish app reading the KJV keeps STEPBible's English.
        let kjv = GlossLanguage.code(for: .bible, bibleLanguage: Translation.kjv.language)
        #expect(try spanish.words(in: genesis, glossLanguage: kjv).allSatisfy { $0.englishGloss == nil })
    }
}
