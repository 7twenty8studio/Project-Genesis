import SwiftUI

/// Everyone named in the Bible, searchable; the best known first.
struct PeopleBrowser: View {
    @Environment(\.studyData) private var studyData
    @Environment(\.palette) private var palette
    @State private var query = ""
    @State private var people: [PersonSummary] = []

    var body: some View {
        List(people) { person in
            NavigationLink(value: ExploreRoute.person(person.id)) {
                PersonRow(person: person)
            }
            .listRowBackground(palette.surface)
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a person")
        .overlay {
            if people.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .task(id: query) {
            // A short pause so typing doesn't query on every keystroke.
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(150)) }
            guard !Task.isCancelled else { return }
            guard let studyData else { return }
            let text = query
            let found = await Task.detached(priority: .userInitiated) {
                (try? studyData.searchPeople(text, limit: text.isEmpty ? 100 : 60)) ?? []
            }.value
            guard !Task.isCancelled else { return }
            people = found
        }
        .accessibilityIdentifier("people.list")
    }
}

struct PersonRow: View {
    let person: PersonSummary
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(person.name)
                .foregroundStyle(palette.text)
            HStack(spacing: 6) {
                if !person.alsoCalled.isEmpty {
                    Text("Also \(person.alsoCalled)")
                        .lineLimit(1)
                }
                Text(person.verseCount == 1 ? "1 verse" : "\(person.verseCount) verses")
            }
            .font(.caption)
            .foregroundStyle(palette.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One person: biography, family tree, timeline, books, verses and places.
struct PersonDetailView: View {
    let personID: Int

    @Environment(\.studyData) private var studyData
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette

    @State private var loaded: Loaded?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let loaded {
                let person = loaded.person
                let family = loaded.family
                let events = loaded.events
                let books = loaded.books
                let verses = loaded.verses
                let places = loaded.places
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header(person)
                    if !person.biography.isEmpty {
                        DetailSection(title: String(localized: "Biography")) { DictionaryText(text: person.biography) }
                    }
                    if !family.isEmpty {
                        DetailSection(title: String(localized: "Family Tree")) { FamilyTreeView(person: person.summary, family: family) }
                    }
                    if !events.isEmpty {
                        DetailSection(title: String(localized: "Timeline")) {
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
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            ChipFlow(items: places, title: \.name) { router.explore(.place($0.id)) }
                        }
                    }
                    if !books.isEmpty {
                        DetailSection(title: String(localized: "Books")) {
                            ChipFlow(items: books, title: { "\($0.book.name) \u{00B7} \($0.count)" }) { router.read($0.firstVerse) }
                        }
                        .accessibilityIdentifier("person.books")
                    }
                    if !verses.isEmpty {
                        DetailSection(title: String(localized: "Verses")) { VerseMentionList(verses: verses) }
                    }
                    Text(StudyRepository.attribution)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(20)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .themedScreen()
            .navigationTitle(person.name)
            .navigationBarTitleDisplayMode(.inline)
            } else if didLoad {
                StudyDataMissingView()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themedScreen()
            }
        }
        // Read once, off the main thread: these queries used to run on every
        // redraw, which made Explore feel slow.
        .task(id: personID) { await load() }
    }

    private struct Loaded: Sendable {
        let person: Person
        let family: Family
        let events: [TimelineEvent]
        let books: [BookMentions]
        let verses: [VerseID]
        let places: [PlaceSummary]
    }

    private func load() async {
        guard let studyData else {
            didLoad = true
            return
        }
        let id = personID
        loaded = await Task.detached(priority: .userInitiated) { () -> Loaded? in
            guard let person = try? studyData.person(id: id) else { return nil }
            return Loaded(
                person: person,
                family: (try? studyData.family(ofPerson: id)) ?? Family(),
                events: (try? studyData.events(forPerson: id)) ?? [],
                books: (try? studyData.books(forPerson: id)) ?? [],
                verses: (try? studyData.verses(forPerson: id)) ?? [],
                places: (try? studyData.places(forPerson: id)) ?? []
            )
        }.value
        didLoad = true
    }

    private func header(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(person.name)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(palette.text)
                .accessibilityIdentifier("person.name")
            let details = [
                person.summary.alsoCalled.isEmpty ? nil : String(localized: "Also called \(person.summary.alsoCalled)"),
                person.group.isEmpty ? nil : person.group,
                person.lifespan,
            ].compactMap { $0 }
            ForEach(details, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
            if let first = person.firstVerse {
                Button {
                    router.read(first)
                } label: {
                    Label("First mentioned in \(PassageReference(verse: first).description)", systemImage: "book")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 4)
            }
        }
    }
}

/// Parents above, the person and spouses in the middle, children below,
/// siblings alongside. Tap anyone to go to their page.
struct FamilyTreeView: View {
    let person: PersonSummary
    let family: Family

    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if !family.parents.isEmpty {
                generation(String(localized: "Parents"), family.parents)
                connector
            }
            // The person on their own line (never squeezed letter by letter),
            // with husbands or wives wrapping underneath.
            Text(person.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(palette.background)
                .background(palette.accent, in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
            if !family.partners.isEmpty {
                VStack(spacing: 6) {
                    Label("Spouses", systemImage: "heart")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                    FlowLayout(spacing: 6) {
                        ForEach(family.partners) { chip($0) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            }
            if !family.children.isEmpty {
                connector
                generation(String(localized: "Children"), family.children)
            }
            if !family.siblings.isEmpty {
                generation(String(localized: "Siblings"), family.siblings)
                    .padding(.top, 18)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("person.familyTree")
    }

    private var connector: some View {
        Rectangle()
            .fill(palette.separator)
            .frame(width: 1.5, height: 18)
    }

    private func generation(_ title: String, _ people: [PersonSummary]) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
            FlowLayout(spacing: 6) {
                ForEach(people) { chip($0) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(_ relative: PersonSummary) -> some View {
        Button(relative.name) { router.explore(.person(relative.id)) }
            .font(.subheadline)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(palette.text)
            .background(palette.background, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.separator))
            .buttonStyle(.plain)
    }
}
