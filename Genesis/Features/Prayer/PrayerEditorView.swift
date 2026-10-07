import SwiftData
import SwiftUI

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
    @State private var exporting: JournalExportSubject?

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

                PrayerPassagesSection(prayer: prayer)

                AttachmentsSection(owner: .prayer, ownerID: prayer.id)

                if !prayer.isAnswered {
                    reminderSection
                }

                answerSection

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
            ToolbarItem(placement: .topBarLeading) {
                JournalExtrasMenu(owner: .prayer, onTemplate: apply) { exporting = .prayer(prayer) }
            }
        }
        .sheet(item: $exporting) { subject in
            JournalExportSheet(subject: subject)
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

    private var reminderSection: some View {
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

    private var answerSection: some View {
        Section {
            if prayer.isAnswered {
                TextField("How was it answered?", text: $answerNote, axis: .vertical)
                    .accessibilityIdentifier("prayer.answerNote")
                Button("Move Back to Praying") {
                    StudyStore(context: modelContext).markAnswered(prayer, answered: false)
                }
            } else {
                Button {
                    StudyStore(context: modelContext).markPrayed(prayer)
                } label: {
                    Label(prayedToday ? "Prayed Today" : "I Prayed for This", systemImage: prayedToday ? "checkmark.circle.fill" : "hands.and.sparkles")
                }
                .disabled(prayedToday)
                .accessibilityIdentifier("prayer.prayed")
                Button {
                    StudyStore(context: modelContext).markAnswered(prayer, note: answerNote)
                } label: {
                    Label("Mark as Answered", systemImage: "checkmark.seal")
                }
                .accessibilityIdentifier("prayer.markAnswered")
            }
        } header: {
            Text(prayer.isAnswered ? "Answered" : "")
        } footer: {
            if prayer.isAnswered {
                Text("Optional: a few words to remember how God answered.")
            }
        }
    }

    private var prayedToday: Bool {
        prayer.lastPrayedAt.map { Calendar.current.isDateInToday($0) } ?? false
    }

    /// A template (Premium) in place of an empty prayer, or after what's written.
    private func apply(_ template: JournalTemplate) {
        prayer.body = JournalTemplate.inserting(template.text(), into: prayer.body).text
    }

    private func save() {
        guard !wasDeleted else { return }
        let store = StudyStore(context: modelContext)
        // Discard a prayer that was opened and left empty; one with only
        // attachments is kept under a plain title, so it's listed.
        if !prayer.hasContent {
            guard !store.attachments(for: .prayer, id: prayer.id).isEmpty else {
                wasDeleted = true
                store.delete(prayer)
                return
            }
            prayer.title = String(localized: "Untitled Prayer")
        }
        prayer.reminderAt = hasReminder && !prayer.isAnswered ? reminderDate : nil
        if !hasReminder { prayer.reminderRepeatsDaily = false }
        if prayer.isAnswered { prayer.answerNote = answerNote }
        prayer.updatedAt = .now
        store.save()
        PrayerReminders.update(for: prayer)
    }
}

/// The passages a prayer holds, each shown verbatim from the Bible being
/// read, with a field to add another ("John 3:16" or "Psalm 23").
struct PrayerPassagesSection: View {
    let prayer: Prayer

    @Environment(BibleLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @State private var text = ""
    @State private var problem: String?

    var body: some View {
        Section {
            ForEach(prayer.passages) { passage in
                PrayerPassageRow(passage: passage)
            }
            .onDelete { offsets in
                let store = StudyStore(context: modelContext)
                offsets.map { prayer.passages[$0] }.forEach { store.detach($0, from: prayer) }
            }
            if prayer.passages.count < PrayerPassage.maximumPerPrayer {
                HStack {
                    TextField(String(localized: "John 3:16", comment: "Example Bible reference"), text: $text)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(add)
                        .accessibilityIdentifier("prayer.passageField")
                    Button("Add", action: add)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("prayer.addPassage")
                }
            }
        } header: {
            Text("Bible Passages")
        } footer: {
            if let problem {
                Text(problem)
                    .foregroundStyle(.orange)
            } else {
                Text("Pray with Scripture: add a verse or passage, such as Philippians 4:6\u{2013}7.")
            }
        }
    }

    private func add() {
        let current = library.current
        guard let passage = PrayerPassage.parse(text, lastVerse: { chapter in
            (try? current.chapter(chapter))?.verses.last?.id.verse
        }) else {
            problem = String(localized: "Type a book, chapter and verse, such as John 3:16.")
            return
        }
        guard ((try? current.verses(from: passage.start, through: passage.end)) ?? []).isEmpty == false else {
            problem = String(localized: "That passage isn't in the Bible you're reading.")
            return
        }
        problem = nil
        text = ""
        StudyStore(context: modelContext).attach(passage, to: prayer)
    }
}

/// One attached passage: its reference and words, verbatim from the current Bible.
struct PrayerPassageRow: View {
    let passage: PrayerPassage

    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        let translation = library.currentTranslation
        let verses = (try? library.current.verses(from: passage.start, through: passage.end)) ?? []
        VStack(alignment: .leading, spacing: 6) {
            Text("\(passage.reference.description(in: translation.language)) · \(translation.abbreviation)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.accent)
            if verses.isEmpty {
                Text("This passage isn't in the Bible you're reading.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            } else {
                Text(verses.map(\.plainText).joined(separator: " "))
                    .font(settings.preferences.font.font(size: 16))
                    .foregroundStyle(palette.text)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prayer.passage")
    }
}
