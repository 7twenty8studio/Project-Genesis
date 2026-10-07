import Foundation

/// The Home Screen and Lock Screen widgets, by their WidgetKit kind string.
/// The raw values are what's installed on people's screens: never change them.
enum WidgetKind: String, CaseIterable, Sendable {
    case dailyVerse = "DailyVerse"
    case continueReading = "ContinueReading"
    case readingProgress = "ReadingProgress"
    case streak = "Streak"
    case prayerReminder = "PrayerReminder"
    case memorise = "Memorise"
    case todaysReading = "TodaysReading"
    case groupProgress = "GroupProgress"
}

/// A widget's size, without WidgetKit (so the rule below is easy to test).
enum WidgetSize: CaseIterable, Sendable {
    case small, medium, large, extraLarge
    case accessoryCircular, accessoryRectangular, accessoryInline

    /// Lock Screen (and watch-style) families.
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        case .small, .medium, .large, .extraLarge: false
        }
    }
}

/// Which widgets are free. The verse widget is the app's daily welcome: free
/// as the small and medium Home Screen widget and on the Lock Screen, showing
/// the verse of the day or a random verse. Its large size, its Premium
/// options (categories, From Your Reading) and every other widget need
/// Genesis Premium (`PremiumFeature.widgets`). Widgets keep all their sizes
/// and options in the gallery and show a calm locked card instead.
enum WidgetAccess {
    static func isFree(kind: WidgetKind, size: WidgetSize) -> Bool {
        kind == .dailyVerse && (size == .small || size == .medium || size.isAccessory)
    }

    static func isUnlocked(kind: WidgetKind, size: WidgetSize, isPremium: Bool) -> Bool {
        isPremium || isFree(kind: kind, size: size)
    }

    /// The verse widget at a size, showing one of its options.
    static func isUnlocked(_ source: VerseWidgetSource, size: WidgetSize, isPremium: Bool) -> Bool {
        isPremium || (isFree(kind: .dailyVerse, size: size) && !source.needsPremium)
    }
}
