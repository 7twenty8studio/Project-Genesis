import Foundation
import Testing
@testable import Genesis

/// A first launch in Spanish offers, and chooses, a Spanish Bible.
@Suite("Onboarding Bibles")
struct OnboardingBiblesTests {
    private static func item(_ id: String, language: String, premium: Bool = false, youVersionID: Int? = nil) -> DownloadableTranslation {
        DownloadableTranslation(id: id, name: id, year: "1909", license: "Public domain", summary: "",
                                fileURL: "", fileBytes: 4_000_000, databaseBytes: 0, sha256: "", version: 1,
                                language: language, premium: premium, youVersionID: youVersionID)
    }

    private static let catalog = [
        item("NVI", language: "es", youVersionID: 128),
        item("LBLA", language: "es", premium: true),
        item("RV1909", language: "es"),
        item("BSB", language: "en"),
    ]

    @Test func spanishPutsAFreeSpanishDownloadFirstAndChoosesIt() {
        let options = OnboardingBibles.options(installed: Translation.bundled, catalog: Self.catalog, language: "es")
        #expect(options.map(\.id) == ["RV1909", "KJV", "WEB", "ASV"])
        #expect(options.first?.download?.id == "RV1909")
        #expect(OnboardingBibles.suggested(current: .kjv, options: options, language: "es").id == "RV1909")
    }

    @Test func englishKeepsTheBundledBiblesAndTheCurrentOne() {
        let options = OnboardingBibles.options(installed: Translation.bundled, catalog: Self.catalog, language: "en")
        #expect(options.map(\.id) == ["KJV", "WEB", "ASV", "BSB"])
        #expect(OnboardingBibles.suggested(current: .kjv, options: options, language: "en").id == "KJV")
    }

    @Test func offlineSpanishStaysWithTheBundledBible() {
        let options = OnboardingBibles.options(installed: Translation.bundled, catalog: [], language: "es")
        #expect(options.allSatisfy { $0.download == nil })
        #expect(OnboardingBibles.suggested(current: .kjv, options: options, language: "es").id == "KJV")
    }

    @Test func aSpanishBibleAlreadyOnTheDeviceIsNotDownloadedAgain() {
        let rv = Self.item("RV1909", language: "es").translation
        let options = OnboardingBibles.options(installed: Translation.bundled + [rv], catalog: Self.catalog, language: "es")
        #expect(options.first?.id == "RV1909")
        #expect(options.first?.download == nil)
        #expect(options.filter { $0.id == "RV1909" }.count == 1)
    }
}
