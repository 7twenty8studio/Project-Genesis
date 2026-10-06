import Foundation
import SwiftData
import Testing
@testable import Genesis

@Suite("Premium limits")
@MainActor
struct PremiumTests {
    private func service(premium: Bool) -> EntitlementService {
        EntitlementService(defaults: UserDefaults(suiteName: "PremiumTests-\(UUID())")!, override: premium)
    }

    @Test func freeAccountsGetTheEssentials() {
        let free = service(premium: false)
        // Notes, highlights, prayers and reading plans have no limits or gates;
        // these are the Premium extras.
        #expect(!free.allows(.advancedSearch))
        #expect(!free.allows(.widgets))
        #expect(!free.allows(.readingInsights))
    }

    @Test func premiumHasEverything() {
        let premium = service(premium: true)
        let allowed = PremiumFeature.allCases.filter { premium.allows($0) }
        #expect(allowed.count == PremiumFeature.allCases.count)
    }

    @Test func freeThemesStayAvailable() {
        let free = service(premium: false)
        let available = ReaderTheme.allCases.filter { free.allows($0) }
        #expect(available == [.automatic, .paper, .sepia, .slate, .highContrast])
        #expect(!free.allows(.cloudBackup))
        #expect(!free.allows(.historicalContent))
    }

    @Test func emptyNotesDontCountTowardTheLimit() throws {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = StudyStore(context: container.mainContext)
        store.createNote(kind: .text, anchor: .none)
        store.createNote(kind: .text, anchor: .none, title: "Grace")
        #expect(store.noteCount() == 1)
    }
}
