import Foundation

/// The verse widget's backgrounds (Premium, except Classic). The raw values
/// are saved in installed widgets' configurations: never change them.
enum WidgetArtStyle: String, CaseIterable, Codable, Sendable {
    /// Today's look: plain, or the reading theme's colours with Premium.
    case classic
    case paper, autumn, winter, spring, summer, night
    /// A postcard: cream paper, a stamp and a postmark, drawn by the widget.
    case vintage
    /// A photo the person chose in Versely (Settings › Widget Photo).
    case photo

    var needsPremium: Bool { self != .classic }

    /// Words go in light ink on these (dark art or a shaded photo).
    var isDark: Bool { self == .night || self == .photo }

    /// The painted backgrounds the app draws for the widget.
    static let painted: [WidgetArtStyle] = [.paper, .autumn, .winter, .spring, .summer, .night]
}

/// The widget's three Home Screen shapes, each with its own picture so the
/// art isn't stretched.
enum WidgetArtShape: String, CaseIterable, Sendable {
    case small, medium, large

    /// Pixels: the largest iPhone's widget at 3×, rounded up.
    var pixelSize: CGSize {
        switch self {
        case .small: CGSize(width: 520, height: 520)
        case .medium: CGSize(width: 1100, height: 520)
        case .large: CGSize(width: 1100, height: 1160)
        }
    }
}

/// Where the widget pictures live: the App Group container, written by the
/// app (`WidgetArtWriter`) and read by the widget extension. No Scripture in
/// them: the verse is always drawn by the widget, verbatim, over the art.
enum WidgetArt {
    /// Bump to have the app draw the painted art again (after changing it).
    static let version = 1

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?
            .appending(path: "WidgetArt", directoryHint: .isDirectory)
    }

    static func paintedURL(_ style: WidgetArtStyle, shape: WidgetArtShape) -> URL? {
        folder?.appending(path: "\(style.rawValue)-\(shape.rawValue).jpg")
    }

    /// The person's photo, prepared for the widget (at most 1200 pixels).
    static var photoURL: URL? {
        folder?.appending(path: "photo.jpg")
    }

    static func url(_ style: WidgetArtStyle, shape: WidgetArtShape) -> URL? {
        switch style {
        case .classic, .vintage: nil
        case .photo: photoURL
        default: paintedURL(style, shape: shape)
        }
    }
}
