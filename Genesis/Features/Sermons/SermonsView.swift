import SwiftData
import SwiftUI

/// Sermon Notes pushed from Home (the Sunday card or a genesis://sermons link).
/// In the Library the same list is a shelf beside Notes.
struct SermonsView: View {
    var body: some View {
        SermonsList()
            .navigationTitle("Sermon Notes")
    }
}

/// Every sermon, by date (this week, then by month) or by church, with a
/// favourites filter and search. Free for everyone, with no limits.
struct SermonsList: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Query(sort: \Sermon.preachedAt, order: .reverse) private var sermons: [Sermon]
    @AppStorage("sermons.grouping") private var groupingRaw = SermonGrouping.Mode.date.rawValue
    @State private var favouritesOnly = false
    @State private var query = ""
    @State private var editing: Sermon?

    private var mode: SermonGrouping.Mode {
        SermonGrouping.Mode(rawValue: groupingRaw) ?? .date
    }

    var body: some View {
        let byID = Dictionary(sermons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let visible = SermonGrouping.visible(sermons.map(\.facts), query: query, favouritesOnly: favouritesOnly)
        let sections = SermonGrouping.sections(visible, mode: mode)
        List {
            ThemedRows {
                SermonListControls(groupingRaw: $groupingRaw, favouritesOnly: $favouritesOnly)
                if sections.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.sermons) { facts in
                            if let sermon = byID[facts.id] {
                                row(sermon)
                            }
                        }
                        .onDelete { offsets in
                            let store = StudyStore(context: modelContext)
                            offsets.compactMap { byID[section.sermons[$0].id] }.forEach { store.delete($0) }
                        }
                    } header: {
                        Text(SermonSectionTitle.title(for: section.kind))
                    }
                }
            }
        }
        .themedScreen()
        .searchable(text: $query, prompt: "Search sermons")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = StudyStore(context: modelContext).createSermon()
                } label: {
                    Label("New Sermon Notes", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("sermons.new")
            }
        }
        .sheet(item: $editing) { sermon in
            NavigationStack { SermonEditorView(sermon: sermon) }
        }
    }

    private func row(_ sermon: Sermon) -> some View {
        Button {
            editing = sermon
        } label: {
            SermonRow(sermon: sermon)
        }
        .listRowBackground(palette.surface)
        .swipeActions(edge: .leading) {
            Button(sermon.isFavourite ? "Remove Favourite" : "Favourite", systemImage: sermon.isFavourite ? "star.slash" : "star") {
                StudyStore(context: modelContext).toggleFavourite(sermon)
            }
            .tint(palette.accent)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            QuietEmptyState(
                systemImage: "magnifyingglass",
                title: String(localized: "No matching sermons"),
                message: String(localized: "Try a word from the title, the preacher, the church or your notes.")
            )
        } else if favouritesOnly {
            QuietEmptyState(
                systemImage: "star",
                title: String(localized: "No favourite sermons yet"),
                message: String(localized: "Tap the star on a sermon you want to come back to.")
            )
        } else {
            QuietEmptyState(
                systemImage: "building.columns",
                title: String(localized: "No sermon notes yet"),
                message: String(localized: "Take notes during the sermon, with the verses beside them. Turn on Church Mode for a dim, quiet screen.")
            )
        }
    }
}

/// Group by date or church, and the favourites filter.
private struct SermonListControls: View {
    @Binding var groupingRaw: String
    @Binding var favouritesOnly: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        Section {
            Picker("Group By", selection: $groupingRaw) {
                Text("By Date", comment: "Sermon list grouping").tag(SermonGrouping.Mode.date.rawValue)
                Text("By Church", comment: "Sermon list grouping").tag(SermonGrouping.Mode.church.rawValue)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("sermons.grouping")

            Button {
                favouritesOnly.toggle()
            } label: {
                Label("Favourites", systemImage: favouritesOnly ? "star.fill" : "star")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(favouritesOnly ? palette.background : palette.text)
                    .background(favouritesOnly ? palette.accent : palette.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(favouritesOnly ? .isSelected : [])
            .accessibilityIdentifier("sermons.favourites")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }
}

/// Section headings for the sermon list.
enum SermonSectionTitle {
    static func title(for kind: SermonGrouping.Section.Kind) -> String {
        switch kind {
        case .thisWeek: String(localized: "This Week", comment: "Sermon list section: sermons from this week")
        case let .month(start): start.formatted(.dateTime.month(.wide).year())
        case let .church(name): name
        case .noChurch: String(localized: "No Church Added", comment: "Sermon list section: sermons without a church")
        }
    }
}

/// One sermon in the list.
struct SermonRow: View {
    let sermon: Sermon
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(sermon.preachedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                if !sermon.church.isEmpty {
                    Text(verbatim: "\u{00B7}")
                    Text(sermon.church)
                        .lineLimit(1)
                }
                Spacer()
                if !sermon.passages.isEmpty {
                    Image(systemName: "book.closed")
                        .accessibilityLabel("Has Bible passages")
                }
                if sermon.isFavourite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(palette.accent)
                        .accessibilityLabel("Favourite")
                }
            }
            .font(.caption)
            .foregroundStyle(palette.secondaryText)

            Text(sermon.displayTitle)
                .font(.headline)
                .foregroundStyle(palette.text)
                .lineLimit(2)
            if let byline {
                Text(byline)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// "Pastor Ruth · Grace in Galatians"
    private var byline: String? {
        let parts = [sermon.preacher, sermon.series ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }
}
