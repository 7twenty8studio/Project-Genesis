import SwiftUI

/// The Search tab.
struct SearchView: View {
    @Environment(AppRouter.self) private var router
    @State private var text = ""

    var body: some View {
        NavigationStack {
            SearchContent(text: $text) { router.read($0) }
                .navigationTitle("Search")
                .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Words, phrases or a reference")
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }
}

enum SearchScopeOption: String, CaseIterable, Identifiable {
    case all, oldTestament, newTestament

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .oldTestament: "Old Testament"
        case .newTestament: "New Testament"
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
    @Environment(\.palette) private var palette
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
        let noun = count == 1 ? "verse" : "verses"
        let shown = results.verses.count < count ? " · showing \(results.verses.count)" : ""
        return "\(count.formatted()) \(noun)\(shown)"
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
            ForEach(["John 3:16", "Psalm 23", "love one another", "\u{201C}the Lord is my shepherd\u{201D}", "Romans 8"], id: \.self) { example in
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
            return
        }
        // Brief pause so fast typists don't search on every keystroke.
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else { return }

        let repository = library.current
        let searchScope = scope.scope
        let searchOrder = order
        let found = await Task.detached(priority: .userInitiated) {
            try? BibleSearch.run(input, in: repository, scope: searchScope, order: searchOrder)
        }.value
        guard !Task.isCancelled else { return }
        results = found ?? .empty
    }
}

private struct SearchKey: Hashable {
    let text: String
    let scope: SearchScopeOption
    let order: SearchOrder
    let translation: String
}
