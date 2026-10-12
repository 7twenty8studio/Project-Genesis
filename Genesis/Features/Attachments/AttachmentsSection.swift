import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The attachments on a prayer or sermon notes (Premium, `.journalExtras`):
/// a strip of photos, PDFs and Pencil pages, the recordings below it, and an
/// Add menu. Free accounts keep seeing anything already
/// attached and get a short teaser instead of the menu.
struct AttachmentsSection: View {
    let owner: AttachmentOwner
    let ownerID: UUID

    @Environment(\.palette) private var palette
    @Environment(EntitlementService.self) private var entitlements
    @Environment(AttachmentTransfers.self) private var transfers
    @Query private var attachments: [Attachment]

    init(owner: AttachmentOwner, ownerID: UUID) {
        self.owner = owner
        self.ownerID = ownerID
        let kind = owner.rawValue
        let id = ownerID
        _attachments = Query(
            filter: #Predicate<Attachment> { $0.ownerID == id && $0.ownerKindRaw == kind },
            sort: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
    }

    var body: some View {
        Section {
            AttachmentsRow(owner: owner, ownerID: ownerID, attachments: attachments, isUnlocked: entitlements.allows(.journalExtras))
        } header: {
            Text("Attachments")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Attachments are saved on this device first, then copied to your private iCloud when you're online, so they're on your other devices too. They use your iCloud storage.")
                if let problem = transfers.problem?.errorDescription {
                    Text(problem)
                        .accessibilityIdentifier("attachments.iCloudProblem")
                }
            }
        }
    }
}

/// Everything in the section as one row, so its pickers and sheets have a
/// single home.
private struct AttachmentsRow: View {
    let owner: AttachmentOwner
    let ownerID: UUID
    let attachments: [Attachment]
    let isUnlocked: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Environment(AttachmentTransfers.self) private var transfers
    @State private var sheet: AttachmentSheet?
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var showsPDFImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var viewing: Attachment?
    @State private var problem: String?
    @State private var isImporting = false

