import SwiftUI

/// One topic: its headings and the passages under each, with verse text
/// from the reader's Bible. Tap a passage to open it.
struct TopicDetailView: View {
    let topicID: Int
    let onOpen: (VerseID) -> Void

    @Environment(\.topics) private var topics
    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette
    @State private var topic: Topic?
    @State private var shownID: Int?

    var body: some View {
        List {
            ThemedRows {
                if let topic {
                    ForEach(topLevel(topic)) { entry in
                        Section {
                            passages(entry)
                            ForEach(children(of: entry, in: topic)) { child in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(child.label)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(palette.text)
                                    passages(child)
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Text(entry.label)
                        }
                        .listRowBackground(palette.surface)
                    }
                    if !topic.seeAlso.isEmpty {
                        Section("See also") {
                            ForEach(topic.seeAlso) { other in
                                Button(other.name) { shownID = other.id }
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        .listRowBackground(palette.surface)
                    }
                    Section {
                    } footer: {
                        Text("Verses from the \(library.currentTranslation.abbreviation). \(TopicRepository.attribution)")
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .themedScreen()
        .navigationTitle(topic?.summary.name ?? String(localized: "Topic"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: shownID ?? topicID) {
            topic = try? topics?.topic(id: shownID ?? topicID)
        }
        .accessibilityIdentifier("topic.detail")
    }

    private func topLevel(_ topic: Topic) -> [TopicEntry] {
        topic.entries.filter { $0.parentID == nil }
    }

    private func children(of entry: TopicEntry, in topic: Topic) -> [TopicEntry] {
        topic.entries.filter { $0.parentID == entry.id }
    }

    @ViewBuilder
    private func passages(_ entry: TopicEntry) -> some View {
        ForEach(entry.passages.prefix(30)) { passage in
            TopicPassageRow(passage: passage, onOpen: onOpen)
        }
        if entry.passages.count > 30 {
            Text("And \(entry.passages.count - 30) more")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
    }
}

/// A passage under a topic: the reference and its first verse.
private struct TopicPassageRow: View {
    let passage: TopicPassage
    let onOpen: (VerseID) -> Void

    @Environment(BibleLibrary.self) private var library

    var body: some View {
        Button {
            onOpen(passage.start)
        } label: {
            VerseSnippet(
                reference: passage.reference.description,
                text: (try? library.current.verse(passage.start))?.plainText ?? "",
                lineLimit: 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("topic.passage")
    }
}

extension EnvironmentValues {
    /// The topical index (nil if Topics.sqlite is missing from the build).
    @Entry var topics: TopicRepository? = nil
}
