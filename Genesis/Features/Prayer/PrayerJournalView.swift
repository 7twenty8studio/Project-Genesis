import SwiftData
import SwiftUI

/// The private prayer journal: requests, answered prayers, categories and reminders.
struct PrayerJournalView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case praying, answered
        var id: String { rawValue }
        var title: String { self == .praying ? String(localized: "Praying", comment: "Prayer journal filter: prayers still being prayed") : String(localized: "Answered", comment: "Prayer journal filter: answered prayers") }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Query(sort: \Prayer.updatedAt, order: .reverse) private var prayers: [Prayer]
    @State private var filter: Filter = .praying
    @State private var category: PrayerCategory?
    @State private var editing: Prayer?
    @State private var premium: PremiumFeature?
    @Environment(EntitlementService.self) private var entitlements

    private var visible: [Prayer] {
        prayers.filter { prayer in
            (filter == .answered) == prayer.isAnswered && (category == nil || prayer.category == category)
        }
    }

    var body: some View {
        List {
            ThemedRows {
                Section {
                    Picker("Show", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("prayer.filter")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip(String(localized: "All", comment: "Prayer category filter: every category"), systemImage: nil, selected: category == nil) { category = nil }
                            ForEach(PrayerCategory.allCases) { item in
                                chip(item.title, systemImage: item.systemImage, selected: category == item) {
                                    category = category == item ? nil : item
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                if visible.isEmpty {
                    QuietEmptyState(
                        systemImage: filter == .praying ? "hands.and.sparkles" : "checkmark.seal",
                        title: filter == .praying ? String(localized: "No prayer requests") : String(localized: "No answered prayers yet"),
                        message: filter == .praying
                            ? String(localized: "Add the people and needs you're praying for. Your journal is private to you.")
                            : String(localized: "When a prayer is answered, mark it here to remember God's faithfulness.")
                    )
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
                    }
                }
                .onDelete { offsets in
                    let store = StudyStore(context: modelContext)
                    offsets.map { visible[$0] }.forEach { store.delete($0) }
                }
            }
        }
        .themedScreen()
        .premiumSheet($premium)
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
        }
        .sheet(item: $editing) { prayer in
            NavigationStack { PrayerEditorView(prayer: prayer) }
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

/// Writes or edits one prayer.
struct PrayerEditorView: View {
    @Bindable var prayer: Prayer

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(ReaderSettings.self) private var settings
    @State private var hasReminder = false
    @State private var reminderDate = Date.now.addingTimeInterval(3600)
    @State private var answerNote = ""
    @State private var wasDeleted = false
    @State private var confirmDelete = false
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            ThemedRows {
                Section {
                    TextField("Who or what are you praying for?", text: $prayer.title, axis: .vertical)
                        .font(.headline)
                        .accessibilityIdentifier("prayer.title")
                    TextField("Your prayer", text: $prayer.body, axis: .vertical)
                        .font(settings.preferences.font.font(size: 17))
                        .lineLimit(4...)
                        .accessibilityIdentifier("prayer.body")
                }

                Section("Category") {
                    Picker("Category", selection: $prayer.category) {
                        ForEach(PrayerCategory.allCases) { category in
                            Label(category.title, systemImage: category.systemImage).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if !prayer.isAnswered {
                    Section {
                        Toggle("Remind me to pray", isOn: $hasReminder)
                            .accessibilityIdentifier("prayer.reminder")
                        if hasReminder {
                            DatePicker("Time", selection: $reminderDate, displayedComponents: prayer.reminderRepeatsDaily ? [.hourAndMinute] : [.date, .hourAndMinute])
                            Toggle("Every day", isOn: $prayer.reminderRepeatsDaily)
                        }
                    } footer: {
                        if notificationsDenied {
                            Text("Notifications are off for Genesis. Turn them on in Settings to get reminders.")
                        } else {
                            Text("Reminders show only the title above, never your prayer.")
                        }
                    }
                }

                Section {
                    if prayer.isAnswered {
                        TextField("How was it answered?", text: $answerNote, axis: .vertical)
                        Button("Move Back to Praying") {
                            StudyStore(context: modelContext).markAnswered(prayer, answered: false)
                        }
                    } else {
                        Button {
                            StudyStore(context: modelContext).markAnswered(prayer, note: answerNote)
                        } label: {
                            Label("Mark as Answered", systemImage: "checkmark.seal")
                        }
                        .accessibilityIdentifier("prayer.markAnswered")
                    }
                } header: {
                    Text(prayer.isAnswered ? "Answered" : "")
                }

                Section {
                    Button("Delete Prayer", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .themedScreen()
        .navigationTitle(prayer.isAnswered ? "Answered Prayer" : "Prayer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { dismiss() }
                    .accessibilityIdentifier("prayer.done")
            }
        }
        .confirmationDialog("Delete this prayer?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                wasDeleted = true
                StudyStore(context: modelContext).delete(prayer)
                dismiss()
            }
        }
        .onAppear {
            hasReminder = prayer.reminderAt != nil
            if let reminder = prayer.reminderAt { reminderDate = reminder }
            answerNote = prayer.answerNote ?? ""
        }
        .onChange(of: hasReminder) { _, on in
            guard on else { return }
            Task { notificationsDenied = !(await PrayerReminders.requestAuthorization()) }
        }
        .onDisappear(perform: save)
    }

    private func save() {
        guard !wasDeleted else { return }
        let store = StudyStore(context: modelContext)
        // Discard a prayer that was opened and left empty.
        if prayer.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           prayer.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            wasDeleted = true
            store.delete(prayer)
            return
        }
        prayer.reminderAt = hasReminder && !prayer.isAnswered ? reminderDate : nil
        if !hasReminder { prayer.reminderRepeatsDaily = false }
        if prayer.isAnswered { prayer.answerNote = answerNote }
        prayer.updatedAt = .now
        store.save()
        PrayerReminders.update(for: prayer)
    }
}