    private var pictures: [Attachment] { attachments.filter { $0.kind != .audio } }
    private var recordings: [Attachment] { attachments.filter { $0.kind == .audio } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !pictures.isEmpty {
                AttachmentStrip(attachments: pictures) { viewing = $0 }
            }
            ForEach(recordings) { recording in
                AttachmentAudioRow(attachment: recording) { viewing = recording }
            }
            if isUnlocked {
                addMenu
            } else {
                PremiumTeaser(
                    message: String(localized: "Add photos, voice recordings and Pencil pages with Premium."),
                    feature: .journalExtras
                )
            }
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoItems, maxSelectionCount: nil, matching: .images)
        .fileImporter(isPresented: $showsPDFImporter, allowedContentTypes: [.pdf]) { importPDF($0) }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { data in Task { await addPhoto(data) } }
                .ignoresSafeArea()
        }
        .sheet(item: $sheet) { sheet in sheetContent(sheet) }
        .sheet(item: $viewing) { attachment in
            AttachmentViewer(attachment: attachment, onEditDrawing: isUnlocked ? { editDrawing($0) } : nil)
        }
    }

    // MARK: Adding

    private var addMenu: some View {
        Menu {
            Button("Choose Photos", systemImage: "photo.on.rectangle") { showsPhotoPicker = true }
            if CameraPicker.isAvailable {
                Button("Take Photo", systemImage: "camera") { showsCamera = true }
            }
            Button("Record Voice", systemImage: "mic") { sheet = .recorder }
                .accessibilityIdentifier("attachments.record")
            if allows(.pdf) {
                Button("Import PDF", systemImage: "doc.badge.plus") { showsPDFImporter = true }
            }
            if allows(.drawing) {
                Button("Drawing", systemImage: "pencil.tip.crop.circle.badge.plus") { sheet = .newDrawing }
            }
        } label: {
            HStack {
                Label("Add Attachment", systemImage: "paperclip")
                Spacer()
                if isImporting { ProgressView() }
            }
            .foregroundStyle(palette.accent)
        }
        .disabled(isImporting)
        .accessibilityIdentifier("attachments.add")
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AttachmentSheet) -> some View {
        switch sheet {
        case .recorder:
            VoiceRecorderSheet(owner: owner, files: transfers.files) { url, duration in
                keepRecording(url, duration: duration)
            }
        case .newDrawing:
            DrawingAttachmentSheet(initialData: nil) { data in
                if let data { save(data, kind: .drawing) }
            }
        case let .drawing(attachment):
            DrawingAttachmentSheet(initialData: try? transfers.files.read(attachment.fileName)) { data in
                updateDrawing(attachment, data: data)
            }
        }
    }

    /// After the viewer has closed, so the two sheets don't overlap.
    private func editDrawing(_ attachment: Attachment) {
        viewing = nil
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            sheet = .drawing(attachment)
        }
    }

    private func allows(_ kind: AttachmentKind) -> Bool {
        AttachmentLimits.canAdd(kind, to: owner)
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer {
            isImporting = false
            photoItems = []
        }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            await addPhoto(data)
        }
    }

    private func addPhoto(_ data: Data) async {
        let prepared = await Task.detached { AttachmentMedia.preparedPhoto(from: data) }.value
        guard let prepared else {
            problem = String(localized: "That photo couldn't be added.")
            return
        }
        save(prepared, kind: .photo)
    }

    private func importPDF(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            problem = String(localized: "That PDF couldn't be opened.")
            return
        }
        guard AttachmentLimits.fits(byteCount: data.count, kind: .pdf) else {
            problem = String(localized: "That file is too large to attach.")
            return
        }
        guard let pages = AttachmentMedia.pdfPageCount(data) else {
            problem = String(localized: "That PDF couldn't be opened.")
            return
        }
        save(data, kind: .pdf, pageCount: pages, caption: url.deletingPathExtension().lastPathComponent)
    }

    private func keepRecording(_ url: URL, duration: TimeInterval) {
        let id = UUID()
        let fileName = AttachmentPaths.fileName(id: id, kind: .audio)
        do {
            try transfers.files.move(url, to: fileName)
        } catch {
            problem = String(localized: "The recording couldn't be saved.")
            return
        }
        let size = (try? transfers.files.url(for: fileName).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        record(id: id, kind: .audio, fileName: fileName, byteSize: size, duration: duration)
    }

    /// Writes the file, then records the attachment.
    private func save(_ data: Data, kind: AttachmentKind, pageCount: Int? = nil, caption: String = "") {
        let id = UUID()
        let fileName = AttachmentPaths.fileName(id: id, kind: kind)
        guard AttachmentLimits.fits(byteCount: data.count, kind: kind) else {
            problem = String(localized: "That file is too large to attach.")
            return
        }
        do {
            try transfers.files.write(data, to: fileName)
        } catch {
            problem = String(localized: "That couldn't be saved on this device.")
            return
        }
        record(id: id, kind: kind, fileName: fileName, byteSize: data.count, pageCount: pageCount, caption: caption)
    }

    private func record(id: UUID, kind: AttachmentKind, fileName: String, byteSize: Int, duration: Double? = nil, pageCount: Int? = nil, caption: String = "") {
        let store = StudyStore(context: modelContext)
        let added = store.addAttachment(id: id, kind: kind, to: owner, ownerID: ownerID, byteSize: byteSize, duration: duration, pageCount: pageCount, caption: caption)
        if added == nil {
            transfers.files.remove(fileName)
            problem = String(localized: "That can't be attached here.")
        } else {
            problem = nil
        }
    }

    private func updateDrawing(_ attachment: Attachment, data: Data?) {
        let store = StudyStore(context: modelContext)
        guard let data else {
            store.delete(attachment)
            return
        }
        do {
            try transfers.files.write(data, to: attachment.fileName)
            store.attachmentFileChanged(attachment, byteSize: data.count)
        } catch {
            problem = String(localized: "That couldn't be saved on this device.")
        }
    }
}

private enum AttachmentSheet: Identifiable {
    case recorder
    case newDrawing
    case drawing(Attachment)

    var id: String {
        switch self {
        case .recorder: "recorder"
        case .newDrawing: "newDrawing"
        case let .drawing(attachment): "drawing-\(attachment.id.uuidString)"
        }
    }
}

/// Photos, PDFs and Pencil pages side by side.
private struct AttachmentStrip: View {
    let attachments: [Attachment]
    let onOpen: (Attachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { attachment in
                    Button {
                        onOpen(attachment)
                    } label: {
                        AttachmentThumbnail(attachment: attachment)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(attachment.caption.isEmpty ? attachment.kind.title : attachment.caption))
                    .accessibilityIdentifier("attachments.item")
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// A voice recording: its length and caption; tap to play.
private struct AttachmentAudioRow: View {
    let attachment: Attachment
    let onOpen: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.caption.isEmpty ? attachment.kind.title : attachment.caption)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Text(verbatim: VoiceLevel.timeText(attachment.duration ?? 0))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .foregroundStyle(palette.accent)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("attachments.recording")
    }
}
