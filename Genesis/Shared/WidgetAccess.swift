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

/// A widget's size, without WidgetKit.
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

/// Which widgets are free. Every widget works for free in its Classic look,
/// at every size, so nothing in the widget gallery turns into a locked card
/// once it's added. Premium is what people choose inside a widget: the verse
/// widget's backgrounds and keepsakes, its categories and From Your Reading,
/// widgets in the reading theme's colours. Two widgets stay Premium because
/// their feature is: Memorize (`PremiumFeature.memorise` in the app) and the
/// listening Live Activity (`PremiumFeature.widgets`, checked in the app).
/// A Premium choice without Premium shows the Classic look with a small
/// Premium tag (`PremiumTag`).
enum WidgetAccess {
    static func isFree(kind: WidgetKind) -> Bool {
        kind != .memorise
    }

    static func isUnlocked(kind: WidgetKind, isPremium: Bool) -> Bool {
        isPremium || isFree(kind: kind)
    }

    /// The verse widget showing one of its options.
    static func isUnlocked(_ source: VerseWidgetSource, isPremium: Bool) -> Bool {
        isPremium || !source.needsPremium
    }

    /// The verse widget's background.
    static func isUnlocked(_ style: WidgetArtStyle, isPremium: Bool) -> Bool {
        isPremium || !style.needsPremium
    }
}
