import SwiftUI

/// The Explore tab: the Bible timeline and people (free), and maps and
/// journeys (Genesis Premium; free accounts see a preview).
struct ExploreView: View {
    enum Section: String, CaseIterable, Identifiable {
        case timeline, map, people
        var id: String { rawValue }
        var title: String {
            switch self {
            case .timeline: String(localized: "Timeline")
            case .map: String(localized: "Map")
            case .people: String(localized: "People")
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
                } else {
                    switch section {
                    case .timeline: TimelineBrowser()
                    case .map:
                        if entitlements.allows(.historicalContent) {
                            BibleMapView()
                        } else {
                            MapLockedView()
                        }
                    case .people: PeopleBrowser()
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if studyData != nil {
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

/// What free accounts see on the Map: a preview of the journeys and the way
/// to unlock. The timeline and people are free.
private struct MapLockedView: View {
    @Environment(\.studyData) private var studyData
    @Environment(\.palette) private var palette
    @State private var premium: PremiumFeature?
    @State private var journeys: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "map")
                        .font(.title)
                        .foregroundStyle(palette.accent)
                    Text("Walk the lands of the Bible")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text("With Premium, explore 1,250 places on the map and follow Paul's journeys and the Exodus step by step.")
                        .foregroundStyle(palette.secondaryText)
                }
                FlowLayout(spacing: 8) {
                    ForEach(journeys, id: \.self) { journey in
                        Text(journey)
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
        .task {
            journeys = ((try? studyData?.routes()) ?? []).map(\.title)
        }
    }
}
