import SwiftData
import SwiftUI

/// Writes or edits a note, prayer, study note or journal entry.
struct NoteEditorView: View {
    @Bindable var note: Note

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderSettings.self) private var settings
    @FocusState private var focusedField: Field?
    @State private var confirmDelete = false
    @State private var themeName = ""
    @State private var wasDeleted = false

    private enum Field { case title, body }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Kind", selection: $note.kind) {
                    ForEach(NoteKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.systemImage).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                anchorView

                TextField("Title", text: $note.title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .focused($focusedField, equals: .title)

                TextField(placeholder, text: $note.body, axis: .vertical)
                    .font(settings.preferences.font.font(size: 18))
                    .lineSpacing(5)
                    .focused($focusedField, equals: .body)
                    .accessibilityIdentifier("note.body")
                    .frame(minHeight: 240, alignment: .topLeading)
            }
            .padding(20)
        }
        .themedScreen()
        .navigationTitle(note.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { dismiss() }
                    .accessibilityIdentifier("note.done")
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                wasDeleted = true
                StudyStore(context: modelContext).delete(note)
                dismiss()
            }
        }
        .onAppear {
            if case let .theme(name) = note.anchor { themeName = name }
            if note.body.isEmpty { focusedField = .body }
        }
        .onDisappear(perform: save)
    }

    private var placeholder: String {
        switch note.kind {
        case .prayer: "Write your prayer\u{2026}"
        case .journal: "What's on your heart today?"
        case .study: "Observations, questions, connections\u{2026}"
        case .text: "Write a note\u{2026}"
        }
    }

    @ViewBuilder
    private var anchorView: some View {
        switch note.anchor {
        case let .verses(start, end):
            let verses = (try? library.current.verses(from: start, through: end)) ?? []
            VerseSnippet(
                reference: note.anchor.title,
                text: verses.map(\.plainText).joined(separator: " "),
                lineLimit: 4
            )
            .card()
        case .chapter, .book:
            Label(note.anchor.title, systemImage: "book")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.accent)
        case .theme:
            TextField("Theme, e.g. Grace", text: $themeName)
                .textFieldStyle(.roundedBorder)
        case .none:
            EmptyView()
        }
    }

    private func save() {
        guard !wasDeleted else { return }
        // Don't keep notes that were opened and left empty.
        if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            wasDeleted = true
            StudyStore(context: modelContext).delete(note)
            return
        }
        if case .theme = note.anchor {
            note.anchor = .theme(themeName.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        note.updatedAt = .now
        StudyStore(context: modelContext).save()
    }
}
