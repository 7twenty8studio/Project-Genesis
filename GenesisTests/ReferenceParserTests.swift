import Foundation
import Testing
@testable import Genesis

@Suite("Reference parsing")
struct ReferenceParserTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let input: String
        let book: Int
        let chapter: Int
        let verse: Int
        var end: Int?

        var testDescription: String { input }
    }

    @Test("Common references", arguments: [
        Case(input: "John 3:16", book: 43, chapter: 3, verse: 16),
        Case(input: "jn 3:16", book: 43, chapter: 3, verse: 16),
        Case(input: "Jhn 3.16", book: 43, chapter: 3, verse: 16),
        Case(input: "1 Cor 13:4-7", book: 46, chapter: 13, verse: 4, end: 7),
        Case(input: "1cor 13:4\u{2013}7", book: 46, chapter: 13, verse: 4, end: 7),
        Case(input: "I John 1:9", book: 62, chapter: 1, verse: 9),
        Case(input: "First John 1:9", book: 62, chapter: 1, verse: 9),
        Case(input: "2 Tim 3:16", book: 55, chapter: 3, verse: 16),
        Case(input: "Rev. 21:4", book: 66, chapter: 21, verse: 4),
        Case(input: "Revelations 21:4", book: 66, chapter: 21, verse: 4),
        Case(input: "song of songs 2:4", book: 22, chapter: 2, verse: 4),
        Case(input: "Ps 119:105", book: 19, chapter: 119, verse: 105),
    ])
    func parsesVerse(_ expected: Case) throws {
        let reference = try #require(ReferenceParser.parse(expected.input))
        #expect(reference.book.id == expected.book)
        #expect(reference.chapter == expected.chapter)
        #expect(reference.verseStart == expected.verse)
        #expect(reference.verseEnd == expected.end)
    }

    @Test func parsesChapterAndBook() throws {
        let psalm = try #require(ReferenceParser.parse("Psalm 23"))
        #expect(psalm.book.id == 19)
        #expect(psalm.chapter == 23)
        #expect(psalm.verseStart == nil)

        let genesis = try #require(ReferenceParser.parse("Genesis"))
        #expect(genesis.book.id == 1)
        #expect(genesis.chapter == nil)
    }

    @Test func singleChapterBooksUseVerseNumbers() throws {
        let jude = try #require(ReferenceParser.parse("Jude 3"))
        #expect(jude.chapter == 1)
        #expect(jude.verseStart == 3)
        #expect(jude.description == "Jude 3")
    }

    @Test func crossChapterRangeKeepsStart() throws {
        let reference = try #require(ReferenceParser.parse("John 3:16-4:2"))
        #expect(reference.chapter == 3)
        #expect(reference.verseStart == 16)
        #expect(reference.verseEnd == nil)
    }

    @Test("Rejects non-references", arguments: ["love", "John 22", "Genesis 0", "grace and peace", "", "3:16", "John 3:16 foo"])
    func rejects(input: String) {
        #expect(ReferenceParser.parse(input) == nil)
    }

    @Test func bookSuggestions() {
        #expect(ReferenceParser.books(matching: "phil").map(\.id).contains(50))
        #expect(ReferenceParser.books(matching: "joh").first?.id == 43)
        #expect(ReferenceParser.books(matching: "John 3").isEmpty)
    }

    @Test func descriptions() {
        #expect(PassageReference(book: .withNumber(43), chapter: 3, verseStart: 16, verseEnd: 18).description == "John 3:16\u{2013}18")
        #expect(PassageReference(verse: VerseID(book: 19, chapter: 23, verse: 1)).description == "Psalms 23:1")
    }
}
