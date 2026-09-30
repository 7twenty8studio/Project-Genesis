import SwiftUI

/// The Explore tab: the Bible timeline, maps and people (Genesis Premium).
struct ExploreView: View {
    enum Section: String, CaseIterable, Identifiable {
        case timeline, map, people
        var id: String { rawValue }
        var title: String {
            switch self {
            case .timeline: "Timeline"
            case .map: "Map"
            case .people: "People"
            }
        }
    }

    @Environment(AppRouter.self) private var router
    @Environment(EntitlementService.self) private var entitlements
    @Environment(\.studyData) private var studyData
    @Environment(\.palette) private var palette
    @State private var section: Section = .timeline

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.explorePath) {
            Group {
                if studyData == nil {
                    StudyDataMissingView()
                } else if !entitlements.allows(.historicalContent) {
                    ExploreLockedView()
                } else {
                    switch section {
                    case .timeline: TimelineBrowser()
                    case .map: BibleMapView()
                    case .people: PeopleBrowser()
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if studyData != nil && entitlements.allows(.historicalContent) {
                    Picker("Explore", selection: $section) {
                        ForEach(Section.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("explore.section")
                }
            }
            .themedScreen()
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ExploreRoute.self) { ExploreDestination(route: $0) }
        }
    }
}

/// What free accounts see: a preview of the eras and the way to unlock.
private struct ExploreLockedView: View {
    @Environment(\.studyData) private var studyData
    @Environment(\.palette) private var palette
    @State private var premium: PremiumFeature?

    var body: some View {
        let eras = (try? studyData?.eras()) ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "map")
                        .font(.title)
                        .foregroundStyle(palette.accent)
                    Text("Walk through the story of Scripture")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text("An interactive timeline from Creation to Revelation, Bible maps with Paul's journeys and the Exodus, and more than 3,000 people with family trees and every verse that mentions them.")
                        .foregroundStyle(palette.secondaryText)
                }
                FlowLayout(spacing: 8) {
                    ForEach(eras) { era in
                        Text(era.title)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(palette.secondaryText)
                            .background(palette.surface, in: Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
                Button {
                    premium = .historicalContent
                } label: {
                    Label("Unlock with Premium", systemImage: "lock.open")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("explore.unlock")
            }
            .padding(20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .premiumSheet($premium)
    }
}
