import Foundation
import Testing
@testable import Genesis

@Suite("Widget access and theme-matched widgets")
@MainActor
struct WidgetAccessTests {
    @Test func everyWidgetButMemorizeIsFree() {
        for kind in WidgetKind.allCases {
            #expect(WidgetAccess.isFree(kind: kind) == (kind != .memorise), Comment(rawValue: kind.rawValue))
            #expect(WidgetAccess.isUnlocked(kind: kind, isPremium: false) == (kind != .memorise), Comment(rawValue: kind.rawValue))
        }
    }

    @Test func premiumUnlocksEveryWidget() {
        for kind in WidgetKind.allCases {
            #expect(WidgetAccess.isUnlocked(kind: kind, isPremium: true))
        }
    }

    @Test func verseOfTheDayAndRandomVerseAreFree() {
        let free: Set<VerseWidgetSource> = [.verseOfTheDay, .random]
        for source in VerseWidgetSource.allCases {
            #expect(WidgetAccess.isUnlocked(source, isPremium: false) == free.contains(source), Comment(rawValue: source.rawValue))
            #expect(WidgetAccess.isUnlocked(source, isPremium: true))
        }
    }

    @Test func onlyTheClassicBackgroundIsFree() {
        for style in WidgetArtStyle.allCases {
            #expect(WidgetAccess.isUnlocked(style, isPremium: false) == (style == .classic), Comment(rawValue: style.rawValue))
            #expect(WidgetAccess.isUnlocked(style, isPremium: true))
        }
    }

    @Test func widgetStylesListEveryStyleOnce() {
        #expect(Set(WidgetArtStyle.galleryOrder) == Set(WidgetArtStyle.allCases))
        #expect(WidgetArtStyle.galleryOrder.count == WidgetArtStyle.allCases.count)
        #expect(WidgetArtStyle.galleryOrder.first == .classic, "The free style first")
    }

    @Test func theStyleChosenInVerselyReachesTheSnapshot() throws {
        let defaults = try #require(UserDefaults(suiteName: "WidgetStyle-\(UUID().uuidString)"))
        #expect(WidgetStylePreference.current(defaults) == .classic)
        WidgetStylePreference.set(.pressedFlowers, defaults: defaults)
        #expect(WidgetStylePreference.current(defaults) == .pressedFlowers)

        var snapshot = WidgetSnapshot.placeholder
        #expect(snapshot.chosenVerseStyle == .classic, "Older snapshots keep the Classic look")
        snapshot.verseStyle = WidgetArtStyle.night.rawValue
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.chosenVerseStyle == .night)
    }

    @Test func verseWidgetOptionsKeepTheirSavedNames() {
        // Installed widgets save these; GenesisWidgets' VerseWidgetOption mirrors them.
        #expect(VerseWidgetSource.allCases.map(\.rawValue) == [
            "verseOfTheDay", "random", "fromYourReading",
            "hope", "peace", "faith", "strength", "comfort", "love", "gratitude", "guidance",
        ])
        let categories = VerseWidgetSource.allCases.compactMap(\.category)
        #expect(categories == VerseCategory.allCases)
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
