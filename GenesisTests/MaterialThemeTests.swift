import CoreGraphics
import Foundation
import Testing
@testable import Genesis

@Suite("Material themes")
struct MaterialThemeTests {
    static let themes: [ReaderTheme] = [.hearth, .leatherBound, .cedar, .highlands, .galileeStorm, .ironstone]

    @Test func theyComeInThePickerOrder() {
        let order = ReaderTheme.allCases.filter { $0.scenery != nil }
        #expect(order == Self.themes)
    }

    @Test func allSixArePremium() {
        for theme in Self.themes {
            #expect(theme.isPremium, "\(theme.rawValue)")
            #expect(theme.hasPaperTexture, "\(theme.rawValue)")
            #expect(theme.season == nil, "\(theme.rawValue)")
            #expect(!theme.hasStars, "\(theme.rawValue)")
        }
    }

    @Test func darkAndLightPages() {
        let dark = Self.themes.filter(\.isDark)
        #expect(dark == [.hearth, .galileeStorm, .ironstone])
    }

    @Test func eachHasItsOwnScenery() {
        let sceneries = Self.themes.compactMap(\.scenery)
        #expect(sceneries == ThemeScenery.allCases)
        let moving = ThemeScenery.allCases.filter(\.moves)
        #expect(moving == [.hearth, .highlands, .galileeStorm])
        let paper = ThemeScenery.allCases.filter(\.turnsLikePaper)
        #expect(paper == [.leatherBound, .cedar])
        let others = ReaderTheme.allCases.filter { !Self.themes.contains($0) }.compactMap(\.scenery)
        #expect(others.isEmpty)
    }

    @Test func wordsStayEasyToReadForAWholeChapter() {
        for theme in Self.themes {
            let palette = theme.palette
            let body = Self.contrast(palette.textHex, palette.backgroundHex)
            let onSurface = Self.contrast(palette.textHex, palette.surfaceHex)
            let secondary = Self.contrast(palette.secondaryTextHex, palette.backgroundHex)
            let accent = Self.contrast(palette.accentHex, palette.backgroundHex)
            #expect(body >= 10, "\(theme.rawValue) body text: \(body)")
            #expect(onSurface >= 4.5, "\(theme.rawValue) text on surfaces")
            #expect(secondary >= 4.5, "\(theme.rawValue) secondary text: \(secondary)")
            #expect(accent >= 4.5, "\(theme.rawValue) accent: \(accent)")
        }
    }

    // MARK: Where the scenery goes

    static let phone = SceneryArea(size: CGSize(width: 390, height: 844), top: 115, left: 18, bottom: 70, right: 18, topBand: 65, footBand: 40)

    @Test func sideMaterialsAreSlimOnPhonesAndWiderOnIPad() {
        #expect(Self.phone.sideWidth(maximum: 56) == 9)
        var iPad = Self.phone
        iPad.size = CGSize(width: 1024, height: 1366)
        iPad.left = 160
        iPad.right = 160
        #expect(iPad.sideWidth(maximum: 56) == 56)
        var tight = Self.phone
        tight.left = 4
        #expect(tight.sideWidth(maximum: 56) == 6)
    }

    @Test func footDecorationFoldsAwayWithoutRoom() {
        #expect(Self.phone.footDecoration == 40)
        var homeButton = Self.phone
        homeButton.footBand = 6
        #expect(homeButton.footDecoration == 0)
    }

    @Test func theTextAreaIsKeptClear() {
        #expect(Self.phone.isInText(CGPoint(x: 195, y: 400)))
        #expect(!Self.phone.isInText(CGPoint(x: 8, y: 400)))
        #expect(!Self.phone.isInText(CGPoint(x: 195, y: 820)))
        #expect(!Self.phone.isInText(CGPoint(x: 195, y: 30)))
    }

    // MARK: Motion

    @Test func theHorizonBrightensGentlyNowAndThen() {
        var brightest = 0.0
        var lit = 0
        let steps = Int(StormFlash.cycle * 20)
        for step in 0..<steps {
            let value = StormFlash.intensity(at: Double(step) / 20)
            #expect(value >= 0 && value <= 1)
            brightest = max(brightest, value)
            if value > 0.05 { lit += 1 }
        }
        #expect(brightest > 0.5, "It does brighten")
        #expect(Double(lit) / Double(steps) < 0.2, "Mostly calm")
        #expect(StormFlash.intensity(at: 0) == 0)
        #expect(StormFlash.intensity(at: -3) == 0)
    }

    @Test func embersDieOutLowOnThePage() {
        let page = CGSize(width: 390, height: 844)
        for second in stride(from: 0.0, through: 60.0, by: 0.5) {
            for (index, ember) in HearthEmbers.embers.enumerated() {
                let state = HearthEmbers.state(of: ember, index: index, at: CGFloat(second), page: page)
                let lowOnThePage = state.point.y >= page.height * (1 - HearthEmbers.reach) - 1
                #expect(lowOnThePage, "ember \(index) at \(second)s: \(state.point.y)")
                #expect(state.opacity >= 0 && state.opacity <= 1)
            }
        }
        #expect(HearthEmbers.embers.count == 12)
    }

    /// WCAG relative luminance contrast ratio.
    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let first = luminance(a)
        let second = luminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}
