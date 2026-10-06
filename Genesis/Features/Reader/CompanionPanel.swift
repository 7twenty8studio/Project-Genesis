import SwiftData
import SwiftUI

/// The second column on iPad and an open iPhone Duo: notes, related passages
/// or search beside the text, so study never covers Scripture.
struct CompanionPanel: View {
    enum Mode: String, CaseIterable, Identifiable {
        case notes, crossReferences, study, context, search, plan, prayer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notes: String(localized: "Notes")
            case .crossReferences: String(localized: "Related", comment: "Panel title: related passages (cross-references)")
            case .study: String(localized: "Study")
            case .context: String(localized: "Context")
            case .search: String(localized: "Search")
            case .plan: String(localized: "Reading Plan")
            case .prayer: String(localized: "Prayer Journal")
            }
        }

        var systemImage: String {
            switch self {
            case .notes: "note.text"
            case .crossReferences: "arrow.triangle.branch"
            case .study: "sparkles"
            case .context: "map"
            case .search: "magnifyingglass"
            case .plan: "calendar"
            case .prayer: "hands.and.sparkles"
            }
        }
    }

    @Binding var mode: Mode
    @Environment(ReaderViewModel.self) private var reader
    @Environment(\.palette) private var palette
    @Environment(StudyAssistant.self) private var assistant
    @Environment(FeaturePreferences.self) private var features
    @Environment(EntitlementService.self) private var entitlements

    /// Only the panels for features that are switched on.
    private var modes: [Mode] {
        Mode.allCases.filter { mode in
            switch mode {
            case .study: assistant.isEnabled
            case .context: features.isOn(.explore)
            case .plan, .prayer: features.isOn(.plansAndPrayer)
            case .notes, .crossReferences, .search: true
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .notes:
                    ChapterNotesView(chapter: reader.chapterID)
                case .crossReferences:
                    CrossReferencesView(verse: reader.studyVerse ?? reader.focusVerse) { reader.open($0) }
                case .study:
                    if assistant.isEnabled {
                        ChapterStudyPanel(chapter: reader.chapterID)
                    } else {
                        ChapterNotesView(chapter: reader.chapterID)
                    }
                case .context:
                    ChapterContextView(chapter: reader.chapterID)
                case .search:
                    SearchContent(compact: true) { reader.open($0) }
                case .plan:
                    CompanionPlanView()
                case .prayer:
                    PrayerJournalView()
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .plans: PlansView()
                case let .plan(id): PlanDetailView(enrollmentID: id)
                case .prayerJournal: PrayerJournalView()
                case .insights: InsightsView()
                case .memorise:
                    if entitlements.allows(.memorise) {
                        MemoriseView()
                    } else {
                        PremiumView(highlighted: .memorise)
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                // Seven panels don't fit a segmented control in 360 points.
                // A menu with its own label: the system picker's label wraps
                // ("Not / es") in a narrow panel.
                Menu {
                    Picker("Panel", selection: $mode) {
                        ForEach(modes) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Label(mode.title, systemImage: mode.systemImage)
                            .lineLimit(1)
                            .fixedSize()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(palette.accent)
                }
                .accessibilityLabel("Panel, \(mode.title)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .accessibilityIdentifier("companion.mode")
            }
            .onChange(of: modes) {
                if !modes.contains(mode) { mode = .notes }
            }
            // Plans and the prayer journal have their own toolbar buttons (New Prayer).
            .toolbar(mode == .plan || mode == .prayer ? .visible : .hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
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
            ThemedRows {
                if notes.isEmpty {
                    QuietEmptyState(
                        systemImage: "note.text",
                        title: String(localized: "No notes in \(chapter.description)"),
                        message: String(localized: "Long-press a verse and choose Note, or add a note for the whole chapter.")
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
        }
        .themedScreen()
        .safeAreaInset(edge: .bottom) {
            Button {
                let store = StudyStore(context: modelContext)
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

/// Bible + Reading Plan: today's reading in the plan you're following, or the
/// plans to choose from.
struct CompanionPlanView: View {
    @Query(sort: \PlanEnrollment.createdAt, order: .reverse) private var enrollments: [PlanEnrollment]

    var body: some View {
        if let active = enrollments.first(where: { $0.isActive && $0.plan != nil }) {
            PlanDetailView(enrollmentID: active.id)
        } else {
            PlansView(opensStartedPlan: false)
        }
    }
}
