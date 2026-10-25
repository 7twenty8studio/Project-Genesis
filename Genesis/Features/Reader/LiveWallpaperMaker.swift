import AVFoundation
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers

/// Makes a Lock Screen wallpaper that moves: a Live Photo of the verse with
/// its season's leaves, petals, snow or light drifting for a few seconds.
/// Apps can't set the wallpaper or make live ones, but a Live Photo saved to
/// Photos can be chosen in Settings › Wallpaper, and iOS plays it each time
/// the phone wakes. Premium (`.premiumThemes`, the seasonal look).
///
/// A Live Photo is a still image and a short movie that share an identifier
/// (the image's Apple maker note 17, the movie's content identifier) plus a
/// mark in the movie at the still's moment. Frames are drawn with the same
/// `VerseImageCanvas` as the still wallpaper, the verse verbatim in every one.
@MainActor
enum LiveWallpaperMaker {
    enum Failure: Error { case drawing, writing, notAllowed }

    /// 2.5 s at 30 frames: short enough for iOS to play it on the Lock Screen.
    static let duration: Double = 2.5
    static let framesPerSecond: Int32 = 30
    /// The movie's size: a 19.5:9 iPhone screen, 1080 wide.
    static let videoSize = CGSize(width: 1080, height: 2340)

    /// Draws the frames, writes the pair and saves it to Photos.
    /// `progress` goes from 0 to 1 while frames are drawn.
    static func save(card: VerseCard, style: VerseImageStyle, options: VerseImageOptions, currentTheme: ReaderTheme, progress: (Double) -> Void) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.notAllowed }

        let identifier = UUID().uuidString
        let folder = FileManager.default.temporaryDirectory.appending(path: "live-\(identifier)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let movieURL = folder.appending(path: "wallpaper.mov")
        let photoURL = folder.appending(path: "wallpaper.jpg")

        let frameCount = Int(duration * Double(framesPerSecond))
        let stillIndex = frameCount / 2
        let start = SeasonalEffectView.paintedMoment

        // The movie.
        let writer = try AVAssetWriter(outputURL: movieURL, fileType: .mov)
        writer.metadata = [contentIdentifierItem(identifier)]
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoSize.width,
            AVVideoHeightKey: videoSize.height,
        ])
        video.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: videoSize.width,
            kCVPixelBufferHeightKey as String: videoSize.height,
        ])
        let (metadataInput, metadataAdaptor) = stillImageTimeInput()
        writer.add(video)
        writer.add(metadataInput)
        guard writer.startWriting() else { throw Failure.writing }
        writer.startSession(atSourceTime: .zero)

        // Marks the still's moment in the movie.
        let stillTime = CMTime(value: CMTimeValue(stillIndex), timescale: framesPerSecond)
        let mark = AVMutableMetadataItem()
        mark.key = "com.apple.quicktime.still-image-time" as NSString
        mark.keySpace = .quickTimeMetadata
        mark.value = 0 as NSNumber
        mark.dataType = "com.apple.metadata.datatype.int8"
        metadataAdaptor.append(AVTimedMetadataGroup(items: [mark], timeRange: CMTimeRange(start: stillTime, duration: CMTime(value: 1, timescale: framesPerSecond))))
        metadataInput.markAsFinished()

        var still: CGImage?
        for index in 0..<frameCount {
            let time = start + Double(index) / Double(framesPerSecond)
            guard let image = frame(card: card, style: style, options: options, currentTheme: currentTheme, seasonTime: time) else { throw Failure.drawing }
            if index == stillIndex { still = image }
            while !video.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool, let buffer = pixelBuffer(from: image, pool: pool),
                  adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: framesPerSecond))
            else { throw Failure.writing }
            progress(Double(index + 1) / Double(frameCount))
            await Task.yield()
        }
        video.markAsFinished()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            writer.finishWriting { done.resume() }
        }
        guard writer.status == .completed, let still else { throw Failure.writing }

        // The still, with the same identifier.
        try writePhoto(still, identifier: identifier, to: photoURL)

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: photoURL, options: nil)
            request.addResource(with: .pairedVideo, fileURL: movieURL, options: nil)
        }
    }

    /// One frame: the wallpaper at a moment of its season's motion.
    private static func frame(card: VerseCard, style: VerseImageStyle, options: VerseImageOptions, currentTheme: ReaderTheme, seasonTime: TimeInterval) -> CGImage? {
        let shape = VerseImageShape.lockScreen
        let canvas = VerseImageCanvas(card: card, style: style, shape: shape, options: options, photo: nil, currentTheme: currentTheme, seasonTime: seasonTime)
            .frame(width: shape.size.width, height: shape.size.height)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = videoSize.width / shape.size.width
        return renderer.cgImage
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var created: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created) == kCVReturnSuccess, let buffer = created else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(videoSize.width),
            height: Int(videoSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // Fills the frame (the drawing can be a pixel off in height).
        context.draw(image, in: CGRect(origin: .zero, size: videoSize))
        return buffer
    }

    private static func contentIdentifierItem(_ identifier: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.key = "com.apple.quicktime.content.identifier" as NSString
        item.keySpace = .quickTimeMetadata
        item.value = identifier as NSString
        item.dataType = "com.apple.metadata.datatype.UTF-8"
        return item
    }

    private static func stillImageTimeInput() -> (AVAssetWriterInput, AVAssetWriterInputMetadataAdaptor) {
        let spec: NSDictionary = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as NSString: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as NSString: "com.apple.metadata.datatype.int8",
        ]
        var description: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [spec] as CFArray,
            formatDescriptionOut: &description
        )
        let input = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
        return (input, AVAssetWriterInputMetadataAdaptor(assetWriterInput: input))
    }

    private static func writePhoto(_ image: CGImage, identifier: String, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw Failure.writing }
        let properties: NSDictionary = [
            kCGImagePropertyMakerAppleDictionary as String: ["17": identifier],
            kCGImageDestinationLossyCompressionQuality as String: 0.92,
        ]
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw Failure.writing }
    }
}
