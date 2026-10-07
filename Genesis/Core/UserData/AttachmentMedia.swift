import AVFoundation
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Prepares files before they're attached: photos downscaled and re-encoded
/// without their metadata (so no location leaves the device), PDFs checked
/// and counted, recordings measured. Pure functions, safe off the main thread.
enum AttachmentMedia {
    /// A photo as stored: JPEG at `AttachmentLimits.jpegQuality`, the longer
    /// side at most `AttachmentLimits.maxPhotoPixels`, turned upright, with
    /// no EXIF, GPS or other metadata. Nil when the data isn't an image.
    static func preparedPhoto(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let size = pixelSize(of: source) else { return nil }
        let target = AttachmentLimits.scaledPixelSize(size)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(target.width, target.height)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return jpegData(image)
    }

    /// The image's pixel size as stored (before any EXIF rotation).
    private static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Encodes with no metadata at all: only the pixels are written.
    static func jpegData(_ image: CGImage, quality: CGFloat = AttachmentLimits.jpegQuality) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// True when the image carries a location (used by tests).
    static func hasLocation(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        return properties[kCGImagePropertyGPSDictionary] != nil
    }

    /// Pixel size of encoded image data (used by tests and the PDF export).
    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return pixelSize(of: source)
    }

    /// A PDF's page count, or nil when it isn't a readable PDF or is over the limit.
    static func pdfPageCount(_ data: Data) -> Int? {
        guard AttachmentLimits.fits(byteCount: data.count, kind: .pdf),
              let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else { return nil }
        return document.pageCount
    }

    /// A recording's length in seconds.
    static func audioDuration(at url: URL) -> Double? {
        guard let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 else { return nil }
        return player.duration
    }
}
