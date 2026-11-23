import CoreGraphics
import Foundation

/// The illustrated scene behind the words in the scene themes (Premium):
/// Forest, Ocean and Hearth. The pictures are the owner-approved
/// illustrations (Tools/Themes/make_scenes.py); `ThemeSceneView` draws them
/// behind the live text with a soft shade where the words sit, and moves one
/// thing in each: mist in the Forest, swells on the Ocean, embers at the
/// Hearth. Everything here is pure, so tests and the still agree.
enum ThemeScene: String, CaseIterable, Sendable {
    case forest, ocean, hearth

    /// The picture in the asset catalog.
    var artName: String {
        switch self {
        case .forest: "ThemeSceneForest"
        case .ocean: "ThemeSceneOcean"
        case .hearth: "ThemeSceneHearth"
        }
    }

    /// Every scene picture is 1536 × 2752 px.
    static let artAspect: CGFloat = 1536.0 / 2752.0

    /// The colour around the picture where it doesn't reach: only Hearth's
    /// fire is drawn smaller than the screen, on the picture's own charcoal.
    var fillHex: UInt32 {
        switch self {
        case .forest: 0x1E3A2E
        case .ocean: 0x6A7A93
        case .hearth: 0x271C18
        }
    }

    /// Where the picture goes on a reading area (`size` is the whole area,
    /// `safeBottom` the home indicator's band).
    ///
    /// - Forest fills the height, centred.
    /// - Ocean is a little taller than the screen, from the top, so its
    ///   far water (and the bright line along it) sits low, under the last
    ///   lines' shade; the swells are separate layers (`OceanSwells`).
    /// - Hearth's fire is smaller, centred, its stones just above the page
    ///   number, so the glow stays under the words and the counter clear.
    func artFrame(in size: CGSize, safeBottom: CGFloat) -> CGRect {
        switch self {
        case .forest:
            let height = size.height
            let width = height * Self.artAspect
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: height)
        case .ocean:
            let height = size.height * 1.18
            let width = height * Self.artAspect
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: height)
        case .hearth:
            let height = Hearth.artHeight(for: size)
            let width = height * Self.artAspect
            let stonesBottom = size.height - safeBottom - Hearth.counterClearance
            let bottom = stonesBottom + height * (1 - Hearth.stonesBottom)
            return CGRect(x: (size.width - width) / 2, y: bottom - height, width: width, height: height)
        }
    }

    /// The picture and, for Forest and Ocean, mirrored copies beside it
    /// where it's narrower than the area (Hearth's fire stands alone on its
    /// charcoal).
    func tiles(in size: CGSize, safeBottom: CGFloat) -> [SceneTile] {
        let art = artFrame(in: size, safeBottom: safeBottom)
        return self == .hearth ? [SceneTile(frame: art, mirrored: false)] : Self.tiles(of: art, across: size.width)
    }

    /// The copies of the picture that cover the area: the picture itself,
    /// then mirrored copies beside it while it's narrower than the area (an
    /// iPad held sideways). Mirrored, so the edges meet without a seam.
    static func tiles(of frame: CGRect, across width: CGFloat) -> [SceneTile] {
        guard frame.width > 0 else { return [] }
        var tiles = [SceneTile(frame: frame, mirrored: false)]
        var step = 1
        while frame.minX - CGFloat(step - 1) * frame.width > 0 || frame.maxX + CGFloat(step - 1) * frame.width < width {
            let mirrored = !step.isMultiple(of: 2)
            let offset = CGFloat(step) * frame.width
            tiles.append(SceneTile(frame: frame.offsetBy(dx: -offset, dy: 0), mirrored: mirrored))
            tiles.append(SceneTile(frame: frame.offsetBy(dx: offset, dy: 0), mirrored: mirrored))
            step += 1
        }
        return tiles.filter { $0.frame.maxX > 0 && $0.frame.minX < width }
    }

    /// Room kept free under the text (on top of the usual footer), so the
    /// last lines end above the fire's glow and the swells. Pages hold less
    /// text; a long chapter flows on to the next page as usual.
    func footRoom(in size: CGSize, safeBottom: CGFloat, footHeight: CGFloat) -> CGFloat {
        let textBottom = size.height - safeBottom - footHeight
        let limit: CGFloat
        switch self {
        case .forest:
            return 0
        case .ocean:
            // Above the highest the swells rise, and a little more.
            limit = OceanSwells.top(in: size) - OceanSwells.rise - 6
        case .hearth:
            // Above the smoke and the top of the glow.
            let art = artFrame(in: size, safeBottom: safeBottom)
            limit = art.minY + art.height * Hearth.glowTop
        }
        return max(0, (textBottom - limit).rounded(.up))
    }

    /// The soft shade behind the words: an ellipse of the scene's own dark
    /// colour, strongest where the text is, fading toward the edges so the
    /// picture shows around it.
    var shade: SceneShade {
        switch self {
        case .forest:
            SceneShade(hex: 0x14241F, center: CGPoint(x: 0.5, y: 0.46), radii: CGSize(width: 0.75, height: 0.58),
                       stops: [(0, 0.82), (0.7, 0.62), (1, 0.15)])
        case .ocean:
            SceneShade(hex: 0x161F29, center: CGPoint(x: 0.5, y: 0.44), radii: CGSize(width: 0.85, height: 0.62),
                       stops: [(0, 0.76), (0.72, 0.42), (1, 0)])
        case .hearth:
            SceneShade(hex: 0x1A1411, center: CGPoint(x: 0.5, y: 0.42), radii: CGSize(width: 0.85, height: 0.6),
                       stops: [(0, 0.72), (0.7, 0.35), (1, 0)])
        }
    }

    /// The moment shown when nothing moves (Reduce Motion, Low Power Mode,
    /// Gentle Motion off): a composed still, embers mid-rise.
    static let stillTime: Double = 7.4

    /// Hearth's fire in its picture (shares of the picture's height).
    enum Hearth {
        /// The bottom of the stones.
        static let stonesBottom: CGFloat = 0.93
        /// The coals, where embers start.
        static let coals = CGPoint(x: 0.5, y: 0.855)
        /// How wide the bed of coals is (share of the picture's width).
        static let coalsWidth: CGFloat = 0.46
        /// The top of the smoke and of the glow worth keeping clear of text.
        static let glowTop: CGFloat = 0.64
        /// Points between the stones and the page number's band.
        static let counterClearance: CGFloat = 34

        /// The fire is drawn at half the screen's height, at most 460 pt.
        static func artHeight(for size: CGSize) -> CGFloat {
            min(size.height * 0.5, 460)
        }
    }
}

