import SwiftData
import SwiftUI

/// The private prayer journal: requests, answered prayers, categories,
/// reminders, attached passages, a timeline, a gentle streak and a few
/// numbers. Free for everyone, with no limits.
struct PrayerJournalView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case list, timeline
        var id: String { rawValue }
        var title: String {
            switch self {
            case .list: String(localized: "List", comment: "Prayer journal view: the list of prayers")
            case .timeline: String(localized: "Timeline", comment: "Prayer journal view: prayers and answers by month")
            }
        }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case praying, answered
        var id: String { rawValue }
        var title: String { self == .praying ? String(localized: "Praying", comment: "Prayer journal filter: prayers still being prayed") : String(localized: "Answered", comment: "Prayer journal filter: answered prayers") }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Environment(EntitlementService.self) private var entitlements
    @Query(sort: \Prayer.updatedAt, order: .reverse) private var prayers: [Prayer]
    @State private var mode: Mode = .list
    @State private var filter: Filter = .praying
    @State private var category: PrayerCategory?
    @State private var query = ""
    @State private var editing: Prayer?
    @State private var exporting: JournalExportSubject?
    @State private var premium: PremiumFeature?

    /// Prayers matching the search and the category chip.
    private var searched: [Prayer] {
        prayers.filter { prayer in
            prayer.hasContent
                && (category == nil || prayer.category == category)
                && PrayerSearch.matches(title: prayer.title, body: prayer.body, answerNote: prayer.answerNote, query: query)
        }
    }

    private var visible: [Prayer] {
        searched.filter { (filter == .answered) == $0.isAnswered }
    }

    var body: some View {
        List {
            ThemedRows {
                if query.isEmpty {
                    PrayerLifeSection(prayers: prayers)
                }
                controls
                if mode == .list {
                    listRows
                } else {
                    PrayerTimelineSections(prayers: searched) { editing = $0 }
                }
            }
        }
        .themedScreen()
        .searchable(text: $query, prompt: "Search prayers")
        .navigationTitle("Prayer Journal")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let store = StudyStore(context: modelContext)
                    editing = store.createPrayer(category: category ?? .personal)
                } label: {
                    Label("New Prayer", systemImage: "plus")
                }
                .accessibilityIdentifier("prayer.new")
            }
            ToolbarItem(placement: .secondaryAction) {
                // Premium: the journal as a PDF for a range of days.
                Button("Export as PDF", systemImage: "square.and.arrow.up") {
                    if entitlements.allows(.journalExtras) {
                        exporting = .journal
                    } else {
                        premium = .journalExtras
                    }
                }
                .accessibilityIdentifier("prayer.exportJournal")
            }
        }
        .sheet(item: $editing) { prayer in
            NavigationStack { PrayerEditorView(prayer: prayer) }
        }
        .sheet(item: $exporting) { subject in
            JournalExportSheet(subject: subject)
        }
        .premiumSheet($premium)
    }

    private var controls: some View {
        Section {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("prayer.mode")

            if mode == .list {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("prayer.filter")
            }

            PrayerCategoryChips(selection: $category)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    @ViewBuilder
    private var listRows: some View {
        if visible.isEmpty {
            emptyState
                .listRowBackground(Color.clear)
        }
        ForEach(visible) { prayer in
            Button {
                editing = prayer
            } label: {
                PrayerRow(prayer: prayer)
            }
            .listRowBackground(palette.surface)
            .swipeActions(edge: .leading) {
                Button(prayer.isAnswered ? "Still Praying" : "Answered") {
                    StudyStore(context: modelContext).markAnswered(prayer, answered: !prayer.isAnswered)
                }
                .tint(palette.accent)
                if !prayer.isAnswered {
                    Button("Prayed", systemImage: "hands.and.sparkles") {
                        StudyStore(context: modelContext).markPrayed(prayer)
                    }
                }
            }
        }
        .onDelete { offsets in
            let store = StudyStore(context: modelContext)
            offsets.map { visible[$0] }.forEach { store.delete($0) }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            QuietEmptyState(
                systemImage: "magnifyingglass",
                title: String(localized: "No matching prayers"),
                message: String(localized: "Try another word from the title or the prayer.")
            )
        } else {
            QuietEmptyState(
                systemImage: filter == .praying ? "hands.and.sparkles" : "checkmark.seal",
                title: filter == .praying ? String(localized: "No prayer requests") : String(localized: "No answered prayers yet"),
                message: filter == .praying
                    ? String(localized: "Add the people and needs you're praying for. Your journal is private to you.")
                    : String(localized: "When a prayer is answered, mark it here to remember God's faithfulness.")
            )
        }
    }
}

/// "All" and one chip per category.
struct PrayerCategoryChips: View {
    @Binding var selection: PrayerCategory?
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(String(localized: "All", comment: "Prayer category filter: every category"), systemImage: nil, selected: selection == nil) { selection = nil }
                ForEach(PrayerCategory.allCases) { item in
                    chip(item.title, systemImage: item.systemImage, selected: selection == item) {
                        selection = selection == item ? nil : item
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ title: String, systemImage: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
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

struct PrayerRow: View {
    let prayer: Prayer
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: prayer.category.systemImage)
                Text(prayer.category.title)
                if prayer.reminderAt != nil, !prayer.isAnswered {
                    Image(systemName: "bell")
                        .accessibilityLabel("Reminder set")
                }
                if !prayer.passages.isEmpty {
                    Image(systemName: "book.closed")
                        .accessibilityLabel("Has Bible passages")
                }
                Spacer()
                if prayer.isAnswered, let answered = prayer.answeredAt {
                    Text("Answered \(answered.formatted(.dateTime.month(.abbreviated).day()))")
                } else {
                    Text(prayer.createdAt, format: .dateTime.month(.abbreviated).day())
                }
            }
            .font(.caption)
            .foregroundStyle(palette.secondaryText)

            Text(prayer.displayTitle)
                .font(.headline)
                .foregroundStyle(palette.text)
                .lineLimit(2)
            if let note = prayer.answerNote, prayer.isAnswered, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
