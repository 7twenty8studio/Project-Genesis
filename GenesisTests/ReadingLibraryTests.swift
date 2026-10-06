import Foundation
import Testing
@testable import Genesis

@Suite("Global Reading Library")
struct ReadingLibraryTests {
    private func offer(_ id: String, name: String, language: String = "en", license: String = "Public domain", json extra: String = "") throws -> DownloadableTranslation {
        let json = """
        {"id": "\(id)", "name": "\(name)", "year": "2023", "license": "\(license)", "summary": "",
         "file_url": "https://example.com/\(id).deflate", "file_bytes": 10, "database_bytes": 20,
         "sha256": "\(String(repeating: "a", count: 64))", "version": 1, "language": "\(language)"\(extra)}
        """
        return try JSONDecoder().decode(DownloadableTranslation.self, from: Data(json.utf8))
    }

    @Test func readsTheServersDetails() throws {
        let item = try offer("NEW", name: "New Bible", json: #", "approach": "thought_for_thought", "reading_level": "everyday", "rights": "licensed", "popularity": 3"#)
        #expect(item.profile == TranslationProfile(approach: .thoughtForThought, readingLevel: .everyday, rights: .licensed, popularity: 3))
    }

    @Test func unknownOrMissingDetailsFallBack() throws {
        // An older server: no columns. The app knows the BSB.
        let bsb = try offer("BSB", name: "Berean Standard Bible")
        #expect(bsb.profile == TranslationProfile.builtIn["BSB"])
        // A value this version doesn't know is ignored, not fatal; the
        // licence line still says public domain.
        let odd = try offer("ODD", name: "Odd Bible", json: #", "approach": "paraphrase-ish""#)
        #expect(odd.profile.approach == nil)
        #expect(odd.profile.rights == .publicDomain)
        // The server wins over what the app knows.
        let moved = try offer("BSB", name: "Berean Standard Bible", json: #", "popularity": 1"#)
        #expect(moved.profile.popularity == 1)
        #expect(moved.profile.approach == .balanced)
    }

    @Test func spanishLicenceReadsAsPublicDomain() {
        #expect(TranslationProfile.rights(fromLicense: "Dominio público") == .publicDomain)
        #expect(TranslationProfile.rights(fromLicense: "© Publisher. Used by permission.") == nil)
    }

    @Test func languagesPutTheAppsFirst() throws {
        let rv = try offer("RV1909", name: "Reina-Valera 1909", language: "es")
        #expect(ReadingLibrary.languages(installed: Translation.bundled, catalog: [rv], preferred: "es") == ["es", "en"])
        #expect(ReadingLibrary.languages(installed: Translation.bundled, catalog: [rv], preferred: "en") == ["en", "es"])
        #expect(ReadingLibrary.languages(installed: Translation.bundled, catalog: [], preferred: "es") == ["en"])
    }

    @Test func entriesAreMostReadFirstAndMergeDownloads() throws {
        let bsb = try offer("BSB", name: "Berean Standard Bible")
        let rv = try offer("RV1909", name: "Reina-Valera 1909", language: "es")
        let unknown = try offer("ZZZ", name: "Another Bible")
        let english = ReadingLibrary.entries(in: "en", installed: Translation.bundled, catalog: [unknown, bsb, rv], recordedTranslationIDs: ["WEB"])
        #expect(english.map(\.id) == ["KJV", "BSB", "WEB", "ASV", "ZZZ"])
        #expect(english.first { $0.id == "BSB" }?.isInstalled == false)
        #expect(english.first { $0.id == "KJV" }?.isInstalled == true)
        #expect(english.first { $0.id == "WEB" }?.hasRecordedAudio == true)
        #expect(english.first { $0.id == "KJV" }?.hasRecordedAudio == false)

        let spanish = ReadingLibrary.entries(in: "es", installed: Translation.bundled, catalog: [bsb, rv], recordedTranslationIDs: [])
        #expect(spanish.map(\.id) == ["RV1909"])
    }

    @Test func aDownloadedBibleAppearsOnce() throws {
        let bsb = try offer("BSB", name: "Berean Standard Bible")
        let installed = Translation.bundled + [bsb.translation]
        let entries = ReadingLibrary.entries(in: "en", installed: installed, catalog: [bsb], recordedTranslationIDs: [])
        #expect(entries.filter { $0.id == "BSB" }.count == 1)
        #expect(entries.first { $0.id == "BSB" }?.isInstalled == true)
        #expect(entries.first { $0.id == "BSB" }?.download != nil, "Still linked to its catalog entry")
    }

    @Test func suggestsABibleForEachWayOfReading() throws {
        let bsb = try offer("BSB", name: "Berean Standard Bible")
        let entries = ReadingLibrary.entries(in: "en", installed: Translation.bundled, catalog: [bsb], recordedTranslationIDs: [])
        #expect(ReadingLibrary.suggestion(for: .study, in: entries)?.id == "WEB", "Word for word in everyday English")
        #expect(ReadingLibrary.suggestion(for: .everyday, in: entries)?.id == "BSB", "Balanced, everyday")
        #expect(ReadingLibrary.suggestion(for: .classic, in: entries)?.id == "KJV", "The most read traditional Bible")

        // Without the BSB, everyday reading falls to the WEB.
        let bundledOnly = ReadingLibrary.entries(in: "en", installed: Translation.bundled, catalog: [], recordedTranslationIDs: [])
        #expect(ReadingLibrary.suggestion(for: .everyday, in: bundledOnly)?.id == "WEB")
    }

    @Test func noSuggestionWithoutDetails() throws {
        let unknown = try offer("ZZZ", name: "Another Bible")
        let entries = ReadingLibrary.entries(in: "en", installed: [], catalog: [unknown], recordedTranslationIDs: [])
        for purpose in ReadingPurpose.allCases {
            #expect(ReadingLibrary.suggestion(for: purpose, in: entries) == nil)
        }
    }
}
