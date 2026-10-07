import PDFKit
import SwiftData
import SwiftUI

/// One attachment full screen: a photo or Pencil page to zoom, a recording
/// to play with a scrubber, or a PDF to read. With its caption, order and
/// delete (with confirmation).
struct AttachmentViewer: View {
    let attachment: Attachment
    /// Pencil pages open for editing (Premium).
    var onEditDrawing: ((Attachment) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(AttachmentTransfers.self) private var transfers
    @State private var caption = ""
    @State private var confirmDelete = false
    @State private var wasDeleted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                captionField
            }
            .themedScreen()
            .navigationTitle(attachment.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog("Delete this attachment?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    // Deleted once the viewer has gone, so nothing reads it after.
                    wasDeleted = true
                    dismiss()
                }
            }
        }
        .task { await transfers.ensureFile(for: attachment) }
        .onAppear { caption = attachment.caption }
        .onDisappear {
            let store = StudyStore(context: modelContext)
            if wasDeleted {
                store.delete(attachment)
            } else {
                store.setCaption(caption, on: attachment)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let url = transfers.fileURL(for: attachment) {
            switch attachment.kind {
            case .photo, .drawing:
                // Loaded once, not on every keystroke in the caption.
                AttachmentImage(url: url, kind: attachment.kind)
            case .pdf:
                AttachmentPDF(url: url)
            case .audio:
                VoiceNotePlayerView(url: url, duration: attachment.duration ?? 0)
            }
        } else if transfers.downloading.contains(attachment.id) {
            ProgressView("Downloading…")
        } else {
            ContentUnavailableView(
                "Not on this device yet",
                systemImage: "icloud.slash",
                description: Text("It will download when you're online. If you added it on another device, open Genesis there so it can finish uploading.")
            )
        }
    }

    private var captionField: some View {
        TextField("Add a caption", text: $caption, axis: .vertical)
            .lineLimit(1...3)
            .padding(12)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding()
            .accessibilityIdentifier("attachment.caption")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", systemImage: "checkmark") { dismiss() }
                .accessibilityIdentifier("attachment.done")
        }
        ToolbarItemGroup(placement: .topBarLeading) {
            Menu {
                if attachment.kind == .drawing, let onEditDrawing {
                    Button("Edit Drawing", systemImage: "pencil.tip") {
                        dismiss()
                        onEditDrawing(attachment)
                    }
                }
                Button("Move Earlier", systemImage: "arrow.left") {
                    StudyStore(context: modelContext).move(attachment, by: -1)
                }
                Button("Move Later", systemImage: "arrow.right") {
                    StudyStore(context: modelContext).move(attachment, by: 1)
                }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("attachment.delete")
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("attachment.more")
        }
    }
}

/// A photo or Pencil page, read from its file once.
private struct AttachmentImage: View {
    let url: URL
    let kind: AttachmentKind

    @State private var image: UIImage?

    var body: some View {
        ZoomableImage(image: image)
            .task(id: url) {
                let data = try? Data(contentsOf: url)
                image = kind == .drawing
                    ? data.flatMap { JournalExportBuilder.drawingImage($0) }.flatMap { UIImage(data: $0) }
                    : data.flatMap { UIImage(data: $0) }
            }
    }
}

/// A PDF, opened once so the page shown stays put while the caption is edited.
private struct AttachmentPDF: View {
    let url: URL

    @State private var document: PDFDocument?

    var body: some View {
        PDFKitView(document: document)
            .task(id: url) { document = PDFDocument(url: url) }
    }
}

/// A picture that zooms with a pinch (or a double tap) and pans when zoomed.
private struct ZoomableImage: View {
    let image: UIImage?

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(zoom.simultaneously(with: pan))
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) { reset(to: scale > 1 ? 1 : 2.5) }
                }
                .accessibilityLabel(Text("Photo"))
                .accessibilityAddTraits(.isImage)
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in scale = min(max(lastScale * value.magnification, 1), 5) }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 { withAnimation(.snappy) { reset(to: 1) } }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func reset(to newScale: CGFloat) {
        scale = newScale
        lastScale = newScale
        if newScale <= 1 {
            offset = .zero
            lastOffset = .zero
        }
    }
}

/// Plays a voice recording with a scrubber.
struct VoiceNotePlayerView: View {
    let url: URL
    let duration: TimeInterval

    @Environment(\.palette) private var palette
    @State private var player = VoiceNotePlayer()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 54))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(player.duration, duration, 0.1))
                .accessibilityLabel("Position")
            HStack {
                Text(verbatim: VoiceLevel.timeText(player.currentTime))
                Spacer()
                Text(verbatim: VoiceLevel.timeText(max(player.duration, duration)))
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(palette.secondaryText)
            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? Text("Pause") : Text("Play"))
            .accessibilityIdentifier("attachment.play")
        }
        .padding(32)
        .onAppear { player.load(url) }
        .onDisappear { player.stop() }
    }
}
