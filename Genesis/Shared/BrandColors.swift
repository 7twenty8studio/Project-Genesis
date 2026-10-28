import SwiftUI

/// Versely's four brand colors (the logo kit's palette), for the places that
/// wear the brand itself rather than the reading theme: the welcome screen
/// and the Classic widgets.
enum BrandColors {
    static let cream = Color(red: 0xF9 / 255, green: 0xEB / 255, blue: 0xD7 / 255)
    static let sand = Color(red: 0xE0 / 255, green: 0xB4 / 255, blue: 0x8D / 255)
    static let copper = Color(red: 0xB9 / 255, green: 0x82 / 255, blue: 0x5A / 255)
    static let walnut = Color(red: 0x7A / 255, green: 0x4E / 255, blue: 0x2D / 255)
    /// Walnut's deepest shade, for text on cream.
    static let ink = Color(red: 0x4A / 255, green: 0x2E / 255, blue: 0x1A / 255)

    /// The copper-to-walnut gradient of the brand's buttons.
    static let buttonGradient = LinearGradient(
        colors: [Color(red: 0xC6 / 255, green: 0x93 / 255, blue: 0x6A / 255), walnut],
        startPoint: .top,
        endPoint: .bottom
    )
}
