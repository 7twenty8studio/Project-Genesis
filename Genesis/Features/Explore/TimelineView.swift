import SwiftUI

/// The interactive Bible timeline: eras from Creation to Revelation, with the
/// events of each. Tap an era to jump to it, an event for its details.
struct TimelineBrowser: View {
    @Environment(\.studyData) private var studyData
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @State private var eras: [Era] = []
    @State private var events: [String: [TimelineEvent]] = [:]

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                eraStrip(proxy)
                List {
                    Text(StudyRepository.chronologyNote)
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .listRowBackground(Color.clear)
                    ForEach(eras) { era in
                        Section {
                            eraHeader(era)
                                .listRowBackground(palette.surface)
                                // A List scrolls to rows, not sections, so the era chips target this row.
                                .id(era.id)
                            ForEach(events[era.id] ?? []) { event in
                                NavigationLink(value: ExploreRoute.event(event.id)) {
                                    EventRow(event: event)
                                }
                                .listRowBackground(palette.surface)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("timeline.list")
            }
        }
        .task { load() }
    }

    private func eraStrip(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(eras) { era in
                    Button(era.title) {
                        withAnimation { proxy.scrollTo(era.id, anchor: .top) }
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(palette.text)
                    .background(palette.surface, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("timeline.era.\(era.id)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func eraHeader(_ era: Era) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(era.title)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(palette.text)
                Spacer()
                if let range = yearRange(era) {
                    Text(range)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            Text(era.summary)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
            Button {
                router.read(era.firstVerse)
            } label: {
                Label("Read \(PassageReference(verse: era.firstVerse).chapterID.description)", systemImage: "book")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("timeline.read.\(era.id)")
        }
        .padding(.vertical, 6)
    }

    private func yearRange(_ era: Era) -> String? {
        guard era.isDated else { return nil }
        let years = (events[era.id] ?? []).compactMap(\.year)
        guard let first = years.min(), let last = years.max() else { return nil }
        return first == last ? TimelineEvent.label(forYear: first) : "\(TimelineEvent.label(forYear: first)) – \(TimelineEvent.label(forYear: last))"
    }

    private func load() {
        guard eras.isEmpty, let studyData else { return }
        eras = (try? studyData.eras()) ?? []
        for era in eras {
            events[era.id] = (try? studyData.events(inEra: era.id)) ?? []
        }
    }
}

struct EventRow: View {
    let event: TimelineEvent
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(palette.accent)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .foregroundStyle(palette.text)
                HStack(spacing: 6) {
                    if let year = event.yearLabel { Text(year) }
                    if let reference = event.reference { Text(reference.description) }
                }
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One event: when, where, who, and the chapters that tell it.
struct EventDetailView: View {
    let eventID: Int

    @Environment(\.studyData) private var studyData
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette

    var body: some View {
        if let studyData, let event = try? studyData.event(id: eventID) {
            let chapters = (try? studyData.chapters(forEvent: eventID)) ?? []
            let people = (try? studyData.people(inEvent: eventID)) ?? []
            let places = (try? studyData.places(inEvent: eventID)) ?? []
            let eraTitle = ((try? studyData.eras()) ?? []).first { $0.id == event.eraID }?.title
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.title)
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .accessibilityIdentifier("event.title")
                        Text([eraTitle, event.yearLabel].compactMap { $0 }.joined(separator: " \u{00B7} "))
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                    }
                    if !chapters.isEmpty {
                        DetailSection(title: "Read") {
                            ChipFlow(items: chapters.map(IdentifiedChapter.init), title: { $0.chapter.description }) { item in
                                router.read(item.chapter)
                            }
                        }
                    }
                    if !people.isEmpty {
                        DetailSection(title: "People") {
                            ChipFlow(items: people, title: \.name) { router.explore(.person($0.id)) }
                        }
                    }
                    let mapped = places.filter(\.isMapped)
                    if !places.isEmpty {
                        DetailSection(title: "Places") {
                            if !mapped.isEmpty {
                                PlacesMap(places: mapped)
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            ChipFlow(items: places, title: \.name) { router.explore(.place($0.id)) }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .themedScreen()
            .navigationTitle(event.yearLabel ?? "Event")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            StudyDataMissingView()
        }
    }
}

private struct IdentifiedChapter: Identifiable {
    let chapter: ChapterID
    var id: ChapterID { chapter }
}
