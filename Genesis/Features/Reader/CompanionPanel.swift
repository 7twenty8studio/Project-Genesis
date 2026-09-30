import SwiftData
import SwiftUI

/// The second column on iPad and an open iPhone Duo: notes, related passages
/// or search beside the text, so study never covers Scripture.
struct CompanionPanel: View {
    enum Mode: String, CaseIterable, Identifiable {
        case notes, crossReferences, study, context, search

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notes: "Notes"
            case .crossReferences: "Related"
            case .study: "Study"
            case .context: "Context"
            case .search: "Search"
            }
        }
    }

    @Binding var mode: Mode
    @Environment(ReaderViewModel.self) private var reader
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .notes:
                    ChapterNotesView(chapter: reader.chapterID)
                case .crossReferences:
                    CrossReferencesView(verse: reader.studyVerse ?? reader.focusVerse) { reader.open($0) }
                case .study:
                    ChapterStudyPanel(chapter: reader.chapterID)
                case .context:
                    ChapterContextView(chapter: reader.chapterID)
                case .search:
                    SearchContent(compact: true) { reader.open($0) }
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Panel", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Notes attached to verses in a chapter, with a button to add one.
struct ChapterNotesView: View {
    let chapter: ChapterID

    @Environment(\.modelContext) private var modelContext
    @Environment(ReaderViewModel.self) private var reader
    @Environment(\.palette) private var palette
    @Query private var notes: [Note]
    @State private var editing: Note?
    @State private var premium: PremiumFeature?
    @Environment(EntitlementService.self) private var entitlements

    init(chapter: ChapterID) {
        self.chapter = chapter
        let book: Int? = chapter.book
        let number: Int? = chapter.chapter
        _notes = Query(
            filter: #Predicate<Note> { $0.bookNumber == book && $0.chapterNumber == number },
            sort: \Note.createdAt
        )
    }

    var body: some View {
        List {
            if notes.isEmpty {
                QuietEmptyState(
                    systemImage: "note.text",
                    title: "No notes in \(chapter.description)",
                    message: "Long-press a verse and choose Note, or add a note for the whole chapter."
                )
                .listRowBackground(Color.clear)
            }
            ForEach(notes) { note in
                Button {
                    editing = note
                } label: {
                    NoteRow(note: note)
                }
                .listRowBackground(palette.background)
            }
        }
        .themedScreen()
        .safeAreaInset(edge: .bottom) {
            Button {
                let store = StudyStore(context: modelContext)
                guard entitlements.canAddNote(existing: store.noteCount()) else {
                    premium = .unlimitedNotes
                    return
                }
                editing = store.createNote(kind: .study, anchor: .chapter(chapter))
            } label: {
                Label("Note on \(chapter.description)", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(16)
        }
        .premiumSheet($premium)
        .sheet(item: $editing, onDismiss: { reader.notesDidChange() }) { note in
            NavigationStack { NoteEditorView(note: note) }
        }
    }
}

/// One note in a list.
struct NoteRow: View {
    let note: Note
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: note.kind.systemImage)
                Text(note.kind.title)
                if !note.anchor.title.isEmpty {
                    Text("·")
                    Text(note.anchor.title)
                }
                Spacer()
                Text(note.updatedAt, format: .dateTime.month(.abbreviated).day())
            }
            .font(.caption)
            .foregroundStyle(palette.secondaryText)

            Text(note.displayTitle)
                .font(.headline)
                .foregroundStyle(palette.text)
                .lineLimit(1)
            if !note.title.isEmpty, !note.body.isEmpty {
                Text(note.body)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
