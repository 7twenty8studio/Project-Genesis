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

    /// The pictures drawn so far for the current `WidgetArt.version`
    /// ("autumn-large", …), so drawing that was cut short (the app closed
    /// midway) carries on where it stopped instead of starting over.
    private static let progressKey = "widgetArt.drawnFiles"
    private static var isDrawing = false

    /// Draws the painted backgrounds once (and again when `WidgetArt.version`
    /// changes or a file is missing). Cheap when there's nothing to do.
    ///
    /// Eighteen full-size paintings take several seconds, which froze the
    /// app on launch (Sentry APPLE-IOS-2, "App hanging for at least 2000
    /// ms"). So they're drawn a moment after launch, one at a time, with
    /// the screen free to update in between; each one is kept as soon as
    /// it's drawn.
    static func drawIfNeeded() {
        guard !isDrawing, let folder = WidgetArt.folder else { return }
        let defaults = UserDefaults.standard
        let current = defaults.integer(forKey: versionKey) == WidgetArt.version
        let done = current ? Set<String>() : Set(defaults.stringArray(forKey: progressKey) ?? [])
        let missing = WidgetArtStyle.painted.flatMap { style in
            WidgetArtShape.allCases.map { (style, $0) }
        }.filter { style, shape in
            guard let url = WidgetArt.paintedURL(style, shape: shape) else { return false }
            let exists = FileManager.default.fileExists(atPath: url.path)
            // An older version's picture is drawn again unless this
            // version's run already did it.
            return !exists || (!current && !done.contains(name(style, shape)))
        }
        guard !missing.isEmpty else {
            if !current { finish() }
            return
        }
        isDrawing = true
        Task { @MainActor in
            defer { isDrawing = false }
            // Let launch (or the screen just opened) finish first.
            try? await Task.sleep(for: .seconds(2))
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var drawnNames = done
            for (style, shape) in missing {
                guard let url = WidgetArt.paintedURL(style, shape: shape) else { continue }
                let renderer = ImageRenderer(content: WidgetArtCanvas(style: style, size: shape.pixelSize))
                renderer.scale = 1
                if let data = renderer.uiImage?.jpegData(compressionQuality: 0.82), (try? data.write(to: url, options: .atomic)) != nil {
                    drawnNames.insert(name(style, shape))
                    defaults.set(Array(drawnNames), forKey: progressKey)
                }
                // Give the screen its turn before the next picture.
                try? await Task.sleep(for: .milliseconds(150))
            }
            let complete = missing.allSatisfy { style, shape in
                WidgetArt.paintedURL(style, shape: shape).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            }
            if complete { finish() }
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.dailyVerse.rawValue)
        }
    }

    private static func name(_ style: WidgetArtStyle, _ shape: WidgetArtShape) -> String {
        "\(style.rawValue)-\(shape.rawValue)"
    }

    private static func finish() {
        UserDefaults.standard.set(WidgetArt.version, forKey: versionKey)
        UserDefaults.standard.removeObject(forKey: progressKey)
    }

    /// Keeps a photo for the widget: at most 2400 pixels on its long side
    /// (room to zoom in), as a JPEG without its metadata (no location
    /// travels with it), framed in the middle for every widget size until
    /// the person moves it.
    static func savePhoto(_ image: UIImage) throws {
        guard let folder = WidgetArt.folder, let url = WidgetArt.photoURL else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let longSide = max(image.size.width, image.size.height) * image.scale
        let factor = min(1, 2400 / max(longSide, 1))
        let target = CGSize(width: image.size.width * image.scale * factor, height: image.size.height * image.scale * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return }
        try data.write(to: url, options: .atomic)
        for shape in WidgetArtShape.allCases {
            UserDefaults.standard.removeObject(forKey: framingKey(shape))
        }
        saveFramings([:], photo: resized)
    }

    /// The framing kept for one widget shape (the middle, if never moved).
    static func framing(for shape: WidgetArtShape) -> PhotoFraming {
        guard let data = UserDefaults.standard.data(forKey: framingKey(shape)),
              let framing = try? JSONDecoder().decode(PhotoFraming.self, from: data) else { return PhotoFraming() }
        return framing
    }

    /// Keeps each shape's framing and writes the photo cut to each shape
    /// at the widget's full size.
    static func saveFramings(_ framings: [WidgetArtShape: PhotoFraming], photo: UIImage? = nil) {
        guard let photo = photo ?? self.photo, let cgImage = photo.cgImage else { return }
        let pixels = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        for shape in WidgetArtShape.allCases {
            let framing = framings[shape] ?? framing(for: shape)
            if let data = try? JSONEncoder().encode(framing) {
                UserDefaults.standard.set(data, forKey: framingKey(shape))
            }
            let size = shape.pixelSize
            let crop = framing.crop(imageSize: pixels, aspect: size.width / size.height)
            guard let url = WidgetArt.framedPhotoURL(shape), let cut = cgImage.cropping(to: crop.integral) else { continue }
            let framed = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                UIImage(cgImage: cut).draw(in: CGRect(origin: .zero, size: size))
            }
            try? framed.jpegData(compressionQuality: 0.85)?.write(to: url, options: .atomic)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.dailyVerse.rawValue)
    }

    private static func framingKey(_ shape: WidgetArtShape) -> String {
        "widgetPhoto.framing.\(shape.rawValue)"
    }

    static func removePhoto() {
        let urls = [WidgetArt.photoURL] + WidgetArtShape.allCases.map(WidgetArt.framedPhotoURL)
        for url in urls.compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        for shape in WidgetArtShape.allCases {
            UserDefaults.standard.removeObject(forKey: framingKey(shape))
        }
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