/// One copy of a scene's picture.
struct SceneTile: Equatable, Sendable {
    var frame: CGRect
    var mirrored: Bool
}

/// A scene's shade behind the words: an ellipse (centre and radii as shares
/// of the area) with opacity stops from the centre out.
struct SceneShade: Sendable {
    var hex: UInt32
    var center: CGPoint
    var radii: CGSize
    var stops: [(location: CGFloat, opacity: CGFloat)]

    /// The shade's opacity at a point of the area.
    func opacity(at point: CGPoint, in size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 0 }
        let dx = (point.x / size.width - center.x) / radii.width
        let dy = (point.y / size.height - center.y) / radii.height
        let distance = min(1, (dx * dx + dy * dy).squareRoot())
        guard let after = stops.firstIndex(where: { $0.location >= distance }) else { return stops.last?.opacity ?? 0 }
        guard after > 0 else { return stops[0].opacity }
        let a = stops[after - 1], b = stops[after]
        let t = (distance - a.location) / max(0.0001, b.location - a.location)
        return a.opacity + (b.opacity - a.opacity) * t
    }
}

// MARK: - Motion

/// The Ocean's swells: two layers cut from the picture (the far swells and
/// the nearer ones), at the foot of the screen, below the text. Each rises
/// and settles and leans a little sideways, out of step with the other.
enum OceanSwells {
    /// The layers' pictures, their first row in the original and padding
    /// (mirrored in Tools/Themes/make_scenes.py).
    static let farName = "ThemeSceneOceanSwell"
    static let nearName = "ThemeSceneOceanNearSwell"
    static let contentWidth: CGFloat = 1536
    /// The far layer's rows: a lead-in of the water's colour fading in
    /// (so it meets the lake above without an edge), then the swells.
    static let farRows: CGFloat = 802
    static let farLead: CGFloat = 120
    static let nearRows: CGFloat = 352
    static let sidePad: CGFloat = 40
    static let bottomPad: CGFloat = 80
    /// The most a layer rises above its resting place, in points.
    static let rise: CGFloat = 5

