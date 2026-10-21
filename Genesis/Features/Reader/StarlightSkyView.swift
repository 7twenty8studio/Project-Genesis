import SwiftUI
import UIKit

/// Starlight's clear night sky, over the page: twenty stars in three colours
/// (blue-white, white, warm) that twinkle with a quick brightening and a slow
/// fade, a small glint on the brightest, a faint Milky Way along the edges,
/// and a shooting star every 3–8 seconds (the rules are in `NightSky`).
///
/// It sits above the text (the pages are opaque), so it keeps out of the
/// words: stars and haze stay in the margins and the band above the running
/// head, and the haze thins out smoothly before the text, so there's no
/// edge. It never takes a tap, is hidden from VoiceOver, holds still in Low
/// Power Mode, and draws 20 frames a second (60 only while a shooting star
/// passes). With Reduce Motion the stars only fade gently in place and no
/// stars shoot. The still stars printed on the paper are `PaperTexture`'s.
struct StarlightSkyView: View {
    /// Where the words are, as insets from the edges. Nil when the sky is
    /// behind the content instead (the morning welcome), so stars can go anywhere.
    var textInsets: UIEdgeInsets?
    /// How tall the band across the top is where no text ever passes
    /// (paged reading, above the running head). Shooting stars stay in it;
    /// 0 means none.
    var skyBand: CGFloat
    var reduceMotion: Bool

