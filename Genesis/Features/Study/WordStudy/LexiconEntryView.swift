import SwiftUI

/// One Strong's entry: the word, its definition, how often it's used, and
/// the verses that use it (shown verbatim from the Bible being read).
struct LexiconEntryView: View {
    let strongs: String

    @Environment(\.wordStudy) private var wordStudy
    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette
    @State private var loaded: Loaded?
    @State private var didLoad = false

    private struct Loaded: Sendable {
        let entry: LexiconEntry
        let count: Int
        let verses: [Verse]
    }

    /// Verses listed under the entry (the count covers them all).
    private static let verseLimit = 60

    var body: some View {
        List {
            ThemedRows {
                if let loaded {
                    content(loaded)
                } else if didLoad {
                    Text("This word isn't in the dictionary.")
                        .foregroundStyle(palette.secondaryText)
                        .listRowBackground(palette.surface)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .themedScreen()
        .navigationTitle(loaded?.entry.strongs ?? strongs)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: strongs) { await load() }
    }

    @ViewBuilder
    private func content(_ loaded: Loaded) -> some View {
        let entry = loaded.entry
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.lemma)
                    .font(.system(.largeTitle, design: .serif))
                    .foregroundStyle(palette.text)
                Text(entry.transliteration)
                    .font(.subheadline.italic())
                    .foregroundStyle(palette.secondaryText)
                Text(entry.gloss)
                    .font(.headline)
                    .foregroundStyle(palette.accent)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("lexicon.header")
            if loaded.count == 1 {
                Text("Used once in the Bible.")
                    .foregroundStyle(palette.secondaryText)
            } else if loaded.count > 1 {
                Text("Used \(loaded.count) times in the Bible.")
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .listRowBackground(palette.surface)

        if !entry.definition.isEmpty {
            Section("Definition") {
                Text(entry.definition)
                    .foregroundStyle(palette.text)
                    .accessibilityIdentifier("lexicon.definition")
            }
            .listRowBackground(palette.surface)
        }
        if !entry.derivation.isEmpty || !entry.usage.isEmpty {
            Section("From Strong's") {
                if !entry.derivation.isEmpty {
                    LabeledContent("Origin", value: entry.derivation)
                }
                if !entry.usage.isEmpty {
                    LabeledContent("In the KJV", value: entry.usage)
                }
            }
            .listRowBackground(palette.surface)
        }
        if !loaded.verses.isEmpty {
            Section {
                ForEach(loaded.verses) { verse in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PassageReference(verse: verse.id).description(in: library.currentTranslation.language))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.accent)
                        Text(verse.plainText)
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(palette.text)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Where it's used")
            } footer: {
                if loaded.count > loaded.verses.count {
                    Text("The first \(loaded.verses.count) verses.")
                }
            }
            .listRowBackground(palette.surface)
        }
    }

    private func load() async {
        guard let wordStudy else {
            didLoad = true
            return
        }
        let strongs = strongs
        let bible = library.current
        let limit = Self.verseLimit
        loaded = await Task.detached(priority: .userInitiated) { () -> Loaded? in
            guard let entry = try? wordStudy.entry(strongs: strongs) else { return nil }
            let ids = (try? wordStudy.verses(using: strongs, limit: limit)) ?? []
            let verses = ids.compactMap { try? bible.verse($0) }
            return Loaded(entry: entry, count: (try? wordStudy.occurrences(of: strongs)) ?? 0, verses: verses)
        }.value
        didLoad = true
    }
}
