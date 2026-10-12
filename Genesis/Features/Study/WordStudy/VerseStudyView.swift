import SwiftUI

/// Word study for one verse (Premium): the Hebrew or Greek words behind it,
/// each with its Strong's entry, and Matthew Henry's commentary on the
/// passage. The verse itself is shown verbatim from the Bible being read.
struct VerseStudyView: View {
    let verse: VerseID

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VerseStudyList(verse: verse)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") { dismiss() }
                            .accessibilityIdentifier("wordStudy.done")
                    }
                }
                .navigationDestination(for: LexiconRoute.self) { route in
                    LexiconEntryView(strongs: route.strongs)
                }
        }
    }
}

/// The words and commentary of `VerseStudyView`, without its navigation
/// stack. The stack that holds it handles `LexiconRoute`.
struct VerseStudyList: View {
    let verse: VerseID

    enum Tab: String, CaseIterable, Identifiable {
        case words, commentary
        var id: String { rawValue }
        var title: String {
            switch self {
            case .words: String(localized: "Original Words")
            case .commentary: String(localized: "Commentary")
            }
        }
    }

    @Environment(\.wordStudy) private var wordStudy
    @Environment(BibleLibrary.self) private var library
    @Environment(EntitlementService.self) private var entitlements
    @Environment(\.palette) private var palette
    @State private var tab: Tab = .words
    @State private var loaded: Loaded?

    private struct Loaded: Sendable {
        let words: [OriginalWord]
        let commentary: [CommentaryPassage]
    }

    /// Free accounts see this many words, then the way to unlock the rest.
    private static let previewWords = 2

    private var unlocked: Bool { entitlements.allows(.wordStudy) }

    var body: some View {
        List {
            ThemedRows {
                Section {
                    Text((try? library.current.verse(verse))?.plainText ?? "")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(palette.text)
                        .accessibilityIdentifier("wordStudy.verse")
                    Picker("Show", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("wordStudy.tab")
                }
                .listRowBackground(palette.surface)

                if let loaded {
                    switch tab {
                    case .words: words(loaded.words)
                    case .commentary: commentary(loaded.commentary)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }

                Section {
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if WordStudyRepository.needsEnglishNote(bibleLanguage: library.currentTranslation.language) {
                            Text("Definitions and commentary are in English for now. More languages are coming soon.")
                        }
                        Text(WordStudyRepository.attribution)
                    }
                }
            }
        }
        .themedScreen()
        .navigationTitle(PassageReference(verse: verse).description(in: library.currentTranslation.language))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: verse) { await load() }
    }

    // MARK: Sections

    @ViewBuilder
    private func words(_ words: [OriginalWord]) -> some View {
        Section {
            if words.isEmpty {
                Text("No original-language words are listed for this verse.")
                    .foregroundStyle(palette.secondaryText)
            }
            ForEach(unlocked ? words : Array(words.prefix(Self.previewWords))) { word in
                if unlocked, let strongs = word.strongs {
                    NavigationLink(value: LexiconRoute(strongs: strongs)) {
                        OriginalWordRow(word: word)
                    }
                    .accessibilityIdentifier("wordStudy.word")
                } else {
                    OriginalWordRow(word: word)
                }
            }
            if !unlocked && words.count > Self.previewWords {
                PremiumTeaser(message: String(localized: "See every Hebrew and Greek word in this verse, with Strong's definitions, with Premium."), feature: .wordStudy)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
        } header: {
            Text(words.first?.language == .greek ? String(localized: "Greek") : String(localized: "Hebrew"))
        } footer: {
            if unlocked && !words.isEmpty {
                Text("In the original word order. Tap a word for its definition and where else it's used.")
            }
        }
        .listRowBackground(palette.surface)
    }

    @ViewBuilder
    private func commentary(_ passages: [CommentaryPassage]) -> some View {
        if passages.isEmpty {
            Section {
                Text("There's no commentary on this verse.")
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
        } else if !unlocked {
            Section {
                PremiumTeaser(message: String(localized: "Read Matthew Henry's commentary on every chapter, with Premium."), feature: .wordStudy)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
            .listRowBackground(palette.surface)
        } else {
            ForEach(passages) { passage in
                Section {
                    ForEach(Array(passage.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .foregroundStyle(palette.text)
                            .accessibilityIdentifier("wordStudy.commentary")
                    }
                } header: {
                    Text(passage.title ?? passage.reference.description)
                } footer: {
                    Text("Matthew Henry, \(passage.reference.description)")
                }
                .listRowBackground(palette.surface)
            }
        }
    }

    // MARK: Loading

    /// The KJV verses (the word data's numbering) holding this verse's text:
    /// through `OriginalVersification` for the Bibles it lines up (the
    /// Reina-Valera numbers some verses differently); other English Bibles
    /// share the KJV's numbers.
    private var kjvVerses: [VerseID] {
        if let map = OriginalVersification.map(for: library.currentTranslation.id) {
            return map.alignment(of: verse).kjv
        }
        return [verse]
    }

    private func load() async {
        guard let wordStudy else {
            loaded = Loaded(words: [], commentary: [])
            return
        }
        let verses = kjvVerses
        loaded = await Task.detached(priority: .userInitiated) {
            Loaded(
                words: verses.flatMap { (try? wordStudy.words(in: $0)) ?? [] },
                commentary: verses.first.flatMap { try? wordStudy.commentary(for: $0) } ?? []
            )
        }.value
    }
}

/// Opens a Strong's entry from the word list.
struct LexiconRoute: Hashable {
    let strongs: String
}
