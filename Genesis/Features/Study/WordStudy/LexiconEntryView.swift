import SwiftUI

/// One Strong's entry: the word, its definition, how often it's used, and
/// the verses that use it (shown verbatim from the Bible being read).
struct LexiconEntryView: View {
    let strongs: String

    @Environment(\.wordStudy) private var wordStudy
    @Environment(BibleLibrary.self) private var library
    @Environment(StudyResourceLibrary.self) private var studyResources
    @Environment(EntitlementService.self) private var entitlements
    @Environment(\.palette) private var palette
    @Environment(WordPronouncer.self) private var pronouncer
    @State private var loaded: Loaded?
    @State private var didLoad = false
    /// Brown-Driver-Briggs or Liddell-Scott-Jones, from a downloaded lexicon pack.
    @State private var fullEntries: [StudyLexiconEntry] = []

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
        .studyLinks()
        .onAppear { WordPronouncer.preloadVoices() }
        .onDisappear { pronouncer.stop() }
        .task(id: strongs) {
            await load()
            await loadFullEntries()
        }
    }

    @ViewBuilder
    private func content(_ loaded: Loaded) -> some View {
        let entry = loaded.entry
        Section {
            HStack(alignment: .top, spacing: 8) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("lexicon.header")
                PronounceButton(word: entry.lemma, language: entry.language)
            }
            .padding(.vertical, 4)
            if loaded.count == 1 {
                Text("Used once in the Bible.")
                    .foregroundStyle(palette.secondaryText)
            } else if loaded.count > 1 {
                Text("Used \(loaded.count) times in the Bible.")
                    .foregroundStyle(palette.secondaryText)
            }
        } footer: {
            PronunciationNote(language: entry.language)
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
        ForEach(fullEntries) { full in
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(full.lemma)
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(palette.text)
                    if !full.transliteration.isEmpty || !full.gloss.isEmpty {
                        Text([full.transliteration, full.gloss].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
                StudyTextRows(text: full.definition)
                    .accessibilityIdentifier("lexicon.full")
            } header: {
                Text(full.source.title)
            }
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

    /// The fuller lexicons are a Premium download (`lexicons` pack).
    private func loadFullEntries() async {
        guard entitlements.allows(.wordStudy),
              let pack = studyResources.installedResources(.lexicon).first,
              let repository = studyResources.repository(pack.id) else {
            fullEntries = []
            return
        }
        let strongs = strongs
        fullEntries = await Task.detached(priority: .userInitiated) {
            (try? repository.lexicon(strongs: strongs)) ?? []
        }.value
    }
}
