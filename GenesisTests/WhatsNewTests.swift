import Foundation
import Testing
@testable import Genesis

@Suite("What's New")
@MainActor
struct WhatsNewTests {
    private let shipped = WhatsNewAnnouncement(id: "shipped", title: "Shipped", items: [])
    private let switched = WhatsNewAnnouncement(id: "switched", title: "Switched", items: [], flag: .studyAssistant)

    private func make(_ defaults: UserDefaults) -> WhatsNewService {
        WhatsNewService(catalog: [shipped, switched], defaults: defaults)
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "WhatsNewTests-\(UUID())")!
    }

    @Test func switchedFeaturesWaitForTheirSwitch() {
        let service = make(freshDefaults())
        let off = FeatureFlagService(client: nil, override: [.studyAssistant: false])
        let on = FeatureFlagService(client: nil, override: [.studyAssistant: true])
        #expect(service.pending(flags: off).map(\.id) == ["shipped"])
        #expect(service.pending(flags: on).map(\.id) == ["switched", "shipped"], "Newest first")
    }

    @Test func eachIsShownOnce() {
        let defaults = freshDefaults()
        let on = FeatureFlagService(client: nil, override: [.studyAssistant: true])
        let service = make(defaults)
        service.markSeen(service.pending(flags: on))
        #expect(service.pending(flags: on).isEmpty)
        let relaunched = make(defaults)
        #expect(relaunched.pending(flags: on).isEmpty, "Remembered across launches")
    }

    @Test func newInstallsSkipShippedFeaturesButNotSwitchedOnes() {
        let service = make(freshDefaults())
        service.markShippedFeaturesSeen()
        let on = FeatureFlagService(client: nil, override: [.studyAssistant: true])
        #expect(service.pending(flags: on).map(\.id) == ["switched"])
    }

    @Test func switchedOffInUITests() {
        let service = WhatsNewService(catalog: [shipped], defaults: freshDefaults(), isEnabled: false)
        #expect(service.pending(flags: FeatureFlagService(client: nil, override: [:])).isEmpty)
    }

    @Test func catalogIDsAreUnique() {
        let ids = WhatsNewCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(WhatsNewCatalog.studyAssistant.flag == .studyAssistant)
    }
}
