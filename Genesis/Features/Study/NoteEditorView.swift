import SwiftData
import SwiftUI

/// Writes or edits a note, prayer, study note or journal entry, as typed text
/// or a handwritten page.
struct NoteEditorView: View {
    @Bindable var note: Note

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.palette) private var palette
    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderSettings.self) private var settings
    @FocusState private var focusedField: Field?
    @State private var confirmDelete = false
    @State private var themeName = ""
    @State private var wasDeleted = false
    @State private var page: NotePage = .text
    @State private var autosave = DrawingAutosave()
    @State private var drawingTooLarge = false
    /// The reflection prompt offered on a new journal entry, until used or dismissed.
    @State private var prompt: String?

    private enum Field { case title, body }

    var body: some View {
        content
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
                autosave.cancel()
                wasDeleted = true
                StudyStore(context: modelContext).delete(note)
                dismiss()
            }
        }
        .onAppear {
            if case let .theme(name) = note.anchor { themeName = name }
            let drawing = note.drawing
            drawingTooLarge = !NoteDrawing.fitsSync(drawing)
            if drawing != nil, note.body.isEmpty { page = .handwriting }
            offerPromptIfNew()
            if note.body.isEmpty, page == .text { focusedField = .body }
        }
        .onChange(of: note.kind) { offerPromptIfNew() }
        .onChange(of: page) {
            if page == .handwriting { focusedField = nil } else { autosave.flush() }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active { autosave.flush() }
        }
        .onDisappear(perform: save)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .text:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let prompt {
                        JournalPromptCard(
                            prompt: prompt,
                            onUse: { use(prompt) },
                            onAnother: { self.prompt = JournalPrompts.prompt(after: prompt) },
                            onDismiss: { self.prompt = nil }
                        )
                    }
                    bodyField
                }
                .padding(20)
            }
        case .handwriting:
            VStack(alignment: .leading, spacing: 16) {
                header
                HandwritingPage(
                    initialData: note.drawing,
                    autosave: autosave,
                    isTooLargeToSync: drawingTooLarge,
                    onSave: saveDrawing
                )
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Kind", selection: $note.kind) {
                ForEach(NoteKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.systemImage).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Picker("Page", selection: $page) {
                Label("Text", systemImage: "text.alignleft").tag(NotePage.text)
                Label("Handwriting", systemImage: "pencil.and.scribble").tag(NotePage.handwriting)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("note.handwriting")

            anchorView

            TextField("Title", text: $note.title, axis: .vertical)
                .font(.title3.weight(.semibold))
                .focused($focusedField, equals: .title)
        }
    }

    // A plain TextField, so Scribble turns Apple Pencil handwriting into text here.
    private var bodyField: some View {
        TextField(placeholder, text: $note.body, axis: .vertical)
            .font(settings.preferences.font.font(size: 18))
            .lineSpacing(5)
            .focused($focusedField, equals: .body)
            .accessibilityIdentifier("note.body")
            .frame(minHeight: 240, alignment: .topLeading)
    }

    /// A new, empty journal entry gets a gentle prompt it can start from.
    private func offerPromptIfNew() {
        guard prompt == nil, note.kind == .journal, note.title.isEmpty, note.body.isEmpty, note.drawing == nil else { return }
        prompt = JournalPrompts.prompt()
    }

    private func use(_ chosen: String) {
        note.body = JournalPrompts.inserting(chosen, into: note.body)
        prompt = nil
        page = .text
        focusedField = .body
    }

    /// Called by the autosave a moment after the last stroke.
    private func saveDrawing(_ data: Data?) {
        guard !wasDeleted else { return }
        note.drawing = data
        note.updatedAt = .now
        drawingTooLarge = !NoteDrawing.fitsSync(data)
        StudyStore(context: modelContext).save()
    }

    private var placeholder: String {
        switch note.kind {
        case .prayer: String(localized: "Write your prayer\u{2026}")
        case .journal: String(localized: "What's on your heart today?")
        case .study: String(localized: "Observations, questions, connections\u{2026}")
        case .text: String(localized: "Write a note\u{2026}")
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
        autosave.flush()
        // Don't keep notes that were opened and left empty.
        if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           note.drawing == nil {
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
