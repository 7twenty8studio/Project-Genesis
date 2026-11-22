import SwiftUI

/// A church group's published sermons, newest first, on the group page.
/// Shown only where the church has sermons on (the server refuses the
/// list otherwise; `GroupSermons.load` gives nil and the section stays
/// away). Owners, admins and preachers publish from Church Studio on the web.
struct GroupSermonsSection: View {
    let group: GroupSummary
    let sermons: [ChurchSermonSummary]

    @Environment(\.palette) private var palette
    @State private var showsAll = false

    /// Rows before Show All.
    private static let shelf = 3

    var body: some View {
        Section {
            if sermons.isEmpty {
                Text("Sermons you publish in Church Studio appear here.")
                    .foregroundStyle(palette.secondaryText)
            }
            ForEach(showsAll ? sermons : Array(sermons.prefix(Self.shelf))) { sermon in
                NavigationLink(value: TogetherRoute.sermon(sermon.slug)) {
                    ChurchSermonRow(sermon: sermon)
                }
                .accessibilityIdentifier("groupSermons.row")
            }
            if sermons.count > Self.shelf {
                Button(showsAll ? String(localized: "Show less") : String(localized: "Show all \(sermons.count)")) { showsAll.toggle() }
                    .buttonStyle(.borderless)
            }
            if Self.writes(group) {
                Link(destination: ChurchSermonLink.studio(church: group.id)) {
                    Label("Open in Church Studio", systemImage: "safari")
                }
                .font(.footnote)
            }
        } header: {
            Text("Sermons")
        }
        .listRowBackground(palette.surface)
    }

    /// Whether the section shows: a church's members see it once it has
    /// a sermon, its owner, admins and preachers straight away.
    static func shows(_ sermons: [ChurchSermonSummary]?, group: GroupSummary) -> Bool {
        guard let sermons else { return false }
        return !sermons.isEmpty || writes(group)
    }

    /// The owner, admins and preachers write sermons in Church Studio.
    static func writes(_ group: GroupSummary) -> Bool {
        group.role == .leader || group.isPreacher
    }
}

/// Loads a group's sermons for its page.
enum GroupSermons {
    /// nil when the group isn't a church with sermons on (or is hidden).
    @MainActor
    static func load(_ group: UUID, backend: any ChurchSermonBackend, hidden: HiddenChurches) async -> [ChurchSermonSummary]? {
        guard !hidden.isHidden(group) else { return nil }
        return try? await backend.archive(group: group)
    }
}

/// A sermon in a list: title, speaker and date, and whether it's for members.
struct ChurchSermonRow: View {
    let sermon: ChurchSermonSummary

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(sermon.title.isEmpty ? String(localized: "Sermon") : sermon.title)
                .font(.body.weight(.medium))
                .foregroundStyle(palette.text)
            let date = sermon.preachedDate?.formatted(date: .abbreviated, time: .omitted)
            let line = [sermon.speaker.isEmpty ? nil : sermon.speaker, date, sermon.series].compactMap { $0 }.joined(separator: " \u{00B7} ")
            if !line.isEmpty {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            if sermon.audience == .members {
                Label("Members only", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
