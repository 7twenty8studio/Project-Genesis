import CoreGraphics

/// How the person framed their widget photo for one widget shape: how far
/// it's zoomed in and which point of the photo sits in the middle. Pure, so
/// the editor's gestures and the saved crop agree exactly.
struct PhotoFraming: Codable, Equatable, Sendable {
    /// 1 fills the shape with the whole photo's width or height; more is closer.
    var zoom: Double = 1
    /// The middle of the crop, as a fraction of the photo (0…1).
    var centerX: Double = 0.5
    var centerY: Double = 0.5

    static let maxZoom: Double = 5

    /// The part of the photo (in its pixels) that fills a frame of this
    /// shape, always inside the photo.
    func crop(imageSize: CGSize, aspect: CGFloat) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, aspect > 0 else { return .zero }
        // At zoom 1: the largest rectangle of this shape that fits the photo.
        var width = imageSize.width
        var height = width / aspect
        if height > imageSize.height {
            height = imageSize.height
            width = height * aspect
        }
        let zoom = min(max(self.zoom, 1), Self.maxZoom)
        width /= zoom
        height /= zoom
        let x = min(max(centerX * imageSize.width - width / 2, 0), imageSize.width - width)
        let y = min(max(centerY * imageSize.height - height / 2, 0), imageSize.height - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The same framing, with its middle moved back where the crop really
    /// is (so a pan past the edge doesn't build up unseen).
    func clamped(imageSize: CGSize, aspect: CGFloat) -> PhotoFraming {
        let rect = crop(imageSize: imageSize, aspect: aspect)
        guard imageSize.width > 0, imageSize.height > 0 else { return self }
        return PhotoFraming(
            zoom: min(max(zoom, 1), Self.maxZoom),
            centerX: rect.midX / imageSize.width,
            centerY: rect.midY / imageSize.height
        )
    }

    /// Dragging the photo by `translation` points in a frame of `frameSize`:
    /// the photo follows the finger, so the crop moves the other way.
    func panned(by translation: CGSize, frameSize: CGSize, imageSize: CGSize) -> PhotoFraming {
        guard frameSize.width > 0, frameSize.height > 0 else { return self }
        let aspect = frameSize.width / frameSize.height
        let rect = crop(imageSize: imageSize, aspect: aspect)
        let pixelsPerPoint = rect.width / frameSize.width
        var moved = self
        moved.centerX = rect.midX / imageSize.width - Double(translation.width * pixelsPerPoint / imageSize.width)
        moved.centerY = rect.midY / imageSize.height - Double(translation.height * pixelsPerPoint / imageSize.height)
        return moved.clamped(imageSize: imageSize, aspect: aspect)
    }

    /// Pinching by `factor` (1 = no change), keeping the middle where it is.
    func zoomed(by factor: Double, imageSize: CGSize, aspect: CGFloat) -> PhotoFraming {
        var zoomed = clamped(imageSize: imageSize, aspect: aspect)
        zoomed.zoom = min(max(zoomed.zoom * factor, 1), Self.maxZoom)
        return zoomed.clamped(imageSize: imageSize, aspect: aspect)
    }
}
