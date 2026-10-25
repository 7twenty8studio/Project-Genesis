import SwiftUI
import UIKit
import WidgetKit

/// Draws the verse widget's painted backgrounds (paper, the seasons, night)
/// into the App Group for the widget extension, which can't draw the
/// reader's seasonal art itself, and keeps the person's widget photo there.
/// Pictures only: the verse is drawn by the widget over them, verbatim.
@MainActor
enum WidgetArtWriter {
    private static let versionKey = "widgetArt.version"

    /// Draws the painted backgrounds once (and again when `WidgetArt.version`
    /// changes or a file is missing). Cheap when there's nothing to do.
    static func drawIfNeeded() {
        guard let folder = WidgetArt.folder else { return }
        let drawn = UserDefaults.standard.integer(forKey: versionKey) == WidgetArt.version
        let complete = WidgetArtStyle.painted.allSatisfy { style in
            WidgetArtShape.allCases.allSatisfy { shape in
                WidgetArt.paintedURL(style, shape: shape).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            }
        }
        guard !drawn || !complete else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for style in WidgetArtStyle.painted {
            for shape in WidgetArtShape.allCases {
                guard let url = WidgetArt.paintedURL(style, shape: shape) else { continue }
                let renderer = ImageRenderer(content: WidgetArtCanvas(style: style, size: shape.pixelSize))
                renderer.scale = 1
                guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.82) else { continue }
                try? data.write(to: url, options: .atomic)
            }
        }
        UserDefaults.standard.set(WidgetArt.version, forKey: versionKey)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.dailyVerse.rawValue)
    }

    /// Keeps a photo for the widget: at most 1200 pixels on its long side,
    /// as a JPEG without its metadata (no location travels with it).
    static func savePhoto(_ image: UIImage) throws {
        guard let folder = WidgetArt.folder, let url = WidgetArt.photoURL else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let longSide = max(image.size.width, image.size.height) * image.scale
        let factor = min(1, 1200 / max(longSide, 1))
        let target = CGSize(width: image.size.width * image.scale * factor, height: image.size.height * image.scale * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return }
        try data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.dailyVerse.rawValue)
    }

    static func removePhoto() {
        guard let url = WidgetArt.photoURL else { return }
        try? FileManager.default.removeItem(at: url)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.dailyVerse.rawValue)
    }

    static var photo: UIImage? {
        WidgetArt.photoURL.flatMap { UIImage(contentsOfFile: $0.path) }
    }
}

/// One painted background at full size: the theme's textured paper and,
/// for a season, its leaves, petals, snow or light as a still, kept to the
/// edges so the words in the middle stay clear.
struct WidgetArtCanvas: View {
    let style: WidgetArtStyle
    let size: CGSize

    var body: some View {
        let imageStyle = VerseImageStyle(rawValue: style.rawValue) ?? .paper
        ZStack {
            Image(uiImage: PaperTexture.tile(for: imageStyle.theme(reading: .paper)))
                .resizable(resizingMode: .tile)
            if let season = imageStyle.season {
                // Drawn at phone size and enlarged, as on verse images.
                SeasonalEffectView(season: season, stillTime: SeasonalEffectView.paintedMoment)
                    .frame(width: size.width / 2.5, height: size.height / 2.5)
                    .scaleEffect(2.5)
                    .frame(width: size.width, height: size.height)
                    .mask {
                        RadialGradient(
                            colors: [.black.opacity(0.1), .black.opacity(0.1), .black],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(size.width, size.height) * 0.62
                        )
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
