import Photos
import UIKit

/// Saves a verse image or wallpaper to the person's photo library. Asks for
/// add-only access (Versely never reads the library this way).
enum PhotoLibrarySaver {
    enum Outcome: Equatable {
        case saved
        /// Turned off in Settings (or not allowed on this device).
        case notAllowed
        case failed
    }

    static func save(_ image: UIImage) async -> Outcome {
        guard let data = image.pngData() else { return .failed }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .notAllowed }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            return .saved
        } catch {
            return .failed
        }
    }
}

/// Opens Instagram's story editor with a verse image as the background,
/// the way Instagram documents for apps (Meta's "Sharing to Stories"): the
/// image goes on the pasteboard for five minutes and Instagram is opened
/// with our Meta App ID. Offered only when the App ID is set
/// (Config/Secrets.xcconfig, GENESIS_FACEBOOK_APP_ID) and Instagram is
/// installed. Feed posts go through the share sheet, which lists Instagram.
@MainActor
enum InstagramStories {
    private static var appID: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "GenesisFacebookAppID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // An unset build variable can arrive as "$(GENESIS_FACEBOOK_APP_ID)".
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }

    private static var url: URL? {
        appID.flatMap { URL(string: "instagram-stories://share?source_application=\($0)") }
    }

    static var isAvailable: Bool {
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting"), let url else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static func share(_ image: UIImage) {
        guard let url, let data = image.pngData() else { return }
        UIPasteboard.general.setItems(
            [["com.instagram.sharedSticker.backgroundImage": data]],
            options: [.expirationDate: Date().addingTimeInterval(5 * 60)]
        )
        UIApplication.shared.open(url)
    }
}
