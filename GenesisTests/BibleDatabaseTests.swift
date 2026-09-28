import Foundation
import Testing
@testable import Genesis

/// Exercises the bundled databases. Runs hosted in the app, so `Bundle.main`
/// is the app bundle that ships the .sqlite files.
@Suite("Bundled Bible databases")
struct BibleDatabaseTests {
    private func repository(_ translation: Translation) throws -> BibleRepository {
        let url = try #require(Bundle.main.url(forResource: translation.id, withExtension: "sqlite"))
        return try BibleRepository(translation: translation, url: url)
    }

    @Test("Every chapter of every book is present", arguments: Translation.bundled)
    func chaptersMatchCatalog(translation: Translation) throws {
        let bible = try repository(translation)
        for book in BibleBook.all {
            let last = try bible.chapter(ChapterID(book: book.id, chapter: book.chapterCount))
            #expect(!last.verses.isEmpty, "\(translation.id) \(book.name) \(book.chapterCount) is empty")
            let beyond = try bible.chapter(ChapterID(book: book.id, chapter: book.chapterCount + 1))
            #expect(beyond.verses.isEmpty)
        }
    }

    @Test func textIsVerbatim() throws {
        let kjv = try repository(.kjv)
        let verse = try #require(try kjv.verse(VerseID(book: 43, chapter: 3, verse: 16)))
        #expect(verse.text == "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.")
        let genesis = try kjv.chapter(.genesis1)
        #expect(genesis.verses.count == 31)
    }

    @Test func webKeepsPoetryAndHeadings() throws {
        let web = try repository(.web)
        let psalm = try web.chapter(ChapterID(book: 19, chapter: 23))
        #expect(psalm.headings.first?.text == "A Psalm by David.")
        let allPoetry = psalm.verses.allSatisfy { $0.isPoetry }
        #expect(allPoetry)
        #expect(psalm.verses[0].text.contains("\n"))
    }

    @Test("Search finds text quickly", arguments: ["love", "\"in the beginning\"", "bethlehem", "forgiv"])
    func searchIsFast(term: String) throws {
        let kjv = try repository(.kjv)
        let clock = ContinuousClock()
        var results = SearchResults.empty
        let elapsed = try clock.measure {
            results = try BibleSearch.run(term, in: kjv)
        }
        #expect(!results.verses.isEmpty)
        // PRD target: under 100 ms.
        #expect(elapsed < .milliseconds(100), "\(term) took \(elapsed)")
    }

    @Test func hyphenatedNamesAreFound() throws {
        // KJV spells "Beth\u{2013}lehem"; searching the joined form must still find it.
        let kjv = try repository(.kjv)
        let results = try BibleSearch.run("bethlehem", in: kjv)
        #expect(results.totalMatches > 30)
    }

    @Test func scopeLimitsResults() throws {
        let kjv = try repository(.kjv)
        // Trailing space: a whole word, so "Jesui" and "Jesurun" do not match.
        let results = try BibleSearch.run("jesus ", in: kjv, scope: .testament(.old))
        #expect(results.verses.isEmpty)
    }

    @Test func crossReferences() throws {
        let url = try #require(Bundle.main.url(forResource: "CrossReferences", withExtension: "sqlite"))
        let references = try CrossReferenceRepository(url: url).references(from: VerseID(book: 43, chapter: 3, verse: 16))
        #expect(references.count > 5)
        let sortedByVotes = zip(references, references.dropFirst()).allSatisfy { $0.votes >= $1.votes }
        #expect(sortedByVotes)
    }
}
