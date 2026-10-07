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
        let alwaysOffered = OptionalFeature.allCases.filter { $0 != .studyAssistant && $0 != .together }
        #expect(FeaturePreferences.offered(flags: off) == alwaysOffered)
    }

    /// A choice saved before every feature had its own switch.
    private func legacyDefaults(_ saved: [String]) -> UserDefaults {
        let defaults = freshDefaults()
        defaults.set(saved, forKey: "features.enabled")
        defaults.set(true, forKey: "features.chosen")
        return defaults
    }

    @Test func plansAndPrayerOffKeepsPlansPrayerAndMemoriseOff() {
        let features = FeaturePreferences(defaults: legacyDefaults(["explore", "listen"]))
        #expect(!features.isOn(.plans))
        #expect(!features.isOn(.prayer))
        #expect(!features.isOn(.memorise))
        #expect(features.isOn(.listen))
        #expect(features.isOn(.explore))
        #expect(!features.isOn(.studyAssistant), "Still off, as chosen")
        #expect(!features.isOn(.together))
        #expect(features.hasChosen)
    }

    @Test func plansAndPrayerOnTurnsOnEachOfItsParts() {
        let features = FeaturePreferences(defaults: legacyDefaults(["plansAndPrayer"]))
        #expect(features.isOn(.plans))
        #expect(features.isOn(.prayer))
        #expect(features.isOn(.memorise))
        #expect(!features.isOn(.listen), "Listen was switched off")
    }

    @Test func newSwitchesStartOnForSavedChoices() {
        // These were always shown before they had a switch, so nobody loses them.
        let features = FeaturePreferences(defaults: legacyDefaults([]))
        let newSwitches: [OptionalFeature] = [.ambientSounds, .wordStudy, .insights, .moments]
        for feature in newSwitches {
            #expect(features.isOn(feature), "\(feature.rawValue) keeps showing")
        }
        #expect(!features.isOn(.plans), "Keep It Simple stays simple for plans")
    }

    @Test func theMigrationHappensOnce() {
        let defaults = legacyDefaults(["listen"])
        let first = FeaturePreferences(defaults: defaults)
        first.set(.moments, on: false)
        let relaunched = FeaturePreferences(defaults: defaults)
        #expect(!relaunched.isOn(.moments), "A switch turned off after the migration stays off")
        #expect(relaunched.isOn(.ambientSounds))
        #expect(!relaunched.isOn(.prayer))
    }

    @Test func pureMigrationRule() {
        let migrated = FeaturePreferences.migrated(saved: ["plansAndPrayer", "together"], known: OptionalFeature.legacyKnown)
        #expect(migrated.isSuperset(of: [.plans, .prayer, .memorise, .together]))
        #expect(!migrated.contains(.listen))
        let current = Set(OptionalFeature.allCases.map(\.rawValue))
        let unchanged = FeaturePreferences.migrated(saved: ["prayer"], known: current)
        #expect(unchanged == [.prayer], "Nothing is added once every switch is known")
    }

    @Test func everyFeatureHasCopyAndAPlace() {
        for feature in OptionalFeature.allCases {
            #expect(!feature.title.isEmpty)
            #expect(!feature.detail.isEmpty)
            #expect(!feature.systemImage.isEmpty)
        }
        let flags = FeatureFlagService(client: nil, override: [:])
        let setup = FeaturePreferences.offeredInSetup(flags: flags)
        #expect(setup.contains(.prayer))
        #expect(setup.contains(.memorise))
        #expect(!setup.contains(.moments), "Small touches live in Settings only")
        #expect(OptionalFeature.defaults == Set(OptionalFeature.allCases).subtracting([.together]))
    }

    @Test func homeScreensBelongToTheirFeature() {
        let planRoute = HomeRoute.plan(UUID())
        #expect(HomeRoute.plans.feature == .plans)
        #expect(planRoute.feature == .plans)
        #expect(HomeRoute.prayerJournal.feature == .prayer)
        #expect(HomeRoute.memorise.feature == .memorise)
        #expect(HomeRoute.insights.feature == .insights)
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
        #expect(WhatsNewCatalog.memorise.feature == .memorise)
        #expect(WhatsNewCatalog.ambientSounds.feature == .ambientSounds)
        #expect(WhatsNewCatalog.prayerJournalAndSwitches.feature == .prayer)
        #expect(WhatsNewCatalog.prayerJournalAndSwitches.flag == nil)
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
