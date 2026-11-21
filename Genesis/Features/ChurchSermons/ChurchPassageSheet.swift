import SwiftUI

/// A passage from a church's sermon, verbatim from a Bible on this device:
/// the person's own Bible first, or the one the pastor quoted (KJV, WEB,
/// ASV, RV1909, Bíblia Livre) when it's here. References are in KJV
/// numbering and go through `OriginalVersification` (the Reina-Valera
/// lands on the right verse). Closing it goes back to the same place in
/// the outline.
struct ChurchPassageSheet: View {
    let range: StudyRange
    /// The Bible the pastor quoted, if its words may be shown.
    let quoted: String?
    /// Opens the reader at the passage, in the person's own Bible.
    let onOpen: (VerseID) -> Void

    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var choice: String?

    /// A whole chapter's worth at most.
    private static let verseLimit = 60

    var body: some View {
        let options = options
        let translation = options.first { $0.id == choice } ?? options[0]
        let verses = Self.verses(range, in: library.repository(for: translation))
        NavigationStack {
            List {
                ThemedRows {
                    if options.count > 1 {
                        Section {
                            Picker("Bible", selection: Binding(get: { translation.id }, set: { choice = $0 })) {
                                ForEach(options) { Text($0.abbreviation).tag($0.id) }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("churchPassage.bible")
                        }
                    }
                    Section {
                        if verses.isEmpty {
                            Text("This passage isn't in \(translation.name).")
                                .foregroundStyle(palette.secondaryText)
                        }
                        ForEach(verses) { verse in
                            VerseSnippet(
                                reference: PassageReference(verse: verse.id).description(in: translation.language),
                                text: verse.displayText,
                                lineLimit: nil
                            )
                        }
                    } footer: {
                        Text(translation.name)
                    }
                }
            }
            .themedScreen()
            .navigationTitle(range.description(in: translation.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("churchPassage.done")
                }
                if let first = Self.verses(range, in: library.current).first {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Open in Reader", systemImage: "book") { onOpen(first.id) }
                            .accessibilityIdentifier("churchPassage.open")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The person's Bible, then the quoted one (when it's on this device and
    /// different), then the KJV when neither has the passage.
    private var options: [Translation] {
        var list = [library.currentTranslation]
        if let quoted, quoted != library.currentTranslation.id, let bible = library.translations.first(where: { $0.id == quoted }), !library.isLocked(bible) {
            list.append(bible)
        }
        if !list.contains(where: { !Self.verses(range, in: library.repository(for: $0)).isEmpty }), !list.contains(.kjv) {
            list.append(.kjv)
        }
        return list
    }

    /// The passage in a Bible's own numbering.
    static func verses(_ range: StudyRange, in repository: BibleRepository) -> [Verse] {
        let map = OriginalVersification.parallelMap(for: repository.translation)
        let own = map.ownRange(forKJV: range.start, through: range.end)
        return Array(((try? repository.verses(from: own.start, through: own.end)) ?? []).prefix(verseLimit))
    }
}
