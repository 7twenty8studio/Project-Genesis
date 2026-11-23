import CoreGraphics
import Foundation
import Testing
@testable import Genesis

@Suite("Scene themes")
struct SceneThemeTests {
    static let themes: [ReaderTheme] = [.forest, .ocean, .hearth]
    static let phone = CGSize(width: 390, height: 844)
    static let smallPhone = CGSize(width: 375, height: 667)
    static let iPad = CGSize(width: 1024, height: 1366)
    static let iPadSideways = CGSize(width: 1366, height: 1024)

    @Test func exactlyThreeInThePickerOrder() {
        let order = ReaderTheme.allCases.filter { $0.scene != nil }
        #expect(order == Self.themes)
        let scenes = Self.themes.compactMap { $0.scene }
        #expect(scenes == ThemeScene.allCases)
    }

    @Test func premiumAndDark() {
        for theme in Self.themes {
            let premium = theme.isPremium
            let dark = theme.isDark
            let season = theme.season
            #expect(premium, "\(theme.rawValue)")
            #expect(dark, "\(theme.rawValue)")
            #expect(season == nil, "\(theme.rawValue)")
            #expect(!theme.hasStars, "\(theme.rawValue)")
        }
    }

    @Test func wordsStayEasyToRead() {
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

    @Test func theShadeIsDeepestBehindTheWords() {
        for scene in ThemeScene.allCases {
            let shade = scene.shade
            let middle = shade.opacity(at: CGPoint(x: 195, y: 371), in: Self.phone)
            let corner = shade.opacity(at: CGPoint(x: 0, y: 844), in: Self.phone)
            #expect(middle >= 0.65, "\(scene.rawValue): \(middle)")
            #expect(corner < middle, "\(scene.rawValue)")
        }
    }

    // MARK: Composition

    @Test func thePictureCoversTheScreen() {
        for size in [Self.phone, Self.smallPhone, Self.iPad, Self.iPadSideways] {
            for scene in [ThemeScene.forest, .ocean] {
                let art = scene.artFrame(in: size, safeBottom: 20)
                let tiles = ThemeScene.tiles(of: art, across: size.width)
                let left = tiles.map { $0.frame.minX }.min() ?? 1
                let right = tiles.map { $0.frame.maxX }.max() ?? 0
                #expect(left <= 0, "\(scene.rawValue) \(size)")
                #expect(right >= size.width, "\(scene.rawValue) \(size)")
                #expect(art.minY <= 0, "\(scene.rawValue) \(size)")
                #expect(art.maxY >= size.height, "\(scene.rawValue) \(size)")
            }
        }
    }

    @Test func copiesBesideThePictureAreMirrored() {
        let art = ThemeScene.forest.artFrame(in: Self.iPadSideways, safeBottom: 20)
        let tiles = ThemeScene.tiles(of: art, across: Self.iPadSideways.width)
        let first = tiles.first
        let neighbours = tiles.dropFirst().filter { abs(abs($0.frame.minX - art.minX) - art.width) < 0.5 }
        #expect(first?.mirrored == false)
        #expect(!neighbours.isEmpty)
        let allMirrored = neighbours.allSatisfy { $0.mirrored }
        #expect(allMirrored)
        // Hearth has no picture, only its drawn glow.
        let hearth = ThemeScene.hearth.tiles(in: Self.iPadSideways, safeBottom: 20)
        #expect(hearth.isEmpty)
        #expect(ThemeScene.hearth.artName == nil)
        // A phone needs no copies.
        let phoneTiles = ThemeScene.tiles(of: ThemeScene.forest.artFrame(in: Self.phone, safeBottom: 34), across: Self.phone.width)
        #expect(phoneTiles.count == 1)
    }

    @Test func theHearthGlowRisesFromTheWholeFoot() {
        // A glow along the bottom, not a fire in one spot.
        #expect(HearthGlow.height > HearthGlow.brightBand)
        #expect(HearthGlow.height <= 0.5)
        #expect(HearthGlow.emberWidth >= 0.8)
        for step in 0..<400 {
            let time = Double(step) / 10
            let strength = HearthGlow.strength(at: time)
            #expect(strength >= 0.8 - 0.0001 && strength <= 1.0001)
            let patches = HearthGlow.patches(at: time)
            #expect(patches.count == 2)
            let left = patches[0]
            let right = patches[1]
            #expect(left.x > 0.1 && left.x < 0.5, "\(time)")
            #expect(right.x > 0.5 && right.x < 0.9, "\(time)")
            #expect(left.strength >= 0.19 && left.strength <= 1.0001)
            #expect(right.strength >= 0.19 && right.strength <= 1.0001)
        }
    }

    @Test func theWideForestKeepsItsTreesAtTheEdges() {
        let duo = CGSize(width: 951, height: 669)
        let spread = Self.iPadSideways
        let wide = CGSize(width: 2400, height: 900)
        #expect(!ForestWide.uses(Self.phone))
        #expect(!ForestWide.uses(Self.iPad))
        for size in [duo, spread, wide] {
            #expect(ForestWide.uses(size), "\(size)")
            let copies = ForestWide.copies(in: size)
            let left = copies.left
            let right = copies.right
            // Each copy covers the height, kept to the ground.
            #expect(left.minY <= 0.5 && abs(left.maxY - size.height) < 0.5, "\(size)")
            #expect(abs(left.width / left.height - ForestWide.aspect) < 0.001)
            // Together they cover the width.
            #expect(left.minX <= 0.5 && right.maxX >= size.width - 0.5, "\(size)")
            #expect(left.maxX >= right.minX, "\(size)")
            // Trees only in the outer margins: the clearing starts there.
            let leftClearing = left.minX + left.width * ForestWide.treeShare
            let rightClearing = right.maxX - right.width * ForestWide.treeShare
            #expect(abs(leftClearing - size.width * ForestWide.edgeShare) < 0.5, "\(size)")
            #expect(abs(rightClearing - size.width * (1 - ForestWide.edgeShare)) < 0.5, "\(size)")
            // They meet in the middle, where both show the clearing.
            let blend = ForestWide.blend(in: size)
            #expect(blend.lowerBound >= right.minX + right.width * ForestWide.treeShare - 0.5, "\(size)")
            #expect(blend.upperBound <= left.maxX - left.width * ForestWide.treeShare + 0.5, "\(size)")
            #expect(blend.lowerBound < size.width / 2 && blend.upperBound > size.width / 2, "\(size)")
        }
    }

    @Test func theLastLinesEndAboveTheFireAndTheSwells() {
        for (size, safeBottom) in [(Self.phone, CGFloat(34)), (Self.smallPhone, 0), (Self.iPad, 20)] {
            let usual = size.height - safeBottom - ReaderLayout.footHeight

            let hearthRoom = ThemeScene.hearth.footRoom(in: size, safeBottom: safeBottom, footHeight: ReaderLayout.footHeight)
            let brightTop = size.height * (1 - HearthGlow.brightBand)
            #expect(usual - hearthRoom <= brightTop + 0.5, "Hearth \(size)")

            let oceanRoom = ThemeScene.ocean.footRoom(in: size, safeBottom: safeBottom, footHeight: ReaderLayout.footHeight)
            let swells = OceanSwells.top(in: size) - OceanSwells.rise
            #expect(usual - oceanRoom < swells, "Ocean \(size)")

            // Still most of the screen for reading.
            #expect(hearthRoom < size.height * 0.25, "Hearth \(size): \(hearthRoom)")
            #expect(oceanRoom < size.height * 0.25, "Ocean \(size): \(oceanRoom)")
        }
        let forestRoom = ThemeScene.forest.footRoom(in: Self.phone, safeBottom: 34, footHeight: ReaderLayout.footHeight)
        #expect(forestRoom == 0)
    }

    @Test func swellsStayLowOnIPad() {
        let height = (OceanSwells.farRows - OceanSwells.farLead) * OceanSwells.scale(in: Self.iPad)
        #expect(height <= Self.iPad.height * 0.26 + 0.5)
        let phoneScale = OceanSwells.scale(in: Self.phone)
        #expect(abs(phoneScale - 390 / 1536) < 0.0001, "Full width on a phone")
    }

    // MARK: Motion

    @Test func swellsRiseAndSettleWithinTheirRoom() {
        var highest: CGFloat = 0
        var different = false
        for step in 0..<600 {
            let time = Double(step) / 10
            let far = OceanSwells.offset(near: false, at: time)
            let near = OceanSwells.offset(near: true, at: time)
            highest = max(highest, abs(far.height), abs(near.height))
            #expect(abs(far.width) <= 7 && abs(near.width) <= 7)
            if abs(far.height - near.height) > 1 { different = true }
        }
        #expect(highest <= OceanSwells.rise + 0.001)
        #expect(highest > OceanSwells.rise * 0.5, "They do move")
        #expect(different, "Out of step")
    }

    @Test func boughsSwayAndTrunksStayPlanted() {
        var widest: CGFloat = 0
        for step in 0..<400 {
            let time = Double(step) / 10
            let top = ForestSway.offset(atShare: 0, time: time)
            let canopyFoot = ForestSway.offset(atShare: ForestSway.canopy, time: time)
            let floor = ForestSway.offset(atShare: 0.9, time: time)
            widest = max(widest, abs(top))
            #expect(abs(top) <= ForestSway.reach + 0.001)
            #expect(canopyFoot == 0)
            #expect(floor == 0)
        }
        #expect(widest > ForestSway.reach * 0.6, "The branches really move")
    }

    @Test func mistWrapsOffScreen() {
        let size = Self.phone
        for layer in ForestMist.layers {
            for puff in layer.puffs {
                for second in stride(from: 0.0, through: 240.0, by: 0.5) {
                    let state = ForestMist.state(of: puff, in: layer, at: second, size: size)
                    // Never jumps on screen: when it wraps, it's beyond either edge.
                    let next = ForestMist.state(of: puff, in: layer, at: second + 0.5, size: size)
                    if next.center.x < state.center.x {
                        #expect(state.center.x - state.radii.width >= size.width - 1)
                        #expect(next.center.x + next.radii.width <= 1 + size.height * 0.2)
                    }
                    #expect(state.opacity <= 0.5)
                }
            }
        }
        #expect(ForestMist.layers.count == 2)
        let speeds = ForestMist.layers.map { $0.speed }
        #expect(speeds[0] != speeds[1])
    }

    @Test func embersFadeBeforeTheWords() {
        let source = CGPoint(x: 195, y: 760)
        let ceiling: CGFloat = 660
        var shown = 0
        var resting = 0
        for step in 0..<1200 {
            let time = Double(step) / 20
            for (index, spark) in HearthSparks.sparks.enumerated() {
                guard let state = HearthSparks.state(of: spark, index: index, at: time, source: source, width: 100, ceiling: ceiling) else {
                    resting += 1
                    continue
                }
                shown += 1
                #expect(state.point.y >= ceiling - 0.5, "spark \(index) at \(time)s")
                #expect(state.point.y <= source.y + 0.5)
                #expect(state.opacity >= 0 && state.opacity <= 1)
                #expect(state.radius > 0 && state.radius < 2)
            }
        }
        #expect(shown > 0)
        #expect(resting > 0, "Sparks come and go")
        let glow = (0..<200).map { HearthSparks.glow(at: Double($0) / 10) }
        let inRange = glow.allSatisfy { $0 >= 0 && $0 <= 1 }
        #expect(inRange)
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
