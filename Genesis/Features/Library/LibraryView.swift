import SwiftData
import SwiftUI

/// Everything the person has saved: highlights (with collections), notes,
/// bookmarks and, when Sermon Notes is switched on, sermons.
struct LibraryView: View {
    @Environment(\.searchIsTab) private var searchIsTab
    @Environment(AppRouter.self) private var router
    @Environment(FeaturePreferences.self) private var features
    enum Shelf: String, CaseIterable, Identifiable {
        case highlights, notes, bookmarks, sermons
        var id: String { rawValue }
        var title: String {
            switch self {
            case .highlights: String(localized: "Highlights")
            case .notes: String(localized: "Notes")
            case .bookmarks: String(localized: "Bookmarks")
            case .sermons: String(localized: "Sermons", comment: "Library shelf: sermon notes")
            }
        }

        /// The optional feature this shelf belongs to, if any.
        var feature: OptionalFeature? { self == .sermons ? .sermons : nil }
    }

    @State private var shelf: Shelf = .highlights
    @State private var showsStudyLibrary = false

    /// Shelves for features that are switched on.
    private var shelves: [Shelf] {
        Shelf.allCases.filter { item in
            guard let feature = item.feature else { return true }
            return features.isOn(feature)
        }
    }

    /// A hidden feature's shelf falls back to Highlights.
    private var visibleShelf: Shelf {
        shelves.contains(shelf) ? shelf : .highlights
    }

    var body: some View {
        NavigationStack {
            Group {
                switch visibleShelf {
                case .highlights: HighlightsList()
                case .notes: NotesList()
                case .bookmarks: BookmarksList()
                case .sermons: SermonsList()
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Show", selection: $shelf) {
                    ForEach(shelves) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .onChange(of: features.isOn(.sermons)) { _, on in
                if !on, shelf == .sermons { shelf = .highlights }
            }
            .navigationTitle("Library")
            .toolbar {
                if features.isOn(.studyLibrary) {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Study Library", systemImage: "books.vertical") { showsStudyLibrary = true }
                            .accessibilityIdentifier("library.studyLibrary")
                    }
                }
                if !searchIsTab {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Search", systemImage: "magnifyingglass") { router.openSearch(asTab: false) }
                            .accessibilityIdentifier("library.search")
                    }
                }
            }
            .sheet(isPresented: $showsStudyLibrary) {
                StudyResourcesView()
            }
        }
    }
}

// MARK: - Highlights

