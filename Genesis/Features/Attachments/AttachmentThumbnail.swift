import ImageIO
import PDFKit
import PencilKit
import SwiftUI
import UIKit

/// Renders attachment thumbnails away from the main thread and keeps the
/// most recent ones, keyed by attachment and edit time.
actor AttachmentThumbnails {
    static let shared = AttachmentThumbnails()

    struct Key: Hashable, Sendable {
        let id: UUID
        let version: Date
        let pixelSide: Int
    }

    private var cache: [Key: UIImage] = [:]
    private var order: [Key] = []
    private let limit = 120

    func image(for key: Key, url: URL, kind: AttachmentKind) -> UIImage? {
        if let cached = cache[key] { return cached }
        guard let image = Self.render(url, kind: kind, pixelSide: key.pixelSide) else { return nil }
        cache[key] = image
        order.append(key)
        if order.count > limit { cache[order.removeFirst()] = nil }
        return image
    }

    private static func render(_ url: URL, kind: AttachmentKind, pixelSide: Int) -> UIImage? {
        switch kind {
        case .photo:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelSide,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
        case .pdf:
            let side = CGFloat(pixelSide)
            return PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: side, height: side), for: .mediaBox)
        case .drawing:
            guard let data = try? Data(contentsOf: url), let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
            let bounds = drawing.bounds.insetBy(dx: -8, dy: -8)
            let longest = max(bounds.width, bounds.height)
            guard longest > 0 else { return nil }
            return drawing.image(from: bounds, scale: CGFloat(pixelSide) / longest)
        case .audio:
            return nil
        }
    }
}

/// A square picture of a photo, PDF's first page or Pencil page, with a
/// placeholder while the file downloads.
struct AttachmentThumbnail: View {
    let attachment: Attachment
    var side: CGFloat = 76

    @Environment(AttachmentTransfers.self) private var transfers
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(attachment.kind == .photo ? palette.background : Color.white)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: attachment.kind == .photo ? .fill : .fit)
                    .padding(attachment.kind == .photo ? 0 : 6)
            } else if transfers.downloading.contains(attachment.id) {
                ProgressView()
            } else {
                Image(systemName: transfers.unavailable.contains(attachment.id) ? "icloud.slash" : attachment.kind.systemImage)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.separator, lineWidth: 1)
        }
        .task(id: attachment.updatedAt) { await load() }
    }

    private func load() async {
        await transfers.ensureFile(for: attachment)
        guard let url = transfers.fileURL(for: attachment) else { return }
        let key = AttachmentThumbnails.Key(id: attachment.id, version: attachment.updatedAt, pixelSide: Int(side * displayScale))
        image = await AttachmentThumbnails.shared.image(for: key, url: url, kind: attachment.kind)
    }
}

/// A PDF, scrolling page by page (imported church PDFs and the export preview).
struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}
