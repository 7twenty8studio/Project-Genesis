import Foundation
import Testing
@testable import Genesis

/// Bibles from the YouVersion Platform: built on the device from the
/// yvp-bible function's books, always free, and kept out of paid features
/// (LICENSED_BIBLES.md › 5).
@MainActor
@Suite("YouVersion Bibles")
struct YouVersionBibleTests {
    private static let notice = "The Holy Bible, New International Version® NIV®\nCopyright © 1973, 1978, 1984, 2011 by Biblica, Inc.®"
    private static let niv = Translation(id: "NIV", name: "New International Version", year: "2011", license: notice, summary: "", isYouVersion: true)
    private static let nvi = Translation(id: "NVI", name: "Nueva Versión Internacional", year: "2025", license: "© Biblica, Inc.", summary: "", language: "es", isYouVersion: true)
    private static let reinaValera = Translation(id: "RV1909", name: "Reina-Valera 1909", year: "1909", license: "Dominio público", summary: "", language: "es")

    /// John 3, shaped like a yvp-bible response (two verses joined).
    private static let john = Data("""
    {"id":"NIV","book":"JHN","chapters":[{"chapter":3,
      "verses":[
        {"verse":1,"text":"Now there was a Pharisee, a man named Nicodemus.","paragraph":true,"poetry":false},
        {"verse":16,"last":17,"text":"For God so loved the world that he gave his one and only Son.","paragraph":true,"poetry":false},
        {"verse":18,"text":"Whoever believes in him is not condemned in Beth\u{2013}lehem.","paragraph":false,"poetry":false}
      ],
      "headings":[{"beforeVerse":1,"text":"Jesus Teaches Nicodemus"}]}]}
    """.utf8)

    private func builtBible() throws -> BibleRepository {
        let book = try JSONDecoder().decode(YouVersionBook.self, from: Self.john)
        let url = FileManager.default.temporaryDirectory.appending(path: "yvp-\(UUID().uuidString).sqlite")
        try BibleFileWriter.write(books: [43: book], translation: Self.niv, to: url)
        return try BibleRepository(translation: Self.niv, url: url)
    }

    @Test func aBuiltBibleReadsLikeAnyOther() throws {
        let repository = try builtBible()
        let chapter = try repository.chapter(ChapterID(book: 43, chapter: 3))
        // Exactly as the function gave it.
        #expect(chapter.verses.map(\.text) == [
            "Now there was a Pharisee, a man named Nicodemus.",
            "For God so loved the world that he gave his one and only Son.",
            "Whoever believes in him is not condemned in Beth\u{2013}lehem.",
        ])
        #expect(chapter.verses.map(\.numberLabel) == ["1", "16\u{2013}17", "18"])
        #expect(chapter.headings.map(\.text) == ["Jesus Teaches Nicodemus"])
        #expect(chapter.copyrightNotice == Self.notice)
        #expect(try repository.verse(VerseID(book: 43, chapter: 3, verse: 17))?.text.hasPrefix("For God so loved") == true)
    }

    @Test func aBuiltBibleCanBeSearched() throws {
        let repository = try builtBible()
        let loved = try repository.search(matchExpression: "loved", scope: .wholeBible, order: .canonical, limit: 10)
        #expect(loved.map(\.id.verse) == [16])
        // Hyphenated names are found joined too, as in the bundled Bibles.
        let bethlehem = try repository.search(matchExpression: "bethlehem", scope: .wholeBible, order: .canonical, limit: 10)
        #expect(bethlehem.map(\.id.verse) == [18])
    }

    @Test func theSearchFormNeverChangesWhatIsShown() {
        #expect(BibleSearchForm.indexed("In the beginning") == "In the beginning")
        #expect(BibleSearchForm.indexed("to Beth\u{2013}lehem of Judah") == "to Beth\u{2013}lehem Bethlehem of Judah")
    }

    @Test func premiumToolsUseAPublicDomainBibleInTheSameLanguage() {
        let available = [Translation.kjv, Translation.web, Self.niv, Self.reinaValera, Self.nvi]
        #expect(BibleLibrary.premiumToolsTranslation(for: Self.niv, among: available) == .kjv)
        #expect(BibleLibrary.premiumToolsTranslation(for: Self.nvi, among: available) == Self.reinaValera)
        // Without a Spanish public-domain Bible yet, the KJV.
        #expect(BibleLibrary.premiumToolsTranslation(for: Self.nvi, among: [.kjv, Self.nvi]) == .kjv)
        // Every other Bible, licensed or not, is used as it is.
        #expect(BibleLibrary.premiumToolsTranslation(for: .web, among: available) == .web)
        let licensed = Translation(id: "TST", name: "Test", year: "", license: "© Test", summary: "")
        #expect(BibleLibrary.premiumToolsTranslation(for: licensed, among: available) == licensed)
    }

    @Test func catalogRowsAreFreeYouVersionBibles() throws {
        let json = Data("""
        [{"id":"NIrV","yvp_id":110,"name":"New International Reader’s Version","year":"2014","license":"© Biblica","summary":"Simple.","language":"en","approach":"thought_for_thought","reading_level":"everyday","popularity":5,"version":1}]
        """.utf8)
        let row = try #require(try JSONDecoder().decode([YouVersionCatalogRow].self, from: json).first)
        let item = row.downloadable
        #expect(item.youVersionID == 110)
        #expect(item.premium == false)
        #expect(item.rights == .licensed)
        #expect(item.approach == .thoughtForThought)
        #expect(item.translation.isYouVersion)
        #expect(item.translation.requiresPremium == false)
        #expect(item.translation.abbreviation == "NIrV")
    }

    @Test func translationsSavedBeforeYouVersionAreNotYouVersion() throws {
        let saved = Data(#"{"id":"BSB","name":"Berean Standard Bible","year":"2023","license":"Public domain","summary":"","language":"en"}"#.utf8)
        let translation = try JSONDecoder().decode(Translation.self, from: saved)
        #expect(!translation.isYouVersion)
        let roundTrip = try JSONDecoder().decode(Translation.self, from: JSONEncoder().encode(Self.niv))
        #expect(roundTrip.isYouVersion)
    }

    @Test func anUnfinishedDownloadIsKeptToContinue() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "yvp-parts-\(UUID().uuidString)", directoryHint: .isDirectory)
        let item = DownloadableTranslation(id: "NIV", name: "New International Version", year: "2011", license: Self.notice, summary: "",
                                           fileURL: "", fileBytes: 0, databaseBytes: 0, sha256: "", version: 1, youVersionID: 111)
        #expect(YouVersionBibleBuilder.savedBookCount(for: item, in: folder) == 0)
        let parts = YouVersionBibleBuilder.partsFolder(for: item, in: folder)
        try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
        try Self.john.write(to: parts.appending(path: "43.json"))
        try Self.john.write(to: parts.appending(path: "1.json"))
        #expect(YouVersionBibleBuilder.savedBookCount(for: item, in: folder) == 2)
        YouVersionBibleBuilder.discard(item, in: folder)
        #expect(YouVersionBibleBuilder.savedBookCount(for: item, in: folder) == 0)
    }

    @Test func theAnnouncementIsNew() {
        let ids = WhatsNewCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.last == "youversion-bibles")
    }
}
