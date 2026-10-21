import CoreGraphics
import Foundation

/// The rules behind Starlight's moving sky (`StarlightSkyView`), kept pure so
/// they can be tested: when shooting stars fall, how a star twinkles, and the
/// curve things move on. Everything is a function of time and fixed random
/// numbers, so the sky is the same every time and needs no saved state.
enum NightSky {
    // MARK: Fixed random numbers

    /// A number in 0..<1 for `index` and `salt` (SplitMix64), always the same.
    static func unit(_ index: Int, _ salt: UInt64) -> Double {
        var z = UInt64(bitPattern: Int64(index)) &+ (salt &+ 1) &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }

    // MARK: Easing

    /// The strong ease-out, cubic-bezier(0.23, 1, 0.32, 1): moves at once and
    /// settles softly (Motion.easeOut in the interface).
    static func easeOut(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        // Solve the curve's x for t, then read its y.
        var low = 0.0, high = 1.0, u = t
        for _ in 0..<18 {
            u = (low + high) / 2
            let x = 3 * (1 - u) * (1 - u) * u * 0.23 + 3 * (1 - u) * u * u * 0.32 + u * u * u
            if x < t { low = u } else { high = u }
        }
        return 3 * (1 - u) * (1 - u) * u + 3 * (1 - u) * u * u + u * u * u
    }

    // MARK: Twinkling

    /// How bright a star is (0.3...1): a quick rise (0.45 s), a slow fall
    /// (2.15 s), then rest until its next twinkle. With Reduce Motion, a slow,
    /// gentle swell instead.
    static func brightness(at time: Double, period: Double, offset: Double, reduceMotion: Bool) -> Double {
        if reduceMotion {
            return 0.5 + 0.3 * sin((time + offset) * 2 * .pi / (period * 1.6))
        }
        let p = (time + offset).truncatingRemainder(dividingBy: period + 2.6)
        if p < 0.45 { return 0.3 + 0.7 * easeOut(p / 0.45) }
        if p < 2.6 { return 0.3 + 0.7 * pow(1 - (p - 0.45) / 2.15, 2) }
        return 0.3
    }

    // MARK: Shooting stars

    /// One shooting star: when it starts, how long it takes, and its shape
    /// (from fixed random numbers, placed by `path(in:)`).
    struct Streak: Equatable, Sendable {
        let seed: Int
        let start: Double

        var duration: Double { 0.6 + 0.3 * NightSky.unit(seed, 3) }

        func isActive(at time: Double) -> Bool {
            time >= start && time < start + duration
        }

        /// Where it starts and how far it goes, inside a band `height` tall
        /// across the top of a page `width` wide: a shallow fall, left or
        /// right, never below the band.
        func path(width: CGFloat, height band: CGFloat) -> (from: CGPoint, travel: CGVector) {
            let fromRight = NightSky.unit(seed, 4) < 0.5
            let across = CGFloat(NightSky.unit(seed, 5))
            let x = fromRight ? width * (0.55 + 0.37 * across) : width * (0.08 + 0.37 * across)
            let y = 4 + max(0, band - 8) * 0.35 * CGFloat(NightSky.unit(seed, 6))
            let length = min(width * 0.6, 110 + 80 * CGFloat(NightSky.unit(seed, 7)))
            let angle = 0.32 + (CGFloat(NightSky.unit(seed, 8)) - 0.5) * 0.16
            let dy = min(sin(angle) * length, max(0, band - 4 - y))
            return (CGPoint(x: x, y: y), CGVector(dx: cos(angle) * length * (fromRight ? -1 : 1), dy: dy))
        }

        /// The glowing tail's length.
        var tail: CGFloat { 40 + 30 * CGFloat(NightSky.unit(seed, 9)) }
    }

    /// Shooting stars come every 3–8 seconds, the first 3–5.5 s after the page
    /// opens: one per 5.5-second slot, at a random moment in its first 2.5 s.
    /// One in six brings a second close behind it.
    static let slot = 5.5
    static let firstDelay = 3.0
    static let pairDelay = 0.45

    static func streaks(inSlot index: Int) -> [Streak] {
        guard index >= 0 else { return [] }
        let start = Double(index) * slot + firstDelay + 2.5 * unit(index, 1)
        var streaks = [Streak(seed: index * 2, start: start)]
        if unit(index, 2) < 1.0 / 6 {
            streaks.append(Streak(seed: index * 2 + 1, start: start + pairDelay))
        }
        return streaks
    }

    /// The shooting stars in the sky at `time` (seconds since the page opened).
    static func activeStreaks(at time: Double) -> [Streak] {
        let index = Int(((time - firstDelay) / slot).rounded(.down))
        return (index - 1...index).flatMap(streaks(inSlot:)).filter { $0.isActive(at: time) }
    }

    // MARK: Keeping clear of the words

    /// How much of the haze to draw at a point (0...1): fading smoothly over
    /// about 46 points as it nears the text, so there's no visible edge.
    static func hazeFade(at point: CGPoint, text: CGRect) -> CGFloat {
        let dx = max(text.minX - point.x, 0, point.x - text.maxX)
        let dy = max(text.minY - point.y, 0, point.y - text.maxY)
        let outside: CGFloat = dx > 0 || dy > 0
            ? hypot(dx, dy)
            : -min(point.x - text.minX, text.maxX - point.x, point.y - text.minY, text.maxY - point.y)
        let k = min(1, max(0, (outside + 18) / 46))
        return k * k * (3 - 2 * k)
    }
}
