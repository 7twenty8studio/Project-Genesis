import SwiftUI

/// Original Word (Premium, with word study): the Hebrew or Greek most likely
/// behind the English words picked in a verse. Matching goes by each
/// original word's English gloss (`OriginalWordMatcher`), so matches are
/// labelled "Likely" or "Closest match" and every word of the verse is a tap
/// away. The verse is shown verbatim from the Bible being read (English
/// Bibles only); Hebrew and Greek verbatim from WordStudy.sqlite.
struct OriginalWordView: View {
    let verse: VerseID
    /// The word long-pressed in the reader, picked to begin with.
    var pressed: PressedWord?

    @Environment(\.wordStudy) private var wordStudy
    @Environment(BibleLibrary.self) private var library
    @Environment(EntitlementService.self) private var entitlements
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: Loaded?
    /// Indices into `loaded.spans`.
    @State private var picked: Set<Int> = []

    private struct Loaded: Sendable {
        let text: String
        let spans: [Range<String.Index>]
        let words: [OriginalWord]
        let lexicon: [String: LexiconEntry]
        let counts: [String: Int]
    }

    /// A short phrase at most.
    private static let maximumPicked = 6

    private var unlocked: Bool { entitlements.allows(.wordStudy) }
    private var isGreek: Bool { verse.book >= 40 }

    var body: some View {
        NavigationStack {
            List {
                ThemedRows {
                    if let loaded {
                        verseSection(loaded)
                        matchesSection(loaded)
                        allWordsSection
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    Section {
                    } footer: {
                        Text(WordStudyRepository.attribution)
                    }
                }
            }
            .themedScreen()
            .navigationTitle("Original Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("originalWord.done")
                }
            }
            .navigationDestination(for: LexiconRoute.self) { route in
                LexiconEntryView(strongs: route.strongs)
            }
            .navigationDestination(for: VerseStudyRoute.self) { route in
                VerseStudyList(verse: route.verse)
            }
            .task(id: verse) { await load() }
        }
    }

    // MARK: Sections

    private func verseSection(_ loaded: Loaded) -> some View {
        Section {
            PickableVerseText(text: loaded.text, words: loaded.spans, picked: picked, onToggle: toggle)
        } header: {
            Text(PassageReference(verse: verse).description(in: library.currentTranslation.language))
        } footer: {
            Text(isGreek
                 ? String(localized: "Tap a word, or a few words, to see the Greek behind them.")
                 : String(localized: "Tap a word, or a few words, to see the Hebrew behind them."))
        }
        .listRowBackground(palette.surface)
    }

    @ViewBuilder
    private func matchesSection(_ loaded: Loaded) -> some View {
        let selected = selectedText(loaded)
        if !selected.isEmpty {
            let matches = OriginalWordMatcher.matches(for: selected, in: loaded.words, lexicon: loaded.lexicon)
            Section {
                if matches.isEmpty {
                    Text("No close match for “\(selected)”. Matching is approximate, so every word of the verse is listed below.")
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityIdentifier("originalWord.noMatch")
                } else if unlocked {
                    ForEach(matches) { match in
                        matchRows(match, loaded: loaded)
                    }
                } else {
                    OriginalWordRow(word: matches[0].word)
                    PremiumTeaser(message: String(localized: "See the definition of the Hebrew or Greek behind any word, and where else it's used, with Premium."), feature: .wordStudy)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            } header: {
                Text("“\(selected)” in the original")
                    .textCase(nil)
            } footer: {
                if !matches.isEmpty {
                    Text("Matched by each word's English gloss, so treat this as a guide.")
                }
            }
            .listRowBackground(palette.surface)
        }
    }

    @ViewBuilder
    private func matchRows(_ match: OriginalWordMatch, loaded: Loaded) -> some View {
        let strongs = match.word.strongs
        OriginalWordMatchCard(
            match: match,
            entry: strongs.flatMap { loaded.lexicon[$0] },
            usageCount: strongs.flatMap { loaded.counts[$0] } ?? 0
        )
        if let strongs {
            NavigationLink(value: LexiconRoute(strongs: strongs)) {
                Text("Full definition and every verse")
                    .foregroundStyle(palette.accent)
            }
            .accessibilityIdentifier("originalWord.lexicon")
        }
    }

    private var allWordsSection: some View {
        Section {
            NavigationLink(value: VerseStudyRoute(verse: verse)) {
                Label("All words in this verse", systemImage: "character.book.closed")
                    .foregroundStyle(palette.text)
            }
            .accessibilityIdentifier("originalWord.allWords")
        }
        .listRowBackground(palette.surface)
    }

    // MARK: Picking

    private func toggle(_ index: Int) {
        if picked.contains(index) {
            picked.remove(index)
        } else if picked.count < Self.maximumPicked {
            picked.insert(index)
        } else {
            picked = [index]
        }
    }

    /// The picked words in the verse's order.
    private func selectedText(_ loaded: Loaded) -> String {
        picked.sorted()
            .filter { $0 < loaded.spans.count }
            .map { String(loaded.text[loaded.spans[$0]]) }
            .joined(separator: " ")
    }

    // MARK: Loading

    private func load() async {
        let text = (try? library.current.verse(verse))?.plainText ?? ""
        let spans = VerseWords.ranges(in: text)
        if let pressed, pressed.verse == verse, let start = VerseWords.index(of: pressed, in: text, ranges: spans) {
            picked = [start]
        }
        guard let wordStudy else {
            loaded = Loaded(text: text, spans: spans, words: [], lexicon: [:], counts: [:])
            return
        }
        let verse = verse
        loaded = await Task.detached(priority: .userInitiated) {
            let words = (try? wordStudy.words(in: verse)) ?? []
            var lexicon: [String: LexiconEntry] = [:]
            var counts: [String: Int] = [:]
            for strongs in Set(words.compactMap(\.strongs)) {
                if let entry = try? wordStudy.entry(strongs: strongs) {
                    lexicon[strongs] = entry
                }
                counts[strongs] = (try? wordStudy.occurrences(of: strongs)) ?? 0
            }
            return Loaded(text: text, spans: spans, words: words, lexicon: lexicon, counts: counts)
        }.value
    }
}

/// Opens every word of a verse (`VerseStudyList`) from Original Word.
struct VerseStudyRoute: Hashable {
    let verse: VerseID
}
