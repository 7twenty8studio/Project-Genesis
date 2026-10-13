import Foundation
import SQLite3
import Testing
import UIKit
@testable import Genesis

/// Licensed Bibles from the Digital Bible Library: copyright notices,
/// joined verses ("16–17") and keeping their text away from the AI service.
@MainActor
@Suite("Licensed Bibles")
struct LicensedBibleTests {
    private static let notice = "Scripture taken from the Test Bible®. Copyright © 2011 by Test, Inc. Used by permission. All rights reserved worldwide."
    private static let licensed = Translation(id: "TST", name: "Test Bible", year: "2011", license: notice, summary: "")

    /// A tiny Bible database shaped like Tools/BibleData/import_dbl.py's,
    /// with John 3:16–17 joined.
    private func database() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "licensed-\(UUID().uuidString).sqlite")
        var handle: OpaquePointer?
        let opened = sqlite3_open(url.path(percentEncoded: false), &handle)
        #expect(opened == SQLITE_OK)
        defer { sqlite3_close(handle) }
        let sql = """
        CREATE TABLE verses (id INTEGER PRIMARY KEY, book INTEGER, chapter INTEGER, verse INTEGER, text TEXT, paragraph INTEGER, poetry INTEGER);
        CREATE TABLE headings (book INTEGER, chapter INTEGER, before_verse INTEGER, text TEXT);
        CREATE TABLE verse_spans (id INTEGER PRIMARY KEY, last INTEGER NOT NULL);
        INSERT INTO verses VALUES (43003015, 43, 3, 15, 'Fifteen.', 0, 0);
        INSERT INTO verses VALUES (43003016, 43, 3, 16, 'Sixteen and seventeen.', 1, 0);
        INSERT INTO verses VALUES (43003018, 43, 3, 18, 'Eighteen.', 0, 0);
        INSERT INTO verse_spans VALUES (43003016, 43003017);
        """
        let created = sqlite3_exec(handle, sql, nil, nil, nil)
        #expect(created == SQLITE_OK)
        return url
    }

    @Test func licensedMeansNotPublicDomain() {
        #expect(Self.licensed.isLicensed)
        #expect(!Translation.kjv.isLicensed)
        #expect(!Translation.web.isLicensed)
        let reinaValera = Translation(id: "RV1909", name: "Reina-Valera 1909", year: "1909", license: "Dominio público", summary: "", language: "es")
        #expect(!reinaValera.isLicensed)
    }

    @Test func joinedVersesShowTheirRange() throws {
        let repository = try BibleRepository(translation: Self.licensed, url: try database())
        let chapter = try repository.chapter(ChapterID(book: 43, chapter: 3))
        let labels = chapter.verses.map(\.numberLabel)
        #expect(labels == ["15", "16\u{2013}17", "18"])
        let count = try repository.verseCount(in: ChapterID(book: 43, chapter: 3))
        #expect(count == 4)
    }

    @Test func aVerseInsideAJoinedGroupFindsItsWords() throws {
        let repository = try BibleRepository(translation: Self.licensed, url: try database())
        let seventeen = try repository.verse(VerseID(book: 43, chapter: 3, verse: 17))
        #expect(seventeen?.text == "Sixteen and seventeen.")
        let range = try repository.verses(from: VerseID(book: 43, chapter: 3, verse: 17), through: VerseID(book: 43, chapter: 3, verse: 18))
        #expect(range.map(\.id.verse) == [16, 18])
    }

    @Test func theCopyrightNoticeFollowsTheChapterApartFromTheVerses() throws {
        let repository = try BibleRepository(translation: Self.licensed, url: try database())
        let chapter = try repository.chapter(ChapterID(book: 43, chapter: 3))
        #expect(chapter.copyrightNotice == Self.notice)
        let style = ReaderStyle(preferences: ReaderPreferences(), theme: .paper, contentSizeCategory: .large)
        let built = ChapterTextBuilder.build(chapter, style: style, decorations: ChapterDecorations())
        let text = built.text.string
        let noticeRange = (text as NSString).range(of: Self.notice)
        #expect(noticeRange.location != NSNotFound)
        let verseAttribute = built.text.attribute(.verseID, at: noticeRange.location, effectiveRange: nil)
        let isPartOfAVerse = verseAttribute != nil
        #expect(!isPartOfAVerse, "The notice is never part of a verse")
        #expect(text.contains("Sixteen and seventeen."))
    }

    @Test func publicDomainChaptersHaveNoNotice() throws {
        let url = try #require(Bundle.main.url(forResource: "KJV", withExtension: "sqlite"))
        let chapter = try BibleRepository(translation: .kjv, url: url).chapter(ChapterID(book: 43, chapter: 3))
        #expect(chapter.copyrightNotice == nil)
    }

    @Test func sharedJoinedVersesKeepTheirRange() {
        let verses = [
            Verse(id: VerseID(book: 43, chapter: 3, verse: 15), text: "Fifteen.", startsParagraph: false, isPoetry: false),
            Verse(id: VerseID(book: 43, chapter: 3, verse: 16), text: "Sixteen and seventeen.", startsParagraph: false, isPoetry: false, lastVerse: 17),
        ]
        let shared = ChapterTextBuilder.shareText(for: verses, translation: Self.licensed)
        #expect(shared.contains("16\u{2013}17 Sixteen and seventeen."))
        #expect(shared.contains("(TST)"))
    }

    // MARK: Premium Bibles (paid licences)

    @Test func theCatalogMarksPaidBiblesPremium() throws {
        let json = """
        [{"id":"NIV","name":"New International Version","year":"2011","license":"Copyright Biblica","summary":"",
          "file_url":"https://x.supabase.co/storage/v1/object/licensed-bibles/NIV-1.sqlite.deflate","file_bytes":1,
          "database_bytes":1,"sha256":"00","version":1,"rights":"licensed","premium":true},
         {"id":"NVI","name":"Nueva Versión Internacional","year":"2022","license":"Copyright Biblica","summary":"",
          "file_url":"https://x.supabase.co/storage/v1/object/licensed-bibles/NVI-1.sqlite.deflate","file_bytes":1,
          "database_bytes":1,"sha256":"00","version":1,"language":"es"}]
        """
        let items = try JSONDecoder().decode([DownloadableTranslation].self, from: Data(json.utf8))
        let premium = items.map(\.translation.requiresPremium)
        #expect(premium == [true, false], "A free licence stays free; only a paid one needs Premium")
    }

    @Test func savedBiblesRememberPremiumAndOlderOnesAreFree() throws {
        let paid = Translation(id: "NIV", name: "NIV", year: "2011", license: "Copyright", summary: "", requiresPremium: true)
        let decoded = try JSONDecoder().decode(Translation.self, from: JSONEncoder().encode(paid))
        #expect(decoded.requiresPremium)
        let older = #"{"id":"BSB","name":"Berean Standard Bible","year":"2023","license":"Public domain","summary":""}"#
        let old = try JSONDecoder().decode(Translation.self, from: Data(older.utf8))
        #expect(!old.requiresPremium)
    }

    @Test func withoutPremiumAPaidBibleIsLockedAndAnotherIsRead() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "bibles-\(UUID().uuidString)")
        let defaults = try #require(UserDefaults(suiteName: "licensed-\(UUID().uuidString)"))
        let library = BibleLibrary(defaults: defaults, directory: directory)
        let paid = Translation(id: "NIV", name: "NIV", year: "2011", license: "Copyright", summary: "", requiresPremium: true)
        let free = Translation(id: "NVI", name: "NVI", year: "2022", license: "Copyright", summary: "", language: "es")

        #expect(!library.isLocked(paid), "Unlocked until StoreKit says otherwise")
        library.premiumBiblesUnlocked = false
        #expect(library.isLocked(paid))
        #expect(!library.isLocked(free), "A free licence is never locked")
        #expect(!library.isLocked(.kjv))
        let instead = library.fallback(for: paid)
        #expect(instead.language == "en" && !instead.requiresPremium)
    }
}
