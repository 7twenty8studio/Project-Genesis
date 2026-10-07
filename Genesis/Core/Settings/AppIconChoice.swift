import UIKit

/// The Home Screen icon people choose in Settings › App Icon, including
/// Seasons, which changes the icon with the calendar (like the Seasons theme).
/// The standard icon is free; the others are Premium (`isPremium`).
enum AppIconChoice: String, CaseIterable, Identifiable, Sendable {
    case standard, night, autumn, winter, spring, summer, seasons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: String(localized: "Genesis", comment: "App icon name: the standard icon")
        case .night: String(localized: "Night", comment: "App icon name")
        case .autumn: String(localized: "Autumn")
        case .winter: String(localized: "Winter")
        case .spring: String(localized: "Spring")
        case .summer: String(localized: "Summer")
        case .seasons: String(localized: "Seasons", comment: "Reader theme name: follows the time of year")
        }
    }

    /// Night and the seasonal icons come with Premium (`.premiumThemes`).
    var isPremium: Bool { self != .standard }

    /// The preview image in the asset catalog.
    var previewName: String {
        switch self {
        case .standard: "IconPreview-Default"
        case .night: "IconPreview-Night"
        case .autumn, .seasons: "IconPreview-\(resolvedSeason.rawValue.capitalized)"
        case .winter: "IconPreview-Winter"
        case .spring: "IconPreview-Spring"
        case .summer: "IconPreview-Summer"
        }
    }

    private var resolvedSeason: Season {
        self == .seasons ? Season.current() : .autumn
    }

    /// The alternate icon's name for UIApplication (nil = the main icon).
    func iconName(on date: Date = .now) -> String? {
        switch self {
        case .standard: nil
        case .night: "AppIcon-Night"
        case .autumn: "AppIcon-Autumn"
        case .winter: "AppIcon-Winter"
        case .spring: "AppIcon-Spring"
        case .summer: "AppIcon-Summer"
        case .seasons: "AppIcon-\(Season.current(on: date).rawValue.capitalized)"
        }
    }
}

extension EntitlementService {
    /// The standard icon always; the others with Premium. When Premium ends
    /// the icon already set stays (iOS shows an alert whenever an icon
    /// changes, so it's never switched silently); only choosing is locked.
    func allows(icon: AppIconChoice) -> Bool {
        !icon.isPremium || allows(.premiumThemes)
    }
}

/// Applies the chosen icon. iOS shows a short notice each time an app's icon
/// changes; that's the system's and can't be turned off.
@MainActor
enum AppIcon {
    private static let key = "appIcon.choice"

    static var choice: AppIconChoice {
        get { UserDefaults.standard.string(forKey: key).flatMap(AppIconChoice.init(rawValue:)) ?? .standard }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            apply()
        }
    }

    /// Sets the icon to match the choice; with Seasons, call when the app
    /// becomes active so it moves on with the season.
    static func apply() {
        let application = UIApplication.shared
        guard application.supportsAlternateIcons else { return }
        let wanted = choice.iconName()
        guard application.alternateIconName != wanted else { return }
        application.setAlternateIconName(wanted) { _ in }
    }
}
