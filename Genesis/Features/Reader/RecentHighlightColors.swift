import Foundation

/// The highlight colors the compact selection bar shows first: the ones
/// used most recently, filled up from the default order (yellow, blue,
/// green…) so there are always the same number. Kept as a comma-separated
/// string of raw values (UserDefaults "reader.recentHighlightColors").
enum RecentHighlightColors {
    static let storageKey = "reader.recentHighlightColors"
    /// How many show in the compact bar.
    static let shownCount = 3

    /// The colors to show, most recent first.
    static func shown(from stored: String, count: Int = shownCount) -> [HighlightColor] {
        var colors: [HighlightColor] = []
        for color in decode(stored) + HighlightColor.allCases where !colors.contains(color) {
            colors.append(color)
        }
        return Array(colors.prefix(count))
    }

    /// The stored list after `color` was used: it moves to the front.
    static func recording(_ color: HighlightColor, in stored: String) -> String {
        let colors = [color] + decode(stored).filter { $0 != color }
        return colors.map(\.rawValue).joined(separator: ",")
    }

    private static func decode(_ stored: String) -> [HighlightColor] {
        stored.split(separator: ",").compactMap { HighlightColor(rawValue: String($0)) }
    }
}
