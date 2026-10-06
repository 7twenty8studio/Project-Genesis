import Foundation
import Testing
@testable import Genesis

@Suite("Verse ids and navigation")
struct VerseIDTests {
    @Test func encodesAndDecodes() {
        let id = VerseID(book: 43, chapter: 3, verse: 16)
        #expect(id.rawValue == 43_003_016)
        #expect(id.book == 43)
        #expect(id.chapter == 3)
        #expect(id.verse == 16)
        #expect(id.chapterID == ChapterID(book: 43, chapter: 3))
    }

    @Test func ordersCanonically() {
        #expect(VerseID(book: 1, chapter: 50, verse: 26) < VerseID(book: 2, chapter: 1, verse: 1))
        #expect(VerseID(book: 19, chapter: 9, verse: 20) < VerseID(book: 19, chapter: 10, verse: 1))
    }

    @Test func chapterNavigationCrossesBooks() {
        #expect(ChapterID(book: 1, chapter: 50).next == ChapterID(book: 2, chapter: 1))
        #expect(ChapterID(book: 2, chapter: 1).previous == ChapterID(book: 1, chapter: 50))
        #expect(ChapterID(book: 1, chapter: 1).previous == nil)
        #expect(ChapterID(book: 66, chapter: 22).next == nil)
    }

    @Test func catalogIsComplete() {
        #expect(BibleBook.all.count == 66)
        #expect(BibleBook.all.map(\.id) == Array(1...66))
        #expect(BibleBook.all.reduce(0) { $0 + $1.chapterCount } == 1189)
        #expect(BibleBook.oldTestament.count == 39)
    }

    @Test func dailyVerseIsStableForADay() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(DailyVerse.verse(for: date) == DailyVerse.verse(for: date.addingTimeInterval(60)))
        // Early morning and late evening in a time zone behind UTC: one day, one verse.
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = TimeZone(identifier: "America/Chicago")!
        let early = chicago.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 0, minute: 30))!
        let late = chicago.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 23, minute: 30))!
        let nextDay = chicago.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 0, minute: 30))!
        #expect(DailyVerse.verse(for: early, calendar: chicago) == DailyVerse.verse(for: late, calendar: chicago))
        #expect(DailyVerse.verse(for: late, calendar: chicago) != DailyVerse.verse(for: nextDay, calendar: chicago))
        let allValid = DailyVerse.curated.allSatisfy { $0.chapter <= BibleBook.withNumber($0.book).chapterCount }
        #expect(allValid)
    }
}

@Suite("Full-text query building")
struct FullTextQueryTests {
    @Test func wordsAreQuotedAndLastIsPrefix() throws {
        let query = try #require(FullTextQuery("faith hope"))
        #expect(query.matchExpression == "\"faith\" \"hope\"*")
        #expect(query.terms == ["faith", "hope"])
    }

    @Test func trailingSpaceEndsPrefix() throws {
        let query = try #require(FullTextQuery("faith hope "))
        #expect(query.matchExpression == "\"faith\" \"hope\"")
    }

    @Test func quotedTextIsAPhrase() throws {
        let query = try #require(FullTextQuery("\u{201C}The Lord is my shepherd\u{201D}"))
        #expect(query.isPhrase)
        #expect(query.matchExpression == "\"the lord is my shepherd\"")
    }

    @Test func operatorsAreNeutralised() throws {
        let query = try #require(FullTextQuery("love OR NEAR(x) * -hate"))
        #expect(!query.matchExpression.contains("OR "))
        #expect(query.matchExpression.contains("\"or\""))
        #expect(!query.matchExpression.contains("("))
    }

    @Test func emptyInputHasNoQuery() {
        #expect(FullTextQuery("  ") == nil)
        #expect(FullTextQuery("!!!") == nil)
    }

    @Test func highlighterMatchesWordStarts() {
        let text = "For God so loved the world"
        let ranges = SearchHighlighter.matchRanges(in: text, terms: ["love", "world"])
        let words = ranges.map { String(text[$0]) }
        #expect(words == ["loved", "world"])
    }
}
