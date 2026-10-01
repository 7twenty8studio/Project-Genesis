import CryptoKit
import Foundation
import Testing
@testable import Genesis

@Suite("Feature choices")
@MainActor
struct FeaturePreferencesTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "Features-\(UUID())")!
    }

    @Test func newPeopleGetTheSuggestedSet() {
        let features = FeaturePreferences(defaults: freshDefaults())
        #expect(features.enabled == OptionalFeature.defaults)
        #expect(!features.isOn(.together), "Groups and community are opt-in")
        #expect(!features.hasChosen)
    }

    @Test func existingPeopleKeepEverything() {
        let features = FeaturePreferences(defaults: freshDefaults(), existingUser: true)
        #expect(features.enabled == Set(OptionalFeature.allCases))
    }

    @Test func choicesAreRemembered() {
        let defaults = freshDefaults()
        let features = FeaturePreferences(defaults: defaults)
        features.choose([])
        features.set(.listen, on: true)
        let relaunched = FeaturePreferences(defaults: defaults, existingUser: true)
        #expect(relaunched.enabled == [.listen], "A saved choice wins over the existing-user default")
        #expect(relaunched.hasChosen)
    }

    @Test func serverSwitchesStillDecideWhatExists() {
        let features = FeaturePreferences(defaults: freshDefaults(), existingUser: true)
        let off = FeatureFlagService(client: nil, override: [:])
        let on = FeatureFlagService(client: nil, override: [.studyAssistant: true, .groups: true])
        #expect(!features.shows(.studyAssistant, flags: off))
        #expect(features.shows(.studyAssistant, flags: on))
        #expect(!features.shows(.together, flags: off))
        #expect(features.shows(.together, flags: on))
        #expect(FeaturePreferences.offered(flags: off) == [.listen, .plansAndPrayer, .explore])
    }

    @Test func hidingTheAssistantSwitchesItOff() {
        let features = FeaturePreferences(defaults: freshDefaults(), existingUser: true)
        let assistant = StudyAssistant(
            auth: AuthService(client: nil, restoresSession: false),
            entitlements: EntitlementService(defaults: freshDefaults(), override: true),
            library: BibleLibrary(),
            backend: nil,
            flags: FeatureFlagService(client: nil, override: [.studyAssistant: true]),
            preferences: features
        )
        #expect(assistant.isEnabled)
        features.set(.studyAssistant, on: false)
        #expect(!assistant.isEnabled)
    }

    @Test func announcementsKnowTheirFeature() {
        #expect(WhatsNewCatalog.audioBible.feature == .listen)
        #expect(WhatsNewCatalog.churchGroups.feature == .together)
        #expect(WhatsNewCatalog.studyAssistant.feature == .studyAssistant)
    }
}

@Suite("Topics")
struct TopicTests {
    private func topics() throws -> TopicRepository {
        let url = try #require(Bundle.main.url(forResource: "Topics", withExtension: "sqlite"))
        return try TopicRepository(url: url)
    }

    @Test func findsTopicsByName() throws {
        let repository = try topics()
        let forgive = try repository.search("forgive")
        #expect(forgive.first?.name == "Forgiveness")
        let faith = try repository.search("Faith")
        #expect(faith.first?.name == "Faith", "An exact match comes first")
        let short = try repository.search("lo")
        #expect(short.isEmpty, "Two letters are too few")
    }

    @Test func topicsHaveHeadingsAndPassages() throws {
        let repository = try topics()
        let found = try repository.search("forgiveness").first?.id
        let id = try #require(found)
        let loaded = try repository.topic(id: id)
        let topic = try #require(loaded)
        let instances = try #require(topic.entries.first { $0.label == "Instances of" })
        let joseph = try #require(topic.entries.first { $0.parentID == instances.id && $0.label.hasPrefix("Joseph") })
        #expect(joseph.passages.first?.reference.description == "Genesis 45:5\u{2013}15")
        let lordsPrayer = try repository.search("lords prayer")
        #expect(lordsPrayer.first?.name == "Lord's Prayer", "Apostrophes don't matter")
        #expect(topic.seeAlso.contains { $0.name == "Enemy" })
    }
}

@Suite("Bible downloads")
@MainActor
struct BibleDownloadTests {
    private func packed(_ data: Data) throws -> Data {
        try (data as NSData).compressed(using: .zlib) as Data
    }

    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test func unpacksAndChecksDownloads() throws {
        let original = Data("A Bible database".utf8)
        let file = try packed(original)
        let unpacked = try TranslationDownloader.unpack(file, expectedBytes: original.count, sha256: hash(original))
        #expect(unpacked == original)
        #expect(throws: TranslationDownloadError.damaged) {
            _ = try TranslationDownloader.unpack(file, expectedBytes: original.count, sha256: String(repeating: "0", count: 64))
        }
        #expect(throws: TranslationDownloadError.damaged) {
            _ = try TranslationDownloader.unpack(Data("not compressed".utf8), expectedBytes: 10, sha256: hash(original))
        }
    }

    @Test func downloadedTranslationsJoinTheLibraryAndCanBeRemoved() throws {
        let directory = URL.temporaryDirectory.appending(path: "bibles-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Stand in for a download with a copy of a bundled database.
        let source = try #require(Bundle.main.url(forResource: "WEB", withExtension: "sqlite"))
        try FileManager.default.copyItem(at: source, to: directory.appending(path: "TST-1.sqlite"))
        try FileManager.default.copyItem(at: source, to: directory.appending(path: "OLD-1.sqlite"))
        let test = Translation(id: "TST", name: "Test Bible", year: "2026", license: "Public domain", summary: "")
        let installed = [InstalledTranslation(translation: test, version: 1, fileName: "TST-1.sqlite")]
        try JSONEncoder().encode(installed).write(to: directory.appending(path: "installed.json"))

        let defaults = UserDefaults(suiteName: "Downloads-\(UUID())")!
        let library = BibleLibrary(defaults: defaults, directory: directory)
        #expect(library.translations.map(\.id) == ["KJV", "WEB", "ASV", "TST"])
        #expect(library.isRemovable(test))
        #expect(!library.isRemovable(.kjv))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "OLD-1.sqlite").path(percentEncoded: false)), "Files nobody uses are cleared")

        library.currentTranslation = test
        let verse = try library.current.verse(VerseID(book: 43, chapter: 3, verse: 16))
        #expect(verse != nil)

        library.remove(test)
        #expect(library.translations.map(\.id) == ["KJV", "WEB", "ASV"])
        #expect(library.currentTranslation == .kjv, "Removing the current Bible switches back to the KJV")
    }
}