private struct HighlightsList: View {
    @Environment(AppRouter.self) private var router
    @Environment(BibleLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette

    @Query(sort: \Highlight.updatedAt, order: .reverse) private var highlights: [Highlight]
    @Query(sort: \HighlightCollection.name) private var collections: [HighlightCollection]

    @State private var colorFilter: HighlightColor?
    @State private var collectionFilter: HighlightCollection?
    @State private var newCollectionName = ""
    @State private var showsNewCollection = false
    @State private var pendingHighlight: Highlight?

    private var filtered: [Highlight] {
        highlights.filter { highlight in
            (colorFilter == nil || highlight.color == colorFilter)
                && (collectionFilter == nil || highlight.collection?.id == collectionFilter?.id)
        }
    }

    var body: some View {
        let texts = (try? library.current.verses(withIDs: filtered.map(\.verse))) ?? [:]
        List {
            ThemedRows {
                SwiftUI.Section {
                    filters
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                if filtered.isEmpty {
                    QuietEmptyState(
                        systemImage: "highlighter",
                        title: highlights.isEmpty ? String(localized: "No highlights yet") : String(localized: "Nothing matches"),
                        message: highlights.isEmpty ? String(localized: "In the reader, long-press a verse and pick a color.") : String(localized: "Try a different color or collection.")
                    )
                    .listRowBackground(Color.clear)
                }

                ForEach(filtered) { highlight in
                    Button {
                        router.read(highlight.verse)
                    } label: {
                        VerseSnippet(
                            reference: PassageReference(verse: highlight.verse).description,
                            text: texts[highlight.verse]?.plainText ?? "",
                            highlight: highlight.color
                        )
                    }
                    .listRowBackground(palette.surface)
                    .contextMenu {
                        Menu("Color") {
                            ForEach(HighlightColor.allCases) { color in
                                Button(color.title) {
                                    StudyStore(context: modelContext).highlight([highlight.verse], color: color)
                                }
                            }
                        }
                        Menu("Add to Collection") {
                            ForEach(collections) { collection in
                                Button(collection.name) {
                                    StudyStore(context: modelContext).add([highlight], to: collection)
                                }
                            }
                            Button("New Collection\u{2026}") {
                                pendingHighlight = highlight
                                showsNewCollection = true
                            }
                            if highlight.collection != nil {
                                Button("Remove from Collection") {
                                    StudyStore(context: modelContext).add([highlight], to: nil)
                                }
                            }
                        }
                        Button("Remove Highlight", role: .destructive) {
                            StudyStore(context: modelContext).removeHighlights([highlight.verse])
                        }
                    }
                }
                .onDelete { offsets in
                    StudyStore(context: modelContext).removeHighlights(offsets.map { filtered[$0].verse })
                }
            }
        }
        .themedScreen()
        .alert("New Collection", isPresented: $showsNewCollection) {
            TextField("Name", text: $newCollectionName)
            Button("Cancel", role: .cancel) { newCollectionName = "" }
            Button("Create") {
                let store = StudyStore(context: modelContext)
                let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let collection = store.createCollection(named: name)
                if let pendingHighlight { store.add([pendingHighlight], to: collection) }
                newCollectionName = ""
                pendingHighlight = nil
            }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(String(localized: "All", comment: "Highlight filter: every highlight"), selected: colorFilter == nil && collectionFilter == nil) {
                    colorFilter = nil
                    collectionFilter = nil
                }
                ForEach(HighlightColor.allCases) { color in
                    Button {
                        colorFilter = colorFilter == color ? nil : color
                    } label: {
                        Circle()
                            .fill(color.swatch)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(colorFilter == color ? palette.accent : .clear, lineWidth: 2.5))
                    }
                    .accessibilityLabel("\(color.title) highlights")
                    .accessibilityAddTraits(colorFilter == color ? .isSelected : [])
                }
                ForEach(collections) { collection in
                    chip(collection.name, selected: collectionFilter?.id == collection.id) {
                        collectionFilter = collectionFilter?.id == collection.id ? nil : collection
                    }
                }
                Button {
                    pendingHighlight = nil
                    showsNewCollection = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("New collection")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? palette.background : palette.text)
                .background(selected ? palette.accent : palette.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Notes

private struct NotesList: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var kindFilter: NoteKind?
    @State private var editing: Note?
    @State private var premium: PremiumFeature?
    @Environment(EntitlementService.self) private var entitlements
    @Environment(FeaturePreferences.self) private var features

    private var filtered: [Note] {
        guard let kindFilter else { return notes }
        return notes.filter { $0.kind == kindFilter }
    }

    var body: some View {
        List {
            ThemedRows {
                SwiftUI.Section {
                    Picker("Kind", selection: $kindFilter) {
                        Text("All").tag(NoteKind?.none)
                        ForEach(NoteKind.allCases) { Text($0.title).tag(NoteKind?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)

                // Prayers aren't notes: they're kept in the Prayer Journal.
                if features.isOn(.prayer) {
                    SwiftUI.Section {
                        NavigationLink {
                            PrayerJournalView()
                        } label: {
                            Label("Prayer Journal", systemImage: "hands.and.sparkles")
                                .foregroundStyle(palette.text)
                        }
                        .listRowBackground(palette.surface)
                        .accessibilityIdentifier("library.prayerJournal")
                    } footer: {
                        Text("Your prayers are kept in the Prayer Journal.")
                    }
                }

                if filtered.isEmpty {
                    QuietEmptyState(
                        systemImage: "note.text",
                        title: String(localized: "No notes yet"),
                        message: String(localized: "Write about a verse from the reader, or start a journal entry with the button below.")
                    )
                    .listRowBackground(Color.clear)
                }

                ForEach(filtered) { note in
                    Button {
                        editing = note
                    } label: {
                        NoteListRow(note: note)
                    }
                    .listRowBackground(palette.surface)
                }
                .onDelete { offsets in
                    let store = StudyStore(context: modelContext)
                    offsets.map { filtered[$0] }.forEach { store.delete($0) }
                }
            }
        }
        .themedScreen()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(NoteKind.allCases) { kind in
                        Button(kind.title, systemImage: kind.systemImage) {
                            let store = StudyStore(context: modelContext)
                            editing = store.createNote(kind: kind, anchor: kind == .study ? .theme("") : .none)
                        }
                    }
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("library.newNote")
            }
        }
        .sheet(item: $editing) { note in
            NavigationStack { NoteEditorView(note: note) }
        }
        .premiumSheet($premium)
    }
}

// MARK: - Bookmarks

private struct BookmarksList: View {
    @Environment(AppRouter.self) private var router
    @Environment(BibleLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Query(sort: \Bookmark.createdAt, order: .reverse) private var bookmarks: [Bookmark]

    var body: some View {
        let texts = (try? library.current.verses(withIDs: bookmarks.map(\.verse))) ?? [:]
        List {
            ThemedRows {
                if bookmarks.isEmpty {
                    QuietEmptyState(
                        systemImage: "bookmark",
                        title: String(localized: "No bookmarks yet"),
                        message: String(localized: "Tap the bookmark in the reader to mark your place.")
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(bookmarks) { bookmark in
                    Button {
                        router.read(bookmark.verse)
                    } label: {
                        VerseSnippet(
                            reference: PassageReference(verse: bookmark.verse).description,
                            text: texts[bookmark.verse]?.plainText ?? "",
                            lineLimit: 2
                        )
                    }
                    .listRowBackground(palette.surface)
                }
                .onDelete { offsets in
                    let store = StudyStore(context: modelContext)
                    for index in offsets { store.delete(bookmarks[index]) }
                }
            }
        }
        .themedScreen()
    }
}
