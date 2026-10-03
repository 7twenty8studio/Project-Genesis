import SwiftUI

/// The season drifting gently across the page while reading with a seasonal
/// theme: autumn leaves, winter snow, spring blossom, or summer sunlight
/// (slow rays and warm colour washes). It loops for as long as the reader is
/// open, sparse and translucent so the text stays easy to read. It never
/// takes a tap, is hidden from VoiceOver, pauses in Low Power Mode, and is
/// left out with Reduce Motion (ReaderView checks).
struct SeasonalEffectView: View {
    let season: Season
    /// Draws one still moment instead of animating (for verse images).
    var stillTime: TimeInterval?

    @State private var start = Date.now
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        Group {
            if let stillTime {
                Canvas { canvas, size in
                    Self.draw(season, in: canvas, size: size, time: stillTime)
                }
            } else {
                // 30 frames a second is plenty for drifting things and halves the cost.
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: lowPower)) { context in
                    Canvas { canvas, size in
                        let time = context.date.timeIntervalSince(start)
                        canvas.opacity = min(1, time / 1.5) // fade in when it starts
                        Self.draw(season, in: canvas, size: size, time: time)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    nonisolated private static func draw(_ season: Season, in canvas: GraphicsContext, size: CGSize, time: TimeInterval) {
        if season == .summer {
            SummerLight.draw(in: canvas, size: size, time: time)
        } else {
            for particle in SeasonParticle.make(for: season) {
                particle.draw(in: canvas, size: size, time: time, season: season)
            }
        }
    }
}

/// One leaf, snowflake or petal, described by fixed random numbers so its
/// path is a pure function of time. Each falls, leaves the page and starts
/// again at the top.
private struct SeasonParticle {
    let x: CGFloat          // 0...1 across the page
    let offset: CGFloat     // 0...1 of the way down when the effect starts
    let speed: CGFloat      // points per second
    let sway: CGFloat       // side-to-side distance
    let swaySpeed: CGFloat
    let phase: CGFloat
    let size: CGFloat
    let spin: CGFloat
    let tone: Int

    static func make(for season: Season) -> [SeasonParticle] {
        var random = SeededRandom(seed: UInt64(Season.allCases.firstIndex(of: season) ?? 0) + 11)
        let count = switch season {
        case .autumn: 10
        case .winter: 30
        case .spring: 14
        case .summer: 0
        }
        return (0..<count).map { _ in
            SeasonParticle(
                x: random.next(),
                offset: random.next(),
                speed: 22 + random.next() * 26,
                sway: 12 + random.next() * 30,
                swaySpeed: 0.4 + random.next() * 0.7,
                phase: random.next() * .pi * 2,
                size: random.next(),
                spin: (random.next() - 0.5) * 1.6,
                tone: Int(random.next() * 3)
            )
        }
    }

    /// How far down the page it is now, looping: from just above the top to
    /// just below the bottom, then again.
    private func fall(_ t: CGFloat, page: CGSize, speedScale: CGFloat) -> CGFloat {
        let travel = page.height + 60
        let distance = (offset * travel + t * speed * speedScale).truncatingRemainder(dividingBy: travel)
        return distance - 30
    }

    func draw(in canvas: GraphicsContext, size page: CGSize, time: TimeInterval, season: Season) {
        let t = CGFloat(time)
        let drift = sin(t * swaySpeed + phase) * sway
        var context = canvas
        switch season {
        case .autumn:
            let position = CGPoint(x: x * page.width + drift, y: fall(t, page: page, speedScale: 1))
            context.translateBy(x: position.x, y: position.y)
            context.rotate(by: .radians(Double(phase + t * spin)))
            // Tumbling: the leaf turns over as it falls.
            context.scaleBy(x: max(0.2, abs(cos(t * swaySpeed * 1.3 + phase))), y: 1)
            let length = 14 + size * 10
            context.fill(Self.leaf(length: length), with: .color(Self.autumn[tone].opacity(0.6)))
            var vein = Path()
            vein.move(to: CGPoint(x: 0, y: -length / 2))
            vein.addLine(to: CGPoint(x: 0, y: length / 2 + 3))
            context.stroke(vein, with: .color(Self.autumn[tone].opacity(0.75)), lineWidth: 0.8)
        case .winter:
            let position = CGPoint(x: x * page.width + drift * 0.6, y: fall(t, page: page, speedScale: 0.7))
            let diameter = 2.5 + size * 4
            let flake = Path(ellipseIn: CGRect(x: position.x - diameter / 2, y: position.y - diameter / 2, width: diameter, height: diameter))
            // Pale blue-grey with a white centre, so it shows on the pale paper.
            context.fill(flake, with: .color(Self.winter.opacity(0.5)))
            context.fill(Path(ellipseIn: CGRect(x: position.x - diameter / 4, y: position.y - diameter / 4, width: diameter / 2, height: diameter / 2)), with: .color(.white.opacity(0.8)))
        case .spring:
            let position = CGPoint(x: x * page.width + drift, y: fall(t, page: page, speedScale: 0.85))
            context.translateBy(x: position.x, y: position.y)
            context.rotate(by: .radians(Double(phase + t * spin)))
            context.scaleBy(x: 1, y: max(0.25, abs(sin(t * swaySpeed + phase))))
            let width = 7 + size * 5
            context.fill(Path(ellipseIn: CGRect(x: -width / 2, y: -width / 3, width: width, height: width * 0.66)), with: .color(Self.spring[tone].opacity(0.6)))
        case .summer:
            break // SummerLight
        }
    }

    private static func leaf(length: CGFloat) -> Path {
        var path = Path()
        let half = length / 2
        path.move(to: CGPoint(x: 0, y: -half))
        path.addQuadCurve(to: CGPoint(x: 0, y: half), control: CGPoint(x: length * 0.55, y: -half * 0.1))
        path.addQuadCurve(to: CGPoint(x: 0, y: -half), control: CGPoint(x: -length * 0.55, y: half * 0.1))
        return path
    }

    // Muted seasonal colours.
    private static let autumn: [Color] = [0xB4693A, 0xC99541, 0x9C4F2E].map(SeasonColor.make)
    private static let winter = SeasonColor.make(0x8FA6B8)
    private static let spring: [Color] = [0xE2A9B5, 0xEDC4CB, 0xD493A2].map(SeasonColor.make)
}

/// Summer: soft rays of sunlight slanting in from the top corner, slowly
/// breathing and swaying, over warm washes of colour that drift like light
/// through leaves.
private enum SummerLight {
    struct Wash {
        let x: CGFloat, y: CGFloat, radius: CGFloat
        let driftX: CGFloat, driftY: CGFloat, speed: CGFloat, phase: CGFloat
        let color: Color
    }

    static let washes: [Wash] = {
        var random = SeededRandom(seed: 41)
        let colors: [UInt32] = [0xF2C98A, 0xEFB9A0, 0xB9D5C9, 0xF4DE9E, 0xEAC27E, 0xC9DDC0]
        return colors.map { hex in
            Wash(
                x: random.next(), y: random.next(), radius: 0.28 + random.next() * 0.22,
                driftX: 0.04 + random.next() * 0.08, driftY: 0.03 + random.next() * 0.06,
                speed: 0.05 + random.next() * 0.06, phase: random.next() * .pi * 2,
                color: SeasonColor.make(hex)
            )
        }
    }()

    static func draw(in canvas: GraphicsContext, size page: CGSize, time: TimeInterval) {
        let t = CGFloat(time)
        let scale = max(page.width, page.height)

        // Colour washes: large, soft, slow.
        for wash in washes {
            let center = CGPoint(
                x: (wash.x + sin(t * wash.speed + wash.phase) * wash.driftX) * page.width,
                y: (wash.y + cos(t * wash.speed * 0.8 + wash.phase) * wash.driftY) * page.height
            )
            let radius = wash.radius * scale
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            canvas.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [wash.color.opacity(0.3), wash.color.opacity(0)]),
                center: center, startRadius: 0, endRadius: radius
            ))
        }

