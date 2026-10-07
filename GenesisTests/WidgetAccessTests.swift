import Foundation
import Testing
@testable import Genesis

@Suite("Widget access and theme-matched widgets")
@MainActor
struct WidgetAccessTests {
    @Test func onlyTheSmallAndLockScreenVerseOfTheDayIsFree() {
        let free: Set<WidgetSize> = [.small, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        for size in WidgetSize.allCases {
            #expect(WidgetAccess.isFree(kind: .dailyVerse, size: size) == free.contains(size), Comment(rawValue: "Verse of the Day, \(size)"))
        }
        for kind in WidgetKind.allCases where kind != .dailyVerse {
            for size in WidgetSize.allCases {
                #expect(!WidgetAccess.isFree(kind: kind, size: size), Comment(rawValue: "\(kind.rawValue), \(size) is Premium"))
            }
        }
    }

    @Test func premiumUnlocksEveryWidget() {
        for kind in WidgetKind.allCases {
            for size in WidgetSize.allCases {
                #expect(WidgetAccess.isUnlocked(kind: kind, size: size, isPremium: true))
            }
        }
        #expect(!WidgetAccess.isUnlocked(kind: .dailyVerse, size: .medium, isPremium: false))
        #expect(!WidgetAccess.isUnlocked(kind: .streak, size: .accessoryCircular, isPremium: false))
        #expect(WidgetAccess.isUnlocked(kind: .dailyVerse, size: .accessoryInline, isPremium: false))
    }

    @Test func widgetKindsKeepTheirInstalledNames() {
        // Changing a kind would remove the widget from people's screens.
        #expect(WidgetKind.allCases.map(\.rawValue) == [
            "DailyVerse", "ContinueReading", "ReadingProgress", "Streak",
            "PrayerReminder", "Memorise", "TodaysReading", "GroupProgress",
        ])
        #expect(WidgetKind.groupProgress.rawValue == GroupWidgetSnapshot.widgetKind)
    }

    @Test func snapshotsWithoutAThemeStillDecode() throws {
        // Written before theme-matched widgets: no theme.
        let json = """
        {"generatedAt":0,"translation":"KJV","dailyVerses":[],"streakDays":2,"chaptersRead":5,"activePrayerCount":0,"isPremium":true}
        """
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.theme == nil)
        #expect(snapshot.isPremium == true)
    }

    @Test func themeRoundTrips() throws {
        var snapshot = WidgetSnapshot.placeholder
        snapshot.theme = WidgetSnapshotWriter.widgetTheme(for: .sepia)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.theme == snapshot.theme)
    }

    @Test func themeCarriesTheReaderColours() {
        let sepia = WidgetSnapshotWriter.widgetTheme(for: .sepia)
        #expect(sepia.name == "sepia")
        #expect(sepia.light == sepia.dark, "A fixed theme looks the same by day and night")
        #expect(sepia.light.background == ReaderTheme.sepia.palette.backgroundHex)
        #expect(sepia.light.accent == ReaderTheme.sepia.palette.accentHex)
        #expect(!sepia.light.hasPaperTexture)

        let automatic = WidgetSnapshotWriter.widgetTheme(for: .automatic)
        #expect(automatic.light.background == ReaderTheme.paper.palette.backgroundHex)
        #expect(automatic.dark.background == ReaderTheme.slate.palette.backgroundHex)
        #expect(automatic.dark.isDark)

        let parchment = WidgetSnapshotWriter.widgetTheme(for: .parchment)
        #expect(parchment.light.hasPaperTexture, "Premium themes keep their paper look")
    }
}
