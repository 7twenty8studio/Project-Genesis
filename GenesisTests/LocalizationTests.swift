import Foundation
import Testing
@testable import Genesis

@Suite("Spanish")
struct LocalizationTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let input: String
        let book: Int
        let chapter: Int
        let verse: Int?

        var testDescription: String { input }
    }

    @Test("Spanish book names and abbreviations", arguments: [
        Case(input: "Juan 3:16", book: 43, chapter: 3, verse: 16),
        Case(input: "Jn 3,16", book: 43, chapter: 3, verse: 16),
        Case(input: "Génesis 1", book: 1, chapter: 1, verse: nil),
        Case(input: "genesis 1", book: 1, chapter: 1, verse: nil),
        Case(input: "Gn 1:1", book: 1, chapter: 1, verse: 1),
        Case(input: "Éxodo 20", book: 2, chapter: 20, verse: nil),
        Case(input: "Salmos 23", book: 19, chapter: 23, verse: nil),
        Case(input: "Sal 23:1", book: 19, chapter: 23, verse: 1),
        Case(input: "Salmo 91", book: 19, chapter: 91, verse: nil),
        Case(input: "1 Corintios 13:4", book: 46, chapter: 13, verse: 4),
        Case(input: "1 Reyes 18", book: 11, chapter: 18, verse: nil),
        Case(input: "2 Crónicas 7:14", book: 14, chapter: 7, verse: 14),
        Case(input: "2 cronicas 7:14", book: 14, chapter: 7, verse: 14),
        Case(input: "Cantares 2", book: 22, chapter: 2, verse: nil),
        Case(input: "Hechos 2:38", book: 44, chapter: 2, verse: 38),
        Case(input: "Hch 2", book: 44, chapter: 2, verse: nil),
        Case(input: "Santiago 1:5", book: 59, chapter: 1, verse: 5),
        Case(input: "Stg 1", book: 59, chapter: 1, verse: nil),
        Case(input: "Apocalipsis 22:21", book: 66, chapter: 22, verse: 21),
        Case(input: "Primera de Juan 1:9", book: 62, chapter: 1, verse: 9),
        Case(input: "primera Juan 1:9", book: 62, chapter: 1, verse: 9),
        Case(input: "1 Juan 1:9", book: 62, chapter: 1, verse: 9),
        Case(input: "Filemón 4", book: 57, chapter: 1, verse: 4),
        Case(input: "Jonás 2", book: 32, chapter: 2, verse: nil),
        Case(input: "Mateo 5", book: 40, chapter: 5, verse: nil),
        Case(input: "Marcos 1", book: 41, chapter: 1, verse: nil),
        Case(input: "Mr 1", book: 41, chapter: 1, verse: nil),
    ])
    func parsesSpanish(_ test: Case) throws {
        let reference = try #require(ReferenceParser.parse(test.input))
        #expect(reference.book.id == test.book)
        #expect(reference.chapter == test.chapter)
        #expect(reference.verseStart == test.verse)
    }

    @Test func englishSpellingsWinWhereTheLanguagesShareOne() throws {
        // "Mc" is Micah in English; Spanish uses "Mr" for Mark.
        #expect(ReferenceParser.parse("Mc 6:8")?.book.id == 33)
        #expect(ReferenceParser.parse("John 3:16")?.book.id == 43)
        #expect(ReferenceParser.parse("Jude 3")?.book.id == 65)
    }

    @Test func spanishSuggestionsWhileTyping() {
        #expect(ReferenceParser.books(matching: "Apoc").map(\.id) == [66])
        #expect(ReferenceParser.books(matching: "Deuteronomio").map(\.id) == [5])
    }

    @Test func bookNamesInEachLanguage() {
        let john = BibleBook.withNumber(43)
        #expect(john.name(in: "en") == "John")
        #expect(john.name(in: "es") == "Juan")
        #expect(BibleBook.withNumber(22).name(in: "es") == "Cantares")
        #expect(BibleBook.withNumber(66).abbreviation(in: "es") == "Ap")
        #expect(BibleBook.spanish.count == 66)
        // Tests run in English.
        #expect(john.name == "John")
        #expect(AppLanguage.code == "en")
    }

    @Test func translationsSavedBeforeLanguagesAreEnglish() throws {
        let old = #"{"id":"BSB","name":"Berean Standard Bible","year":"2023","license":"Public domain","summary":""}"#
        let translation = try JSONDecoder().decode(Translation.self, from: Data(old.utf8))
        #expect(translation.language == "en")

        let spanish = Translation(id: "RV1909", name: "Reina-Valera 1909", year: "1909", license: "Dominio público", summary: "", language: "es")
        let roundTrip = try JSONDecoder().decode(Translation.self, from: JSONEncoder().encode(spanish))
        #expect(roundTrip.language == "es")
    }

    @Test func catalogRowsWithAndWithoutLanguage() throws {
        let row = #"{"id":"RV1909","name":"Reina-Valera 1909","year":"1909","license":"Dominio público","summary":"","file_url":"https://example.com/RV1909-1.sqlite.deflate","file_bytes":1,"database_bytes":2,"sha256":"00","version":1,"enabled":true,"sort":20}"#
        let older = try JSONDecoder().decode(DownloadableTranslation.self, from: Data(row.utf8))
        #expect(older.language == "en")
        let withLanguage = row.replacingOccurrences(of: #""sort":20"#, with: #""sort":20,"language":"es""#)
        let newer = try JSONDecoder().decode(DownloadableTranslation.self, from: Data(withLanguage.utf8))
        #expect(newer.language == "es")
        #expect(newer.translation.language == "es")
    }

    @Test func studyAnswersAreKeptPerLanguage() {
        let passage = StudyPassage(start: VerseID(book: 43, chapter: 3, verse: 16), end: VerseID(book: 43, chapter: 3, verse: 18))
        #expect(passage.cacheKey(.explain, language: "en") == "v1:explain:43003016-43003018")
        #expect(passage.cacheKey(.explain, language: "es") == "v1:explain:43003016-43003018:es")
    }
}
