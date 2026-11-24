import Foundation
import Testing
@testable import Genesis

@Suite("Feedback, grants and Bible-language names")
@MainActor
struct OctoberUpdateTests {
    @Test func testSwitchUnlocksPremiumInDevelopmentBuilds() throws {
        let defaults = try #require(UserDefaults(suiteName: "entitlements-\(UUID())"))
        let entitlements = EntitlementService(defaults: defaults)
        #expect(!entitlements.isPremium)
        #if DEBUG
        entitlements.isTestingPremium = true
        #expect(entitlements.isPremium)
        entitlements.isTestingPremium = false
        #expect(!entitlements.isPremium)
        #endif
    }

    @Test func uiTestOverrideIgnoresTheTestSwitch() throws {
        let defaults = try #require(UserDefaults(suiteName: "entitlements-\(UUID())"))
        let entitlements = EntitlementService(defaults: defaults, override: false)
        #if DEBUG
        entitlements.isTestingPremium = true
        #endif
        #expect(!entitlements.isPremium)
    }

    @Test func aSavedGrantEndsOnItsDateWithoutTheServer() throws {
        let defaults = try #require(UserDefaults(suiteName: "entitlements-\(UUID())"))
        defaults.set(true, forKey: "premium.grant")
        defaults.set(Date.now.addingTimeInterval(-60).timeIntervalSince1970, forKey: "premium.grantEnds")
        let ended = EntitlementService(defaults: defaults)
        #expect(!ended.hasGrant)
        #expect(!ended.isPremium)
    }

    @Test func aSavedGrantStillRunningKeepsPremiumOffline() throws {
        let defaults = try #require(UserDefaults(suiteName: "entitlements-\(UUID())"))
        let end = Date.now.addingTimeInterval(86_400)
        defaults.set(true, forKey: "premium.grant")
        defaults.set(end.timeIntervalSince1970, forKey: "premium.grantEnds")
        let running = EntitlementService(defaults: defaults)
        let shownEnd = try #require(running.grantExpiresAt)
        #expect(running.isPremium)
        #expect(abs(shownEnd.timeIntervalSince(end)) < 1)
    }

    @Test func aPermanentSavedGrantKeepsPremium() throws {
        let defaults = try #require(UserDefaults(suiteName: "entitlements-\(UUID())"))
        defaults.set(true, forKey: "premium.grant")
        let forever = EntitlementService(defaults: defaults)
        #expect(forever.isPremium)
        #expect(forever.grantExpiresAt == nil)
    }

    @Test func referencesCanUseTheBiblesLanguage() {
        let mark5 = ChapterID(book: 41, chapter: 5)
        #expect(mark5.description(in: "en") == "Mark 5")
        #expect(mark5.description(in: "es") == "Marcos 5")
        let reference = PassageReference(verse: VerseID(book: 43, chapter: 3, verse: 16))
        #expect(reference.description(in: "es") == "Juan 3:16")
    }

    @Test func everyFeedbackCategoryIsAllowedByTheDatabase() {
        // Must match the check constraint in 20261007000000_feedback_and_grants.sql.
        #expect(Set(FeedbackCategory.allCases.map(\.rawValue)) == ["bug", "idea", "question", "scripture", "other"])
    }
}