    /// Points per picture pixel: the width of the screen, unless that
    /// makes the swells taller than a quarter of it (an iPad), when they're
    /// smaller and repeat, mirrored, across.
    static func scale(in size: CGSize) -> CGFloat {
        min(size.width / contentWidth, size.height * 0.26 / (farRows - farLead))
    }

    /// Where the swells begin (below the lead-in, which is only colour).
    static func top(in size: CGSize) -> CGFloat {
        size.height - (farRows - farLead) * scale(in: size)
    }

    /// A layer's frame at rest, padding included, centred.
    static func frame(near: Bool, in size: CGSize) -> CGRect {
        let s = scale(in: size)
        let rows = near ? nearRows : farRows
        let width = (contentWidth + sidePad * 2) * s
        return CGRect(x: (size.width - width) / 2, y: size.height - rows * s, width: width, height: (rows + bottomPad) * s)
    }

    /// The width one copy covers (without its padding), for repeating.
    static func period(in size: CGSize) -> CGFloat {
        contentWidth * scale(in: size)
    }

    /// How far a layer is moved at `time`: up and down within `rise`, and a
    /// few points sideways; the near layer is quicker and out of step.
    static func offset(near: Bool, at time: Double) -> CGSize {
        let tau = 2 * Double.pi
        if near {
            let y = 0.62 * sin(tau * time / 5.9 + 1.9) + 0.38 * sin(tau * time / 3.7 + 0.4)
            let x = -sin(tau * time / 9.4 + 0.7)
            return CGSize(width: 7 * x, height: Double(rise) * y)
        } else {
            let y = 0.7 * sin(tau * time / 7.3) + 0.3 * sin(tau * time / 4.6 + 2.2)
            let x = sin(tau * time / 11.2 + 0.3)
            return CGSize(width: 5 * x, height: Double(rise) * 0.8 * y)
        }
    }
}

/// The Forest's mist: two translucent layers of soft puffs drifting slowly
/// sideways between the trunks, at different speeds, under the shade.
enum ForestMist {
    struct Puff: Sendable {
        /// Place along the layer (0...1) and height (share of the area).
        let x, y: CGFloat
        /// Radii as shares of the area's height.
        let width, height: CGFloat
        let opacity: CGFloat
        let bob: CGFloat
    }

    struct Layer: Sendable {
        let puffs: [Puff]
        /// Points per second, to the right.
        let speed: CGFloat
    }

    static let layers: [Layer] = {
        var random = SeededRandom(seed: 61)
        func puffs(_ count: Int, band: ClosedRange<CGFloat>, size: CGFloat, opacity: CGFloat) -> [Puff] {
            (0..<count).map { index in
                Puff(
                    x: (CGFloat(index) + random.next() * 0.7) / CGFloat(count),
                    y: band.lowerBound + random.next() * (band.upperBound - band.lowerBound),
                    width: size * (0.8 + random.next() * 0.6),
                    height: size * (0.28 + random.next() * 0.14),
                    opacity: opacity * (0.7 + random.next() * 0.3),
                    bob: random.next() * .pi * 2
                )
            }
        }
        return [
            Layer(puffs: puffs(6, band: 0.6...0.76, size: 0.2, opacity: 0.42), speed: 6),
            Layer(puffs: puffs(5, band: 0.72...0.9, size: 0.24, opacity: 0.5), speed: 11)
        ]
    }()

    struct State: Equatable, Sendable {
        let center: CGPoint
        let radii: CGSize
        let opacity: CGFloat
    }

    /// Where a puff is at `time`. Each layer is as wide as the area plus a
    /// puff's width either side, and wraps there, off screen.
    static func state(of puff: Puff, in layer: Layer, at time: Double, size: CGSize) -> State {
        let radius = puff.width * size.height
        let span = size.width + radius * 2 + size.height * 0.2
        let travelled = (puff.x * span + CGFloat(time) * layer.speed).truncatingRemainder(dividingBy: span)
        let bob = sin(CGFloat(time) * 0.21 + puff.bob) * size.height * 0.006
        return State(
            center: CGPoint(x: travelled - radius, y: puff.y * size.height + bob),
            radii: CGSize(width: radius, height: puff.height * size.height),
            opacity: puff.opacity
        )
    }
}

