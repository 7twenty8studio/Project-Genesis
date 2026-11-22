import CoreGraphics
import Foundation

/// What surrounds the page in the six material themes: fire, leather, wood,
/// hills, weather and stone. It's drawn at the edges, never over the text
/// area (`SceneryArea`), by `ThemeSceneryView`. Hearth, Highlands and Storm
/// on Galilee move gently under the seasonal rules (the Touches switch,
/// still with Reduce Motion or in Low Power Mode); the others are still.
enum ThemeScenery: String, CaseIterable, Sendable {
    case hearth, leatherBound, cedar, highlands, galileeStorm, ironstone

    /// Embers, mist or rain move while reading.
    var moves: Bool {
        switch self {
        case .hearth, .highlands, .galileeStorm: true
        case .leatherBound, .cedar, .ironstone: false
        }
    }

    /// Cedar and Leather Bound turn pages like paper (the page curl) in
    /// paged reading, whatever page turn is chosen; Reduce Motion and Low
    /// Power Mode keep the plain slide.
    var turnsLikePaper: Bool { self == .cedar || self == .leatherBound }
}

/// Where a theme's scenery may go: the margins around the text and the
/// bands above and below it, never the text itself.
struct SceneryArea: Equatable, Sendable {
    var size: CGSize
    /// The text area's distance from each edge (top and bottom are 0 when
    /// text scrolls through the whole screen).
    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat
    /// Room above the running head (the status bar's band).
    var topBand: CGFloat
    /// Room below the page number (the home indicator's band).
    var footBand: CGFloat
    /// Two pages side by side, with a gutter in the middle.
    var spread: Bool = false

    /// Wood or leather at the sides: slim on phones (half the margin), more
    /// of it on wide layouts, up to `maximum`.
    func sideWidth(maximum: CGFloat) -> CGFloat {
        min(maximum, max(6, min(left, right) * 0.5))
    }

    /// Ridges and water at the foot fold away when there's no room for them
    /// (a phone without a home indicator, very large text).
    var footDecoration: CGFloat {
        footBand >= 20 ? footBand : 0
    }

    /// Whether a point is inside the text area.
    func isInText(_ point: CGPoint) -> Bool {
        point.x >= left && point.x <= size.width - right && point.y >= top && point.y <= size.height - bottom
    }
}

/// Storm on Galilee's distant lightning: now and then the horizon brightens
/// softly and fades (never a bolt, never a flash over the text). Pure, so
/// tests and the painted still agree.
enum StormFlash {
    /// Seconds per cycle; each has one brightening at a varying moment.
    static let cycle: Double = 19

    /// 0...1, how bright the horizon is at `time`.
    static func intensity(at time: Double) -> Double {
        guard time >= 0 else { return 0 }
        let n = (time / cycle).rounded(.down)
        let start = 6 + hash(n) * 8
        let local = time - n * cycle - start
        let echo = hash(n + 0.5) > 0.5 ? pulse(local - 0.7, peak: 0.5) : 0
        return min(1, pulse(local, peak: 1) + echo)
    }

    /// A soft rise over 0.35 s, then a fade over 1.6 s.
    private static func pulse(_ t: Double, peak: Double) -> Double {
        if t < 0 { return 0 }
        if t < 0.35 { let x = t / 0.35; return peak * x * (2 - x) }
        if t < 1.95 { let x = 1 - (t - 0.35) / 1.6; return peak * x * x }
        return 0
    }

    private static func hash(_ x: Double) -> Double {
        let s = sin(x * 12.9898 + 4.1414) * 43758.5453
        return s - s.rounded(.down)
    }
}

/// Hearth's embers: a dozen sparks rising from the fire's glow and dying
/// out low on the page.
enum HearthEmbers {
    struct Ember: Sendable {
        let x, offset, speed, sway, swaySpeed, radius, flicker, phase: CGFloat
    }

    /// How high (as a share of the page) an ember can rise before it's out.
    static let reach: CGFloat = 0.4

    static let embers: [Ember] = {
        var random = SeededRandom(seed: 33)
        return (0..<12).map { _ in
            Ember(x: random.next(), offset: random.next(), speed: 9 + random.next() * 11,
                  sway: 6 + random.next() * 8, swaySpeed: 0.4 + random.next() * 0.6,
                  radius: 0.6 + random.next() * 1.1, flicker: 3 + random.next() * 4, phase: random.next() * .pi * 2)
        }
    }()

    struct State: Equatable, Sendable {
        let point: CGPoint
        let radius: CGFloat
        /// 0...1, fading as it rises and flickering.
        let opacity: CGFloat
    }

    static func state(of ember: Ember, index: Int, at t: CGFloat, page: CGSize) -> State {
        let travel = max(1, page.height * reach)
        let risen = (ember.offset * travel + t * ember.speed).truncatingRemainder(dividingBy: travel)
        let progress = risen / travel
        let drift = progress * 8 * (index.isMultiple(of: 2) ? 1 : -1)
        let point = CGPoint(x: ember.x * page.width + ember.sway * sin(t * ember.swaySpeed + ember.phase) + drift,
                            y: page.height + 6 - risen)
        let opacity = pow(1 - progress, 1.4) * (0.55 + 0.45 * abs(sin(t * ember.flicker + ember.phase)))
        return State(point: point, radius: ember.radius, opacity: opacity)
    }
}