        // Rays: long tapering beams from just beyond the top-right corner.
        let source = CGPoint(x: page.width * 1.05, y: -page.height * 0.08)
        let length = scale * 1.5
        for index in 0..<6 {
            let i = CGFloat(index)
            let sway = sin(t * 0.12 + i * 1.7) * 0.025
            let angle = CGFloat.pi * 0.62 + i * 0.075 + sway  // pointing down and to the left
            let spread = 0.024 + 0.016 * (i.truncatingRemainder(dividingBy: 2))
            let breathe = 0.5 + 0.5 * sin(t * 0.35 + i * 1.3)
            let end1 = CGPoint(x: source.x + cos(angle - spread) * length, y: source.y + sin(angle - spread) * length)
            let end2 = CGPoint(x: source.x + cos(angle + spread) * length, y: source.y + sin(angle + spread) * length)
            var ray = Path()
            ray.move(to: source)
            ray.addLine(to: end1)
            ray.addLine(to: end2)
            ray.closeSubpath()
            canvas.fill(ray, with: .linearGradient(
                Gradient(colors: [SummerLight.ray.opacity(0.32 * breathe + 0.14), SummerLight.ray.opacity(0)]),
                startPoint: source,
                endPoint: CGPoint(x: source.x + cos(angle) * length * 0.75, y: source.y + sin(angle) * length * 0.75)
            ))
        }
    }

    static let ray = SeasonColor.make(0xF0C25E)
}

private enum SeasonColor {
    static func make(_ hex: UInt32) -> Color {
        Color(uiColor: UIColor(hex: hex))
    }
}