    @State private var start = Date.now
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        let insets = textInsets
        let band = skyBand
        let reduce = reduceMotion
        let opened = start
        ZStack {
            // The haze never moves: drawn once, not every frame.
            Canvas { canvas, size in
                SkyPainter.drawMilkyWay(in: canvas, size: size, text: SkyPainter.textRect(insets, in: size))
            }
            TimelineView(StarlightSchedule(start: opened, shooting: band > 0 && !reduce, paused: lowPower, reduceMotion: reduce)) { context in
                let time = context.date.timeIntervalSince(opened)
                Canvas { canvas, size in
                    SkyPainter.drawStars(in: canvas, size: size, time: time, text: SkyPainter.textRect(insets, in: size), band: band, reduceMotion: reduce)
                    if band > 0, !reduce {
                        SkyPainter.drawShootingStars(in: canvas, size: size, time: time, band: band)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: DispatchQueue.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

/// When to draw the next frame: 20 a second, 60 while a shooting star
/// passes, 10 with Reduce Motion, once a second when the system asks for
/// less (Always On), and none while paused.
private struct StarlightSchedule: TimelineSchedule {
    let start: Date
    let shooting: Bool
    let paused: Bool
    let reduceMotion: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(date: startDate, schedule: self, mode: mode)
    }

    func interval(after date: Date, mode: TimelineScheduleMode) -> TimeInterval {
        if mode == .lowFrequency { return 1 }
        if reduceMotion { return 1.0 / 10 }
        let time = date.timeIntervalSince(start)
        if shooting, !NightSky.activeStreaks(at: time).isEmpty || !NightSky.activeStreaks(at: time + 1.0 / 20).isEmpty {
            return 1.0 / 60
        }
        return 1.0 / 20
    }

    struct Entries: Sequence, IteratorProtocol {
        var date: Date
        let schedule: StarlightSchedule
        let mode: TimelineScheduleMode
        var finished = false

        mutating func next() -> Date? {
            guard !finished else { return nil }
            let current = date
            if schedule.paused {
                finished = true
            } else {
                date = current.addingTimeInterval(schedule.interval(after: current, mode: mode))
            }
            return current
        }
    }
}

/// The drawing itself, outside the view so it runs wherever Canvas draws.
private enum SkyPainter {
    struct Star {
        let index: Int
        var zone: Double { NightSky.unit(index, 20) }
        var side: Double { NightSky.unit(index, 27) }
        var x: CGFloat { CGFloat(NightSky.unit(index, 21)) }
        var y: CGFloat { CGFloat(NightSky.unit(index, 22)) }
        var core: CGFloat { 1 + 1.5 * CGFloat(NightSky.unit(index, 23)) }
        var period: Double { 3 + 6 * NightSky.unit(index, 24) }
        var offset: Double { 10 * NightSky.unit(index, 25) }
        var tint: Color { SkyPainter.tints[Int(3 * NightSky.unit(index, 26)) % 3] }
        /// The four brightest wear a glint at their peak.
        var isMajor: Bool { index < 4 }
    }

    static let stars = (0..<20).map(Star.init(index:))
    /// Blue-white, white and warm, like real stars.
    static let tints: [Color] = [0xCDDAFF, 0xF4F1E8, 0xFFE4BA].map { Color(uiColor: UIColor(hex: $0)) }
    static let streakColor = Color(uiColor: UIColor(hex: 0xFAF2D2))
    static let headColor = Color(uiColor: UIColor(hex: 0xFFF8E0))
    static let hazeColors: [Color] = [0x96AAD7, 0xBEB4D2].map { Color(uiColor: UIColor(hex: $0)) }
    static let dustColor = Color(uiColor: UIColor(hex: 0xDCE2F0))

    static func textRect(_ insets: UIEdgeInsets?, in size: CGSize) -> CGRect? {
        guard let insets else { return nil }
        return CGRect(x: insets.left, y: insets.top,
                      width: max(0, size.width - insets.left - insets.right),
                      height: max(0, size.height - insets.top - insets.bottom))
    }

    /// Where a star sits: in the sky band or a side margin, clear of the text.
    static func position(of star: Star, size: CGSize, text: CGRect?, band: CGFloat) -> CGPoint? {
        guard let text else {
            return CGPoint(x: (0.04 + 0.92 * star.x) * size.width, y: (0.04 + 0.92 * star.y) * size.height)
        }
        let left = text.minX
        let right = size.width - text.maxX
        let hasSky = band >= 20
        let hasLeft = left >= 14
        let hasRight = right >= 14
        if hasSky && (star.zone < 0.4 || !(hasLeft || hasRight)) {
            return CGPoint(x: 10 + star.x * (size.width - 20), y: 8 + star.y * (band - 12))
        }
        guard hasLeft || hasRight else { return nil }
        let onLeft = hasLeft && (!hasRight || star.side < 0.5)
        let x = onLeft ? 6 + star.x * (left - 12) : text.maxX + 6 + star.x * (right - 12)
        return CGPoint(x: x, y: (0.1 + 0.82 * star.y) * size.height)
    }

    static func drawStars(in canvas: GraphicsContext, size: CGSize, time: TimeInterval, text: CGRect?, band: CGFloat, reduceMotion: Bool) {
        let fadeIn = min(1, time / 1.5)
        for star in stars {
            guard let point = position(of: star, size: size, text: text, band: band) else { continue }
            let brightness = NightSky.brightness(at: time, period: star.period, offset: star.offset, reduceMotion: reduceMotion)
            // A brief shimmer near the peak, the way real stars flicker.
            let flicker = !reduceMotion && brightness > 0.6 ? 0.08 * sin(time * 37 + star.offset * 11) : 0
            let core = reduceMotion ? star.core : star.core * (1 + 0.4 * CGFloat(max(0, brightness - 0.3) / 0.7))
            let glow = core * (star.isMajor ? 7 : 5)
            canvas.fill(circle(point, glow), with: .radialGradient(
                Gradient(colors: [star.tint.opacity((0.35 + flicker) * brightness * fadeIn), star.tint.opacity(0)]),
                center: point, startRadius: 0, endRadius: glow
            ))
            canvas.fill(circle(point, core), with: .color(star.tint.opacity(min(1, brightness + 0.1 + flicker) * fadeIn)))
            if !reduceMotion, star.isMajor, brightness > 0.7 {
                let k = (brightness - 0.7) / 0.3
                let length = core * 6 * CGFloat(k)
                var glint = Path()
                glint.move(to: CGPoint(x: point.x - length, y: point.y))
                glint.addLine(to: CGPoint(x: point.x + length, y: point.y))
                glint.move(to: CGPoint(x: point.x, y: point.y - length))
                glint.addLine(to: CGPoint(x: point.x, y: point.y + length))
                canvas.stroke(glint, with: .color(star.tint.opacity(0.75 * k * fadeIn)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
            }
        }
    }

    static func drawShootingStars(in canvas: GraphicsContext, size: CGSize, time: TimeInterval, band: CGFloat) {
        for streak in NightSky.activeStreaks(at: time) {
            let (from, travel) = streak.path(width: size.width, height: band)
            let elapsed = time - streak.start
            let progress = elapsed / streak.duration
            let eased = CGFloat(NightSky.easeOut(progress))
            let head = CGPoint(x: from.x + travel.dx * eased, y: from.y + travel.dy * eased)
            let alpha = min(1, elapsed / 0.1, (1 - progress) * streak.duration / 0.28)
            let distance = hypot(travel.dx, travel.dy)
            guard distance > 0 else { continue }
            let tail = min(streak.tail, distance * eased)
            let end = CGPoint(x: head.x - travel.dx / distance * tail, y: head.y - travel.dy / distance * tail)
            var line = Path()
            line.move(to: head)
            line.addLine(to: end)
            canvas.stroke(line, with: .linearGradient(
                Gradient(colors: [streakColor.opacity(0.95 * alpha), streakColor.opacity(0)]),
                startPoint: head, endPoint: end
            ), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            canvas.fill(circle(head, 5), with: .radialGradient(
                Gradient(colors: [headColor.opacity(0.6 * alpha), headColor.opacity(0)]),
                center: head, startRadius: 0, endRadius: 5
            ))
            canvas.fill(circle(head, 1.4), with: .color(headColor.opacity(alpha)))
        }
    }

    /// A faint band of haze and star dust from the top-left corner down the
    /// right-hand side, thinning smoothly before the text.
    static func drawMilkyWay(in canvas: GraphicsContext, size: CGSize, text: CGRect?) {
        func spot(_ i: Int, salt: UInt64, jitter: CGFloat) -> CGPoint {
            let u = CGFloat(NightSky.unit(i, salt))
            return CGPoint(
                x: 10 + u * (size.width - 10) + (CGFloat(NightSky.unit(i, salt + 1)) - 0.5) * jitter,
                y: size.height * (0.03 + 0.68 * pow(u, 2.2)) + (CGFloat(NightSky.unit(i, salt + 2)) - 0.5) * jitter * 0.85
            )
        }
        for i in 0..<90 {
            let point = spot(i, salt: 40, jitter: 30)
            let fade = text.map { NightSky.hazeFade(at: point, text: $0) } ?? 1
            guard fade > 0 else { continue }
            let radius = 12 + 18 * CGFloat(NightSky.unit(i, 43))
            let color = hazeColors[NightSky.unit(i, 44) < 0.5 ? 0 : 1]
            canvas.fill(circle(point, radius), with: .radialGradient(
                Gradient(colors: [color.opacity(0.06 * Double(fade)), color.opacity(0)]),
                center: point, startRadius: 0, endRadius: radius
            ))
        }
        for i in 0..<200 {
            let point = spot(i, salt: 50, jitter: 24)
            let fade = text.map { NightSky.hazeFade(at: point, text: $0) } ?? 1
            guard fade > 0 else { continue }
            let radius = 0.35 + 0.35 * CGFloat(NightSky.unit(i, 53))
            canvas.fill(circle(point, radius), with: .color(dustColor.opacity((0.15 + 0.25 * NightSky.unit(i, 54)) * Double(fade))))
        }
    }

    static func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
