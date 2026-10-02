import SwiftUI
import TipKit

/// The Search tab.
struct SearchView: View {
    @Environment(AppRouter.self) private var router
    @State private var text = ""

    var body: some View {
        NavigationStack {
            SearchContent(text: $text) { router.read($0) }
                .navigationTitle("Search")
                .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Words, topics or a reference")
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }
}

/// Search on iPhone, where it opens from a button rather than a tab.
struct SearchSheet: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            SearchContent(text: $text) { verse in
                dismiss()
                router.read(verse)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Words, topics or a reference")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("search.close")
                }
            }
        }
    }
}

extension EnvironmentValues {
    /// False on iPhone, where Search is a button that opens a sheet.
    @Entry var searchIsTab: Bool = true
}

/// A magnifying-glass button that opens Search (the tab or the sheet).
struct SearchButton: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.searchIsTab) private var searchIsTab
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            router.openSearch(asTab: searchIsTab)
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(palette.accent)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Search")
        .accessibilityIdentifier("home.search")
    }
}

enum SearchScopeOption: String, CaseIterable, Identifiable {
    case all, oldTestament, newTestament

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All", comment: "Search scope: the whole Bible")
        case .oldTestament: String(localized: "Old Testament")
        case .newTestament: String(localized: "New Testament")
        }
    }

    var scope: SearchScope {
        switch self {
        case .all: .wholeBible
        case .oldTestament: .testament(.old)
        case .newTestament: .testament(.new)
        }
    }
}

/// Instant search over the offline Bible: references, book names, words and
/// phrases. Used by the Search tab and the study panel.
struct SearchContent: View {
    @Binding var text: String
    var compact = false
    let onOpen: (VerseID) -> Void

    @Environment(BibleLibrary.self) private var library
    @Environment(\.topics) private var topics
    @Environment(\.palette) private var palette
    @State private var topicResults: [TopicSummary] = []
    @State private var scope: SearchScopeOption = .all
    @State private var order: SearchOrder = .relevance
    @State private var results: SearchResults = .empty

    init(text: Binding<String>, compact: Bool = false, onOpen: @escaping (VerseID) -> Void) {
        _text = text
        self.compact = compact
        self.onOpen = onOpen
    }

    /// Standalone version with its own text field, for the study panel.
    init(compact: Bool, onOpen: @escaping (VerseID) -> Void) {
        self.init(text: .constant(""), compact: compact, onOpen: onOpen)
        usesOwnField = true
    }

    private var usesOwnField = false
    @State private var ownText = ""

    private var query: String { usesOwnField ? ownText : text }

    var body: some View {
        List {
            if usesOwnField {
                TextField("Search", text: $ownText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .listRowBackground(Color.clear)
            }

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                suggestions
            } else {
                filters

                if let reference = results.reference {
                    Section {
                        Button {
                            onOpen(reference.firstVerse)
                        } label: {
                            Label("Go to \(reference.description)", systemImage: "arrow.right.circle")
                                .font(.headline)
                                .foregroundStyle(palette.accent)
                        }
                        .accessibilityIdentifier("search.goToReference")
                        .listRowBackground(palette.surface)
                    }
                }

                if !results.bookSuggestions.isEmpty {
                    Section("Books") {
                        ForEach(results.bookSuggestions) { book in
                            Button(book.name) { onOpen(ChapterID(book: book.id, chapter: 1).firstVerse) }
                                .foregroundStyle(palette.text)
                                .listRowBackground(palette.surface)
                        }
                    }
                }

                if !topicResults.isEmpty {
                    Section("Topics") {
                        ForEach(topicResults) { topic in
                            NavigationLink {
                                TopicDetailView(topicID: topic.id, onOpen: onOpen)
                                    .onAppear { GenesisTips.topics.invalidate(reason: .actionPerformed) }
                            } label: {
                                LabeledContent(topic.name, value: topic.referenceCount == 1 ? String(localized: "1 passage") : String(localized: "\(topic.referenceCount) passages"))
                                    .foregroundStyle(palette.text)
                            }
                            .listRowBackground(palette.surface)
                            .accessibilityIdentifier("search.topic")
                        }
                    }
                }

                Section {
                    ForEach(results.verses) { verse in
                        Button {
                            onOpen(verse.id)
                        } label: {
                            VerseSnippet(
                                reference: PassageReference(verse: verse.id).description,
                                text: verse.plainText,
                                terms: results.terms,
                                lineLimit: compact ? 3 : nil
                            )
                        }
                        .listRowBackground(palette.surface)
                    }
                } header: {
                    if !results.verses.isEmpty {
                        Text(countLabel)
                            .accessibilityIdentifier("search.resultCount")
                    }
                } footer: {
                    if results.isEmpty {
                        Text("No verses found in the \(library.currentTranslation.abbreviation). Try fewer words or a different spelling.")
                    }
                }
            }
        }
        .themedScreen()
        .task(id: SearchKey(text: query, scope: scope, order: order, translation: library.currentTranslation.id)) {
            await runSearch()
        }
    }

    private var countLabel: String {
        let count = results.totalMatches
        let total = count.formatted()
        let shown = results.verses.count
        if shown < count {
            return String(localized: "\(total) verses · showing \(shown)", comment: "Search results header: total matches, of which some are listed")
        }
        return count == 1 ? String(localized: "1 verse") : String(localized: "\(total) verses")
    }

    private var filters: some View {
        Section {
            Picker("Scope", selection: $scope) {
                ForEach(SearchScopeOption.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Order", selection: $order) {
                ForEach(SearchOrder.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private var suggestions: some View {
        Section("Try") {
            TipView(GenesisTips.topics)
                .tipBackground(palette.surface)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            ForEach(["John 3:16", "Psalm 23", "forgiveness", "love one another", "\u{201C}the Lord is my shepherd\u{201D}", "Romans 8"], id: \.self) { example in
                Button(example) {
                    if usesOwnField { ownText = example } else { text = example }
                }
                .foregroundStyle(palette.text)
                .listRowBackground(palette.surface)
            }
        }
    }

    private func runSearch() async {
        let input = query
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = .empty
            topicResults = []
            return
        }
        // Brief pause so fast typists don't search on every keystroke.
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else { return }

        let repository = library.current
        let searchScope = scope.scope
        let searchOrder = order
        let topicIndex = topics
        async let foundTopics = Task.detached(priority: .userInitiated) {
            // A reference like "John 3" isn't a topic search.
            ReferenceParser.parse(input) == nil ? ((try? topicIndex?.search(input, limit: 6)) ?? []) : []
        }.value
        let found = await Task.detached(priority: .userInitiated) {
            try? BibleSearch.run(input, in: repository, scope: searchScope, order: searchOrder)
        }.value
        let matchedTopics = await foundTopics
        guard !Task.isCancelled else { return }
        results = found ?? .empty
        topicResults = matchedTopics
    }
}

private struct SearchKey: Hashable {
    let text: String
    let scope: SearchScopeOption
    let order: SearchOrder
    let translation: String
}
