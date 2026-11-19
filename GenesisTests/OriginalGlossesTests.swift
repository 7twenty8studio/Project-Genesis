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
