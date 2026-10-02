import SwiftUI

/// Study notes for the chapter being read, beside the text ("Bible +
/// Commentary" on iPad and an open iPhone Duo).
struct ChapterStudyPanel: View {
    let chapter: ChapterID

    @Environment(BibleLibrary.self) private var library

    var body: some View {
        let last = (try? library.current.chapter(chapter))?.verses.last?.id.verse ?? 1
        ScrollView {
            StudyAssistantContent(
                passage: StudyPassage(chapter: chapter, lastVerse: last),
                initialAction: .explain,
                showsScripture: false,
                autoLoads: false
            )
            .id(chapter)
            .padding(16)
        }
        .themedScreen()
    }
}

/// Who, where and what happens in the chapter being read ("Bible + Timeline").
struct ChapterContextView: View {
    let chapter: ChapterID

    @Environment(\.studyData) private var studyData
    @Environment(EntitlementService.self) private var entitlements
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @State private var premium: PremiumFeature?

    var body: some View {
        ScrollView {
            if let studyData, entitlements.allows(.historicalContent) {
                content(studyData)
                    .padding(16)
            } else {
                locked.padding(16)
            }
        }
        .themedScreen()
        .premiumSheet($premium)
    }

    @ViewBuilder
    private func content(_ studyData: StudyRepository) -> some View {
        let events = (try? studyData.events(inChapter: chapter)) ?? []
        let people = (try? studyData.people(inChapter: chapter, limit: 24)) ?? []
        let places = (try? studyData.places(inChapter: chapter, limit: 24)) ?? []
        VStack(alignment: .leading, spacing: 22) {
            Text(chapter.description)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(palette.text)
            if events.isEmpty && people.isEmpty && places.isEmpty {
                Text("No people, places or events are recorded for this chapter.")
                    .foregroundStyle(palette.secondaryText)
            }
            if !events.isEmpty {
                DetailSection(title: String(localized: "Events")) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(events) { event in
                            Button { router.explore(.event(event.id)) } label: { EventRow(event: event) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !places.isEmpty {
                DetailSection(title: String(localized: "Places")) {
                    PlacesMap(places: places)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    ChipFlow(items: places, title: \.name) { router.explore(.place($0.id)) }
                }
            }
            if !people.isEmpty {
                DetailSection(title: String(localized: "People")) {
                    ChipFlow(items: people, title: \.name) { router.explore(.person($0.id)) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("context.panel")
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("People, places and events in this chapter, with maps and the timeline.")
                .foregroundStyle(palette.secondaryText)
            Button("Unlock with Premium") { premium = .historicalContent }
                .buttonStyle(.borderedProminent)
        }
    }
}
