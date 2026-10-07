import PDFKit
import SwiftData
import SwiftUI

/// What to export as a PDF.
enum JournalExportSubject: Identifiable {
    case prayer(Prayer)
    case sermon(Sermon)
    /// The prayer journal, for a range of days and optionally one category.
    case journal

    var id: String {
        switch self {
        case let .prayer(prayer): "prayer-\(prayer.id.uuidString)"
        case let .sermon(sermon): "sermon-\(sermon.id.uuidString)"
        case .journal: "journal"
        }
    }
}

/// Creates the PDF (Premium, `.journalExtras`), shows a preview and offers
/// it to share, print or save.
struct JournalExportSheet: View {
    let subject: JournalExportSubject

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(BibleLibrary.self) private var library
    @Environment(ReaderSettings.self) private var settings
    @Environment(EntitlementService.self) private var entitlements
    @Environment(AttachmentTransfers.self) private var transfers
    @Query(sort: \Prayer.createdAt) private var prayers: [Prayer]
    @State private var filter = PrayerExportFilter(from: Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now, through: .now)
    @State private var output: URL?
    @State private var preview: PDFDocument?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                ThemedRows {
                    if case .journal = subject {
                        JournalExportOptions(filter: $filter)
                    }
                    actionSection
                    if let preview {
                        Section("Preview") {
                            PDFKitView(document: preview)
                                .frame(height: 440)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                }
            }
            .themedScreen()
            .navigationTitle("Export PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("journalExport.done")
                }
            }
            .task {
                if case .journal = subject { return }
                await create()
            }
            .onChange(of: filter) { _, _ in
                output = nil
                preview = nil
            }
        }
    }

    private var actionSection: some View {
        Section {
            if isWorking {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing your PDF…")
                }
            } else if let output {
                ShareLink(item: output) {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("journalExport.share")
            } else {
                Button {
                    Task { await create() }
                } label: {
                    Label("Create PDF", systemImage: "doc.richtext")
                }
                .accessibilityIdentifier("journalExport.create")
            }
        } footer: {
            Text("Share, print or save it to Files. Recordings and imported PDFs are listed, not included.")
        }
    }

    private func create() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let store = StudyStore(context: modelContext)
        await downloadPictures(store)
        let font = ReaderStyle.resolvedFont(settings.preferences.font, premium: entitlements.allows(.premiumThemes))
        let builder = JournalExportBuilder(library: library, store: store, files: transfers.files, font: font)
        let export: JournalExport = switch subject {
        case let .prayer(prayer): builder.export(prayer)
        case let .sermon(sermon): builder.export(sermon)
        case .journal: builder.exportJournal(prayers, filter: filter)
        }
        let name = JournalExportFile.name(for: export.title)
        let url = await Task.detached { JournalExportFile.write(JournalPDFRenderer().render(export), named: name) }.value
        output = url
        preview = url.flatMap { PDFDocument(url: $0) }
    }

    /// Photos and Pencil pages synced from another device come down first.
    private func downloadPictures(_ store: StudyStore) async {
        let owners: [(AttachmentOwner, UUID)] = switch subject {
        case let .prayer(prayer): [(.prayer, prayer.id)]
        case let .sermon(sermon): [(.sermon, sermon.id)]
        case .journal: filter.apply(prayers.map(\.facts)).map { (AttachmentOwner.prayer, $0.id) }
        }
        for (owner, id) in owners {
            for attachment in store.attachments(for: owner, id: id) where attachment.kind == .photo || attachment.kind == .drawing {
                await transfers.ensureFile(for: attachment)
            }
        }
    }
}

/// The date range and category for a journal export.
private struct JournalExportOptions: View {
    @Binding var filter: PrayerExportFilter

    var body: some View {
        Section("Prayers") {
            DatePicker("From", selection: $filter.from, displayedComponents: .date)
            DatePicker("Through", selection: $filter.through, displayedComponents: .date)
            Picker("Category", selection: $filter.category) {
                Text("All Categories").tag(PrayerCategory?.none)
                ForEach(PrayerCategory.allCases) { category in
                    Label(category.title, systemImage: category.systemImage).tag(PrayerCategory?.some(category))
                }
            }
            .pickerStyle(.menu)
        }
    }
}

/// Where an export is written before it's shared.
enum JournalExportFile {
    /// "Grace upon grace.pdf", safe as a file name.
    static func name(for title: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = title.components(separatedBy: unsafe).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let short = String(cleaned.prefix(80)).trimmingCharacters(in: .whitespaces)
        return (short.isEmpty ? "Genesis" : short) + ".pdf"
    }

    static func write(_ data: Data, named name: String) -> URL? {
        let folder = URL.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
