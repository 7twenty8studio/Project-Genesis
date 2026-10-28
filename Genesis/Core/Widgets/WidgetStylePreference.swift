import Foundation

/// The verse widget's look chosen in Versely (Settings › Widget Styles).
/// Widgets whose Background is "Chosen in Versely" (the default) follow it
/// through `WidgetSnapshot.verseStyle`; one widget can still pick its own
/// look in Edit Widget.
enum WidgetStylePreference {
    static let key = "widgets.verseStyle"

    static func current(_ defaults: UserDefaults = .standard) -> WidgetArtStyle {
        defaults.string(forKey: key).flatMap(WidgetArtStyle.init(rawValue:)) ?? .classic
    }

    static func set(_ style: WidgetArtStyle, defaults: UserDefaults = .standard) {
        defaults.set(style.rawValue, forKey: key)
    }
}

extension WidgetArtStyle {
    /// The order Widget Styles shows them in: the free one, the plain
    /// papers, the seasons, the keepsakes, then the person's own photo.
    static let galleryOrder: [WidgetArtStyle] = [
        .classic, .paper, .vintage, .night,
        .spring, .summer, .autumn, .winter,
        .instantPhoto, .pressedFlowers, .filmStrip, .typewriter, .libraryCard, .calendarPage,
        .photo,
    ]

    /// The style's name, as the widget's Edit Widget list has it.
    var title: String {
        switch self {
        case .classic: String(localized: "Classic")
        case .paper: String(localized: "Paper")
        case .autumn: String(localized: "Autumn")
        case .winter: String(localized: "Winter")
        case .spring: String(localized: "Spring")
        case .summer: String(localized: "Summer")
        case .night: String(localized: "Night")
        case .vintage: String(localized: "Vintage")
        case .instantPhoto: String(localized: "Instant Photo")
        case .pressedFlowers: String(localized: "Pressed Flowers")
        case .filmStrip: String(localized: "Film Strip")
        case .typewriter: String(localized: "Typewriter")
        case .libraryCard: String(localized: "Library Card")
        case .calendarPage: String(localized: "Calendar Page")
        case .photo: String(localized: "Your Photo")
        }
    }
}
