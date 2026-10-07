import SwiftUI

/// A screen pushed on Home (or in the reader's side panel). A feature the
/// person has switched off (reached from a widget, notification or link)
/// shows a short note with its switch instead of the hidden screen.
struct HomeRouteDestination: View {
    let route: HomeRoute

    @Environment(FeaturePreferences.self) private var features
    @Environment(EntitlementService.self) private var entitlements

    var body: some View {
        if let feature = route.feature, !features.isOn(feature) {
            FeatureOffView(feature: feature)
        } else {
            switch route {
            case .plans: PlansView()
            case let .plan(id): PlanDetailView(enrollmentID: id)
            case .prayerJournal: PrayerJournalView()
            case .insights: InsightsView()
            case .sermons: SermonsView()
            case .memorise:
                if entitlements.allows(.memorise) {
                    MemoriseView()
                } else {
                    PremiumView(highlighted: .memorise)
                }
            }
        }
    }
}

extension HomeRoute {
    /// The optional feature this screen belongs to.
    var feature: OptionalFeature? {
        switch self {
        case .plans, .plan: .plans
        case .prayerJournal: .prayer
        case .insights: .insights
        case .memorise: .memorise
        case .sermons: .sermons
        }
    }
}

/// "Prayer Journal is turned off", with its switch. Nothing was deleted.
struct FeatureOffView: View {
    let feature: OptionalFeature

    @Environment(FeaturePreferences.self) private var features
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 18) {
            QuietEmptyState(
                systemImage: feature.systemImage,
                title: String(localized: "\(feature.title) is turned off"),
                message: String(localized: "You chose to hide this in Settings › Features. Nothing was deleted; turn it on to pick up where you left off.")
            )
            Button {
                features.set(feature, on: true)
            } label: {
                Label("Turn On \(feature.title)", systemImage: "plus.circle")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .accessibilityIdentifier("featureOff.turnOn")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedScreen()
        .navigationTitle(feature.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
