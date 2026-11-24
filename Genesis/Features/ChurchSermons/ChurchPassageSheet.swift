import SwiftUI

/// A passage from a church's sermon, verbatim from a Bible on this device:
/// the person's own Bible first, or the one the pastor quoted (KJV, WEB,
/// ASV, RV1909, Bíblia Livre) when it's here. References are in KJV
/// numbering and go through `OriginalVersification` (the Reina-Valera
/// lands on the right verse). The Bible picked here is the sermon's
/// (`choice`, kept by the outline), so every passage opens in it
/// (`ChurchPassageBible`). Closing it goes back to the same place in the
/// outline.
struct ChurchPassageSheet: View {
    let range: StudyRange
    /// The Bible the pastor quoted, if its words may be shown.
    let quoted: String?
    /// The Bible the pastor named ("NIV"), shown when it isn't the one shown.
    var label: String? = nil
    /// The Bible picked for every passage of this sermon.
    @Binding var choice: String?
    /// Opens the reader at the passage, in the person's own Bible.
    let onOpen: (VerseID) -> Void

    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// A whole chapter's worth at most.
    private static let verseLimit = 60

    var body: some View {
        let options = options
        let shown = ChurchPassageBible.shown(options: options.map(\.id), chosen: choice)
        let translation = options.first { $0.id == shown } ?? options[0]
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
                        } footer: {
                            Text("Every passage in this sermon opens in this Bible.")
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(translation.name)
                            if let label, !ChurchPassageBible.labelNames(label, id: translation.id) {
                                Text("Sermon's Bible: \(label)")
                            }
                        }
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

    /// The person's Bible, the sermon's choice and the quoted one (each when
    /// it's on this device and unlocked), then the KJV when none has the
    /// passage.
    private var options: [Translation] {
        let ids = ChurchPassageBible.options(current: library.currentTranslation.id, chosen: choice, quoted: quoted, isAvailable: { library.canShowChurchPassage(in: $0) })
        var list: [Translation] = ids.compactMap { id -> Translation? in
            if id == library.currentTranslation.id { return library.currentTranslation }
            return library.translations.first { $0.id == id }
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

extension BibleLibrary {
    /// True when the Bible is on this device and not locked.
    func canShowChurchPassage(in id: String) -> Bool {
        translations.first { $0.id == id }.map { !isLocked($0) } ?? false
    }

    /// The Bible a church sermon's passages open in: the one picked for the
    /// sermon when it's here, else the person's own (`ChurchPassageBible`).
    func churchPassageBible(chosen: String?) -> String {
        let ids = ChurchPassageBible.options(current: currentTranslation.id, chosen: chosen, quoted: nil, isAvailable: { canShowChurchPassage(in: $0) })
        return ChurchPassageBible.shown(options: ids, chosen: chosen) ?? currentTranslation.id
    }
}
