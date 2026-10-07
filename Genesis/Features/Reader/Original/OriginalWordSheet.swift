import SwiftUI

/// One Hebrew or Greek word tapped in the Original parallel Bible: the word
/// verbatim, its transliteration, Strong's number, dictionary form, gloss in
/// this verse, grammar in plain words, how editions differ (Greek), the
/// lexicon's definition and every verse that uses it (Premium, `.wordStudy`;
/// free accounts see the word and a way to unlock the rest).
struct OriginalWordSheet: View {
    let word: OriginalWord

    @Environment(\.wordStudy) private var wordStudy
    @Environment(EntitlementService.self) private var entitlements
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: Loaded?

    private struct Loaded: Sendable {
        let entry: LexiconEntry?
        let count: Int
    }

    private var unlocked: Bool { entitlements.allows(.wordStudy) }
    private var morphology: Morphology { Morphology(code: word.morphology, language: word.language) }

    var body: some View {
        NavigationStack {
            List {
                ThemedRows {
                    wordSection
                    if unlocked {
                        OriginalWordDetails(word: word, morphology: morphology, entry: loaded?.entry, count: loaded?.count ?? 0)
                    } else {
                        Section {
                            PremiumTeaser(message: String(localized: "See what every Hebrew and Greek word means, its grammar and where else it's used, with Premium."), feature: .wordStudy)
                                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        }
                        .listRowBackground(palette.surface)
                    }
                    Section {
                    } footer: {
                        Text(WordStudyRepository.attribution)
                    }
                }
            }
            .themedScreen()
            .navigationTitle(languageName)
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
            .task(id: word.id) { await load() }
        }
    }

    private var wordSection: some View {
        Section {
            VStack(alignment: word.language == .hebrew ? .trailing : .leading, spacing: 4) {
                Text(OriginalText.display(word.text))
                    .font(OriginalFont.font(for: word.language, size: word.language == .hebrew ? 44 : 38))
                    .foregroundStyle(palette.text)
                    .accessibilityIdentifier("originalWord.text")
                Text(word.transliteration)
                    .font(.title3.italic())
                    .foregroundStyle(palette.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: word.language == .hebrew ? .trailing : .leading)
            .padding(.vertical, 4)
            LabeledContent("In this verse", value: word.gloss)
            if let strongs = word.strongs {
                LabeledContent("Strong's number", value: strongs)
            }
        }
        .listRowBackground(palette.surface)
    }

    private var languageName: String {
        if morphology.isAramaic { return String(localized: "Aramaic") }
        return word.language == .greek ? String(localized: "Greek") : String(localized: "Hebrew")
    }

    private func load() async {
        guard let wordStudy, let strongs = word.strongs else {
            loaded = Loaded(entry: nil, count: 0)
            return
        }
        loaded = await Task.detached(priority: .userInitiated) {
            Loaded(
                entry: try? wordStudy.entry(strongs: strongs),
                count: (try? wordStudy.occurrences(of: strongs)) ?? 0
            )
        }.value
    }
}

/// The Premium part of `OriginalWordSheet`: dictionary form, grammar,
/// edition note, definition and where the word is used.
private struct OriginalWordDetails: View {
    let word: OriginalWord
    let morphology: Morphology
    let entry: LexiconEntry?
    let count: Int

    @Environment(\.palette) private var palette

    var body: some View {
        if let entry {
            Section("Dictionary form") {
                VStack(alignment: word.language == .hebrew ? .trailing : .leading, spacing: 2) {
                    Text(entry.lemma)
                        .font(OriginalFont.font(for: word.language, size: 28))
                        .foregroundStyle(palette.text)
                    Text(entry.transliteration)
                        .font(.subheadline.italic())
                        .foregroundStyle(palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: word.language == .hebrew ? .trailing : .leading)
                if !entry.gloss.isEmpty {
                    LabeledContent("Meaning", value: entry.gloss)
                }
            }
            .listRowBackground(palette.surface)
        }
        let details = morphology.details
        if !details.isEmpty {
            Section("Grammar") {
                ForEach(details) { detail in
                    LabeledContent(detail.label, value: detail.value)
                }
            }
            .listRowBackground(palette.surface)
        }
        if let edition = word.edition {
            Section("Greek editions") {
                Text(editionNote(edition))
                    .foregroundStyle(palette.text)
            }
            .listRowBackground(palette.surface)
        }
        if let entry, !entry.definition.isEmpty {
            Section("Definition") {
                Text(entry.definition)
                    .foregroundStyle(palette.text)
            }
            .listRowBackground(palette.surface)
        }
        if let strongs = word.strongs, count > 0 {
            Section {
                NavigationLink(value: LexiconRoute(strongs: strongs)) {
                    usage
                }
                .accessibilityIdentifier("originalWord.usage")
            }
            .listRowBackground(palette.surface)
        }
    }

    @ViewBuilder
    private var usage: some View {
        if count == 1 {
            Text("Used once in the Bible.")
                .foregroundStyle(palette.accent)
        } else {
            Text("Used \(count) times in the Bible.")
                .foregroundStyle(palette.accent)
        }
    }

    private func editionNote(_ edition: EditionDifference) -> String {
        switch edition {
        case .textusReceptusOnly:
            String(localized: "This word is in the Textus Receptus, the Greek the KJV translates, but not in the Nestle-Aland text most modern Bibles use.")
        case .minor:
            String(localized: "The Nestle-Aland text most modern Bibles use has this word in a slightly different spelling or form, which doesn't change the meaning.")
        }
    }
}
