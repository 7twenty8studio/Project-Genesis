import PencilKit
import SwiftUI
import UIKit

/// Renders handwritten pages as small images away from the main thread and
/// keeps the most recent ones, keyed by note and edit time.
actor DrawingThumbnails {
    static let shared = DrawingThumbnails()

    struct Key: Hashable, Sendable {
        let noteID: UUID
        let version: Date
        let pixelSide: Int
    }

    private var cache: [Key: UIImage] = [:]
    private var order: [Key] = []
    private let limit = 80

    func image(for key: Key, data: Data, side: CGFloat, scale: CGFloat) -> UIImage? {
        if let cached = cache[key] { return cached }
        guard let image = Self.render(data, side: side, scale: scale) else { return nil }
        cache[key] = image
        order.append(key)
        if order.count > limit {
            cache[order.removeFirst()] = nil
        }
        return image
    }

    /// The whole drawing, fitted into a square of `side` points.
    private static func render(_ data: Data, side: CGFloat, scale: CGFloat) -> UIImage? {
        guard let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -8, dy: -8)
        let longest = max(bounds.width, bounds.height)
        guard longest > 0 else { return nil }
        return drawing.image(from: bounds, scale: side / longest * scale)
    }
}

/// A small picture of a note's handwritten page, for note lists. Shows
/// nothing for notes without one.
struct NoteDrawingThumbnail: View {
    let note: Note
    var side: CGFloat = 52

    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .frame(width: image == nil ? 0 : side, height: image == nil ? 0 : side)
            .overlay {
                if let image { thumbnail(image) }
            }
            .task(id: note.updatedAt) { await load() }
    }

    private func thumbnail(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .inkForPaper(isDark: palette.isDarkPaper)
            .padding(4)
            .frame(width: side, height: side)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.separator, lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Handwritten note"))
            .accessibilityIdentifier("note.thumbnail")
    }

    private func load() async {
        guard let data = note.drawing else {
            image = nil
            return
        }
        let key = DrawingThumbnails.Key(noteID: note.id, version: note.updatedAt, pixelSide: Int(side * displayScale))
        image = await DrawingThumbnails.shared.image(for: key, data: data, side: side, scale: displayScale)
    }
}

private extension View {
    /// Thumbnails are drawn as on light paper; on dark paper, flip the ink's
    /// lightness (keeping its hue), as PencilKit does on screen.
    @ViewBuilder
    func inkForPaper(isDark: Bool) -> some View {
        if isDark {
            colorInvert().hueRotation(.degrees(180))
        } else {
            self
        }
    }
}
