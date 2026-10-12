import SwiftData
import SwiftUI
import TipKit

/// Writes or edits one sermon's notes. Church Mode (remembered) dims the
/// screen to the Night palette, keeps it awake, offers larger text and a
/// quick verse lookup.
struct SermonEditorView: View {
    @Bindable var sermon: Sermon

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var basePalette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppRouter.self) private var router
    @AppStorage("sermons.churchMode") private var churchMode = false
    @AppStorage("sermons.largeText") private var largeText = false
    @State private var insertion: SermonNotesInsertion?
    @State private var wasDeleted = false
    @State private var confirmDelete = false
    @State private var exporting: JournalExportSubject?

    var body: some View {
        let palette = churchMode ? ReaderTheme.night.palette : basePalette
        form
            .environment(\.palette, palette)
            .environment(\.colorScheme, churchMode ? .dark : colorScheme)
            .tint(palette.accent)
            .modifier(ChurchModeScreenAwake(churchMode: churchMode))
    }

    private var form: some View {
        Form {
            ThemedRows {
                if churchMode {
                    ChurchModeSection(largeText: $largeText)
                    SermonVerseLookup(canAttach: sermon.passages.count < Sermon.maximumPassages, onInsert: insert)
                }
                Section {
                    TextField("Sermon title", text: $sermon.title, axis: .vertical)
                        .font(.headline)
                        .accessibilityIdentifier("sermon.title")
                }
                Section("Notes") {
                    SermonNotesEditor(text: $sermon.body, insertion: $insertion, largeText: churchMode && largeText)
                }
                SermonPassagesSection(sermon: sermon, onOpen: openInReader)
                AttachmentsSection(owner: .sermon, ownerID: sermon.id)
                SermonDetailsSection(sermon: sermon)
                Section {
                    Button("Delete Sermon Notes", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .themedScreen()
        .navigationTitle(churchMode ? "Church Mode" : "Sermon Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { editorToolbar }
        .sheet(item: $exporting) { subject in
            JournalExportSheet(subject: subject)
        }
        .confirmationDialog("Delete these sermon notes?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                wasDeleted = true
                StudyStore(context: modelContext).delete(sermon)
                dismiss()
            }
        }
        .onDisappear(perform: save)
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", systemImage: "checkmark") { dismiss() }
                .accessibilityIdentifier("sermon.done")
        }
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                churchMode.toggle()
            } label: {
                Label("Church Mode", systemImage: churchMode ? "building.columns.fill" : "building.columns")
            }
            .accessibilityAddTraits(churchMode ? .isSelected : [])
            .accessibilityIdentifier("sermon.churchMode")
            Button {
                StudyStore(context: modelContext).toggleFavourite(sermon)
            } label: {
                Label(sermon.isFavourite ? "Remove Favorite" : "Favorite", systemImage: sermon.isFavourite ? "star.fill" : "star")
            }
            .accessibilityAddTraits(sermon.isFavourite ? .isSelected : [])
            .accessibilityIdentifier("sermon.favourite")
            JournalExtrasMenu(owner: .sermon, onTemplate: apply) { exporting = .sermon(sermon) }
        }
    }

    /// From the lookup: the reference goes into the notes at the cursor and
    /// the passage is attached.
    private func insert(_ passage: PrayerPassage, reference: String) {
        insertion = SermonNotesInsertion(kind: .reference(reference))
        StudyStore(context: modelContext).attach(passage, to: sermon)
    }

    /// A template (Premium) in place of empty notes, or at the cursor.
    private func apply(_ template: JournalTemplate) {
        insertion = SermonNotesInsertion(kind: .template(template.text()))
    }

    private func openInReader(_ passage: PrayerPassage) {
        dismiss()
        router.read(passage.start)
    }

    private func save() {
        guard !wasDeleted else { return }
        let store = StudyStore(context: modelContext)
        // Discard notes that were opened and left empty; notes with only
        // attachments are kept under a plain title, so they're listed.
        if !sermon.hasContent {
            guard !store.attachments(for: .sermon, id: sermon.id).isEmpty else {
                wasDeleted = true
                store.delete(sermon)
                return
            }
            sermon.title = String(localized: "Untitled Sermon")
        }
        sermon.updatedAt = .now
        store.save()
    }
}

/// Church Mode's own controls: larger text and the one-time Focus tip.
private struct ChurchModeSection: View {
    @Binding var largeText: Bool

    var body: some View {
        Section {
            Toggle("Larger Text", isOn: $largeText)
                .accessibilityIdentifier("sermon.largeText")
            TipView(GenesisTips.churchModeFocus)
        } footer: {
            Text("Church Mode keeps the screen awake and dim while you take notes.")
        }
    }
}

/// Preacher, church (with the person's earlier churches), date and series.
private struct SermonDetailsSection: View {
    @Bindable var sermon: Sermon
    @Query(sort: \Sermon.preachedAt, order: .reverse) private var allSermons: [Sermon]
    @Environment(\.palette) private var palette

    var body: some View {
        let others = allSermons.filter { $0.id != sermon.id }.map(\.facts)
        let suggestions = SermonGrouping.churchSuggestions(others, typed: sermon.church)
        Section("Details") {
            TextField("Preacher", text: $sermon.preacher)
                .textContentType(.name)
                .accessibilityIdentifier("sermon.preacher")
            TextField("Church", text: $sermon.church)
                .accessibilityIdentifier("sermon.church")
            if !suggestions.isEmpty {
                churchSuggestions(suggestions)
            }
            DatePicker("Date", selection: $sermon.preachedAt, displayedComponents: .date)
            TextField("Series (optional)", text: series)
                .accessibilityIdentifier("sermon.series")
        }
    }

    private var series: Binding<String> {
        Binding(
            get: { sermon.series ?? "" },
            set: { sermon.series = $0.isEmpty ? nil : $0 }
        )
    }

    private func churchSuggestions(_ names: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    Button {
                        sermon.church = name
                    } label: {
                        Label(name, systemImage: "building.columns")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(palette.text)
                            .background(palette.background, in: Capsule())
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
