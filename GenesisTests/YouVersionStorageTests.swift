import CryptoKit
import Foundation
import Testing
@testable import Genesis

/// What the publishers' agreements ask of YouVersion Bibles on the device
/// (LICENSED_BIBLES.md › 5): every footnote kept and shown apart from the
/// text, the text sealed, chapters refreshed after the Platform's lifetime.
@MainActor
@Suite("YouVersion storage")
struct YouVersionStorageTests {
    private static let niv = Translation(id: "NIV", name: "New International Version", year: "2011", license: "© Biblica", summary: "", isYouVersion: true)

    /// John 1, shaped like yvp-bible's answer with footnotes (checked against
    /// the NIV, 23 October 2026).
    private static let john = Data("""
    {"id":"NIV","book":"JHN","chapters":[{"chapter":1,"maxAge":3600,
      "verses":[
        {"verse":4,"text":"In him was life, and that life was the light of all mankind.","paragraph":false,"poetry":false},
        {"verse":5,"text":"The light shines in the darkness, and the darkness has not overcome it.","paragraph":false,"poetry":false}
      ],
      "headings":[],
      "notes":[{"verse":5,"offset":67,"text":"Or understood"}]}]}
    """.utf8)

    private func book() throws -> YouVersionBook {
        try JSONDecoder().decode(YouVersionBook.self, from: Self.john)
    }

    private func repository(_ data: Data) throws -> BibleRepository {
        let url = FileManager.default.temporaryDirectory.appending(path: "yvp-\(UUID().uuidString).sqlite")
        try data.write(to: url)
        return try BibleRepository(translation: Self.niv, url: url)
    }

    @Test func footnotesAreKeptApartFromTheText() throws {
        let data = try BibleFileWriter.build(books: [43: try book()], translation: Self.niv)
        let chapter = try repository(data).chapter(ChapterID(book: 43, chapter: 1))
        let five = try #require(chapter.verses.first { $0.id.verse == 5 })
        #expect(five.text == "The light shines in the darkness, and the darkness has not overcome it.")
        #expect(chapter.footnotes == [Footnote(verse: VerseID(book: 43, chapter: 1, verse: 5), offset: 67, text: "Or understood")])
        // The marker goes right after "overcome".
        #expect((five.text as NSString).substring(to: 67).hasSuffix("overcome"))
    }

    @Test func booksFetchedBeforeNotesStillDecode() throws {
        let old = Data(#"{"id":"NIV","book":"JHN","chapters":[{"chapter":1,"verses":[],"headings":[]}]}"#.utf8)
        let chapter = try #require(try JSONDecoder().decode(YouVersionBook.self, from: old).chapters.first)
        #expect(chapter.notes.isEmpty)
        #expect(chapter.maxAge == nil)
    }

    @Test func aRefreshedChapterReplacesTheOldOneEverywhere() throws {
        let original = try BibleFileWriter.build(books: [43: try book()], translation: Self.niv)
        let corrected = YouVersionBook.Chapter(
            chapter: 1,
            verses: [
                .init(verse: 4, last: nil, text: "In him was life, and that life was the light of all people.", paragraph: false, poetry: false),
                .init(verse: 5, last: nil, text: "The light shines in the darkness, and the darkness has not overcome it.", paragraph: true, poetry: false),
            ],
            headings: [.init(beforeVerse: 4, text: "The Word")],
            notes: [.init(verse: 4, offset: 0, text: "A new note")]
        )
        let patched = try repository(try BibleFileWriter.replacingChapter(corrected, book: 43, in: original))
        let chapter = try patched.chapter(ChapterID(book: 43, chapter: 1))
        #expect(chapter.verses.map(\.text).first == "In him was life, and that life was the light of all people.")
        #expect(chapter.headings.map(\.text) == ["The Word"])
        #expect(chapter.footnotes.map(\.text) == ["A new note"])
        // The search index forgot the old words and knows the new ones.
        #expect(try patched.search(matchExpression: "mankind", scope: .wholeBible, order: .canonical, limit: 5).isEmpty)
        #expect(try patched.search(matchExpression: "people", scope: .wholeBible, order: .canonical, limit: 5).map(\.id.verse) == [4])
    }

    @Test func anUnchangedChapterIsNotRewritten() throws {
        let fresh = try #require(try book().chapters.first)
        let stored = try repository(try BibleFileWriter.build(books: [43: try book()], translation: Self.niv)).chapter(ChapterID(book: 43, chapter: 1))
        #expect(!YouVersionChapterComparison.differs(stored: stored, fresh: fresh))
        let changed = YouVersionBook.Chapter(chapter: 1, verses: fresh.verses, headings: fresh.headings, notes: [])
        #expect(YouVersionChapterComparison.differs(stored: stored, fresh: changed))
    }

    @Test func sealedBiblesOpenOnlyWithTheirKey() throws {
        let plain = try BibleFileWriter.build(books: [43: try book()], translation: Self.niv)
        let key = SymmetricKey(size: .bits256)
        let sealed = try BibleProtection.seal(plain, key: key)
        #expect(BibleProtection.isSealed(sealed))
        #expect(!BibleProtection.isSealed(plain))
        // None of the text can be read from the sealed bytes.
        #expect(sealed.range(of: Data("darkness".utf8)) == nil)
        #expect(try BibleProtection.open(sealed, key: key) == plain)
        #expect(throws: (any Error).self) { try BibleProtection.open(sealed, key: SymmetricKey(size: .bits256)) }
        // Opened into memory, it reads like any Bible.
        let database = try SQLiteDatabase(contents: try BibleProtection.open(sealed, key: key))
        #expect(try database.query("SELECT count(*) FROM verses") { $0.int(0) } == [2])
    }

    @Test func aChapterIsFetchedAgainOnlyAfterItsLifetime() {
        var freshness = YouVersionFreshness()
        let fetched = Date(timeIntervalSince1970: 1_000_000)
        #expect(freshness.isStale(book: 43, chapter: 1, now: fetched))
        freshness.set(book: 43, chapter: 1, fetchedAt: fetched, maxAge: 3600)
        #expect(!freshness.isStale(book: 43, chapter: 1, now: fetched.addingTimeInterval(3599)))
        #expect(freshness.isStale(book: 43, chapter: 1, now: fetched.addingTimeInterval(3600)))
        // Without a lifetime from the source, the Platform's usual hour.
        freshness.set(book: 43, chapter: 2, fetchedAt: fetched, maxAge: nil)
        #expect(!freshness.isStale(book: 43, chapter: 2, now: fetched.addingTimeInterval(60)))
        #expect(freshness.isStale(book: 43, chapter: 2, now: fetched.addingTimeInterval(3600)))
    }

    @Test func footnoteMarkersAreLetters() {
        #expect(ChapterTextBuilder.footnoteLabel(0) == "a")
        #expect(ChapterTextBuilder.footnoteLabel(25) == "z")
        #expect(ChapterTextBuilder.footnoteLabel(26) == "aa")
    }

    @Test func theAnnouncementIsNew() {
        let ids = WhatsNewCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.last == "footnotes")
    }
}
