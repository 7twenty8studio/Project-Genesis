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
        #expect(available == [.automatic, .paper, .sepia, .slate, .highContrast, .night])
        #expect(!free.allows(.morningWelcome))
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

@Suite("Premium plans")
struct PremiumPlanTests {
    @Test func everyPlanAndPeriodHasItsOwnProduct() {
        #expect(PremiumProduct.product(.individual, yearly: true) == .yearly)
        #expect(PremiumProduct.product(.individual, yearly: false) == .monthly)
        #expect(PremiumProduct.product(.family, yearly: true) == .familyYearly)
        #expect(PremiumProduct.product(.family, yearly: false) == .familyMonthly)
        #expect(PremiumProduct.ids.count == 4)
        for product in PremiumProduct.allCases {
            #expect(PremiumProduct.product(product.plan, yearly: product.isYearly) == product)
        }
    }

    @Test func familyCostsMoreThanIndividual() {
        #expect(PremiumProduct.familyMonthly.fallbackPrice == "$12.99")
        #expect(PremiumProduct.familyYearly.fallbackPrice == "$99.99")
        #expect(PremiumProduct.monthly.fallbackPrice == "$7.99")
    }
}