/// The Forest's boughs swaying. The top of the picture (the canopy) comes
/// in three layers built by Tools/Themes/make_scenes.py: the canopy with
/// the trunks painted out, drawn in thin bands that each move sideways a
/// little (most at the top, nothing where the canopy ends); the trunks,
/// still, over it; and the dark boughs that cross in front of a trunk,
/// moving with their band. So only branches and needles sway; the trunks
/// and the floor stay planted.
enum ForestSway {
    /// The share of the picture's height that sways (the layers' height:
    /// `CANOPY_ROWS` of the picture's 2752 rows).
    static let canopy: CGFloat = 1266.0 / 2752.0
    /// Bands it's drawn in (thin enough that the bend looks smooth).
    static let bands = 28
    /// The most the top of the picture moves, in points.
    static let reach: CGFloat = 5
    static let canopyName = "ThemeSceneForestCanopy"
    static let trunksName = "ThemeSceneForestTrunks"
    static let frontName = "ThemeSceneForestFront"

    /// How far the band at `share` of the picture's height (0 at the top)
    /// is moved at `time`: a slow breeze with gentler gusts on top, fading
    /// to nothing at the bottom of the canopy.
    static func offset(atShare share: CGFloat, time: Double) -> CGFloat {
        guard share < canopy else { return 0 }
        let weight = pow(1 - max(0, share) / canopy, 1.8)
        let tau = 2 * Double.pi
        let lag = Double(share) * 2.2
        let breeze = 0.65 * sin(tau * time / 6.8 - lag) + 0.35 * sin(tau * time / 3.1 + 1.3 - lag * 1.5)
        return reach * weight * CGFloat(breeze)
    }
}

/// Hearth's embers: small amber sparks leaving the coals at uneven moments,
/// rising and drifting, fading out before they reach the words.
enum HearthSparks {
    struct Spark: Sendable {
        let period, delay, sway, swaySpeed, phase: CGFloat
    }

    static let sparks: [Spark] = {
        var random = SeededRandom(seed: 47)
        return (0..<14).map { _ in
            Spark(period: 2.6 + random.next() * 2.8, delay: random.next() * 6,
                  sway: 3 + random.next() * 6, swaySpeed: 1.2 + random.next() * 1.6, phase: random.next() * .pi * 2)
        }
    }()

    struct State: Equatable, Sendable {
        let point: CGPoint
        let radius: CGFloat
        /// 0...1: quick to catch, then fading as it rises.
        let opacity: CGFloat
    }

    /// A spark at `time`, rising from the coals (`source`, a bed `width`
    /// wide) toward `ceiling`, where it has faded out. Nil between flights:
    /// every flight takes part of its cycle, with a rest of varying length.
    static func state(of spark: Spark, index: Int, at time: Double, source: CGPoint, width: CGFloat, ceiling: CGFloat) -> State? {
        let t = CGFloat(time) + spark.delay
        guard t >= 0 else { return nil }
        let cycle = (t / spark.period).rounded(.down)
        let seed = Double(index) * 13.7 + Double(cycle)
        // Each flight is 55–90% of the cycle; the rest is a pause.
        let flight = spark.period * CGFloat(0.55 + 0.35 * hash(seed))
        let local = t - cycle * spark.period
        guard local < flight else { return nil }
        let progress = local / flight
        let height = max(0, source.y - ceiling) * CGFloat(0.45 + 0.55 * hash(seed + 0.3))
        let start = source.x + (CGFloat(hash(seed + 0.6)) - 0.5) * width
        let drift = (CGFloat(hash(seed + 0.9)) - 0.5) * 24 * progress
        let x = start + drift + spark.sway * progress * sin(t * spark.swaySpeed + spark.phase)
        let y = source.y - height * pow(progress, 0.85)
        let catchUp = min(1, progress / 0.08)
        let flicker = 0.75 + 0.25 * sin(t * 9 + spark.phase)
        let radius = 0.6 + 1.0 * CGFloat(hash(seed + 0.45))
        return State(point: CGPoint(x: x, y: y), radius: radius, opacity: catchUp * pow(1 - progress, 1.3) * flicker)
    }

    /// The glow over the coals: slow, shallow breathing (0...1).
    static func glow(at time: Double) -> CGFloat {
        CGFloat(0.5 + 0.32 * sin(time * 2 * .pi / 6.5) + 0.18 * sin(time * 2 * .pi / 2.3 + 1.1))
    }

    /// 0..<1, the same for the same input.
    private static func hash(_ value: Double) -> Double {
        let x = sin(value * 127.1 + 311.7) * 43758.5453
        return x - x.rounded(.down)
    }
}
