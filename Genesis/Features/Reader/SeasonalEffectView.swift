import SwiftUI

/// The season drifting gently across the page while reading with a seasonal
/// theme, each with its own kind of motion: autumn leaves tumbling down,
/// spring petals riding a breeze over patches of warm light, winter snow
/// falling at three depths with a gust now and then and frost in the
/// corners, or summer sunlight (slow rays and warm colour washes). Sparse
/// and translucent so the text stays easy to read. It never takes a tap, is
/// hidden from VoiceOver and holds still in Low Power Mode; with Reduce
/// Motion (or for verse images) it's one painted still moment.
struct SeasonalEffectView: View {
    let season: Season
    /// Draws one still moment instead of animating (for verse images).
    var stillTime: TimeInterval?
    var reduceMotion = false

    /// The moment shown when it holds still: every season looks settled here.
    static let paintedMoment: TimeInterval = 7.3

    @State private var start = Date.now
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        let current = season
        ZStack {
            if current == .winter {
                // The frost never moves: drawn once, not every frame.
                Canvas { canvas, size in WinterSnow.drawFrost(in: canvas, size: size) }
            }
            if let still = stillTime ?? (reduceMotion ? Self.paintedMoment : nil) {
                Canvas { canvas, size in
                    SeasonPainter.draw(current, in: canvas, size: size, time: still)
                }
            } else {
                // 30 frames a second is plenty for drifting things and halves the cost.
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: lowPower)) { context in
                    Canvas { canvas, size in
                        let time = context.date.timeIntervalSince(start)
                        canvas.opacity = min(1, time / 1.5) // fade in when it starts
                        SeasonPainter.draw(current, in: canvas, size: size, time: time)
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
}

private enum SeasonPainter {
    static func draw(_ season: Season, in canvas: GraphicsContext, size: CGSize, time: TimeInterval) {
        switch season {
        case .autumn: AutumnLeaves.draw(in: canvas, size: size, time: CGFloat(time))
        case .spring: SpringPetals.draw(in: canvas, size: size, time: CGFloat(time))
        case .winter: WinterSnow.draw(in: canvas, size: size, time: CGFloat(time))
        case .summer: SummerLight.draw(in: canvas, size: size, time: time)
        }
    }

    /// Wraps a position into 0..<length, going round when it leaves.
    static func wrap(_ value: CGFloat, _ length: CGFloat) -> CGFloat {
        let r = value.truncatingRemainder(dividingBy: length)
        return r < 0 ? r + length : r
    }
}

/// Seven leaves at a time, falling 14–26 points a second, swaying and
/// turning over as they go.
private enum AutumnLeaves {
    struct Leaf {
        let x, offset, speed, sway, swaySpeed, phase, size, spin: CGFloat
        let tone: Int
    }

    static let leaves: [Leaf] = {
        var random = SeededRandom(seed: 14)
        return (0..<7).map { _ in
            Leaf(x: random.next(), offset: random.next(), speed: 14 + random.next() * 12,
                 sway: 18 + random.next() * 22, swaySpeed: 0.35 + random.next() * 0.35,
                 phase: random.next() * .pi * 2, size: random.next(), spin: (random.next() - 0.5) * 1.2,
                 tone: Int(random.next() * 3) % 3)
        }
    }()
    static let colors: [Color] = [0xB4693A, 0xC99541, 0x9C4F2E].map(SeasonColor.make)

    static func draw(in canvas: GraphicsContext, size page: CGSize, time t: CGFloat) {
        for leaf in leaves {
            let travel = page.height + 60
            let y = SeasonPainter.wrap(leaf.offset * travel + t * leaf.speed, travel) - 30
            let x = leaf.x * page.width + sin(t * leaf.swaySpeed + leaf.phase) * leaf.sway
            var context = canvas
            context.translateBy(x: x, y: y)
            context.rotate(by: .radians(Double(leaf.phase + t * leaf.spin)))
            // Tumbling: the leaf turns over as it falls.
            context.scaleBy(x: max(0.2, abs(cos(t * leaf.swaySpeed * 1.3 + leaf.phase))), y: 1)
            let length = 14 + leaf.size * 10
            context.fill(shape(length: length), with: .color(colors[leaf.tone].opacity(0.45)))
            var vein = Path()
            vein.move(to: CGPoint(x: 0, y: -length / 2))
            vein.addLine(to: CGPoint(x: 0, y: length / 2 + 3))
            context.stroke(vein, with: .color(colors[leaf.tone].opacity(0.6)), lineWidth: 0.8)
        }
    }

    static func shape(length: CGFloat) -> Path {
        var path = Path()
        let half = length / 2
        path.move(to: CGPoint(x: 0, y: -half))
        path.addQuadCurve(to: CGPoint(x: 0, y: half), control: CGPoint(x: length * 0.55, y: -half * 0.1))
        path.addQuadCurve(to: CGPoint(x: 0, y: -half), control: CGPoint(x: -length * 0.55, y: half * 0.1))
        return path
    }
}

/// Twelve blossom petals drifting down and to the right on one shared
/// breeze that swells and settles over 50 seconds, each fluttering and
/// flipping on its own, over two slow patches of warm light.
private enum SpringPetals {
    struct Petal {
        let x, offset, fall, drift, flutter, flutterSpeed, phase, spin, size: CGFloat
        let tone: Int
    }

    static let petals: [Petal] = {
        var random = SeededRandom(seed: 8)
        return (0..<12).map { _ in
            Petal(x: random.next(), offset: random.next(), fall: 12 + random.next() * 8, drift: 6 + random.next() * 6,
                  flutter: 8 + random.next() * 14, flutterSpeed: 0.5 + random.next() * 0.6, phase: random.next() * .pi * 2,
                  spin: (random.next() - 0.5) * 1.4, size: 6.5 + random.next() * 4, tone: Int(random.next() * 3) % 3)
        }
    }()
    static let colors: [Color] = [0xE2A9B5, 0xEDC4CB, 0xD493A2].map(SeasonColor.make)
    static let light: [(x: CGFloat, y: CGFloat, color: Color)] = [
        (0.25, 0.3, SeasonColor.make(0xFFECC8)),
        (0.75, 0.65, SeasonColor.make(0xF7D6DE)),
    ]

    static func draw(in canvas: GraphicsContext, size page: CGSize, time t: CGFloat) {
        // Sun through branches, very faint (it's over the text).
        for (index, patch) in light.enumerated() {
            let i = CGFloat(index)
            let center = CGPoint(x: (patch.x + 0.12 * sin(t * 0.05 + i * 2)) * page.width,
                                 y: (patch.y + 0.06 * cos(t * 0.04 + i)) * page.height)
            let radius = 0.57 * page.width
            canvas.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(Gradient(colors: [patch.color.opacity(0.2), patch.color.opacity(0)]),
                                              center: center, startRadius: 0, endRadius: radius))
        }
        let breeze = 34 * sin(t * .pi * 2 / 50)
        for petal in petals {
            let travelY = page.height + 40
            let y = SeasonPainter.wrap(petal.offset * travelY + t * petal.fall, travelY) - 20
            let travelX = page.width + 40
            let x = SeasonPainter.wrap(petal.x * travelX + t * petal.drift + breeze + petal.flutter * sin(t * petal.flutterSpeed + petal.phase), travelX) - 20
            var context = canvas
            context.translateBy(x: x, y: y)
            context.rotate(by: .radians(Double(petal.phase + t * petal.spin)))
            // Flipping on both axes reads lighter than a leaf's tumble.
            context.scaleBy(x: max(0.2, abs(cos(t * petal.flutterSpeed * 1.4 + petal.phase))),
                            y: 0.65 + 0.35 * sin(t * petal.flutterSpeed + petal.phase * 2))
            context.fill(shape(size: petal.size), with: .color(colors[petal.tone].opacity(0.55)))
        }
    }

    /// A blossom petal with a small notch at its tip.
    static func shape(size h: CGFloat) -> Path {
        let w = h * 0.62
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        path.addQuadCurve(to: CGPoint(x: w * 0.4, y: -h), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -h * 0.68))
        path.addLine(to: CGPoint(x: -w * 0.4, y: -h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h), control: CGPoint(x: -w, y: 0))
        return path
    }
}

/// Snow at three depths, so the page has distance: small slow flakes far
/// away, middle ones, and a few large soft ones close by. Every 25 seconds a
/// gentle 4-second gust leans it all sideways, the near flakes most. A still
/// frost pattern sits in the four corners.
private enum WinterSnow {
    struct Flake {
        let x, offset, radius, fall, sway, swaySpeed, phase, gust, opacity: CGFloat
        let isNear: Bool
    }

    static let flakes: [Flake] = {
        var random = SeededRandom(seed: 21)
        let depths: [(count: Int, radius: ClosedRange<CGFloat>, fall: ClosedRange<CGFloat>, opacity: CGFloat, gust: CGFloat, sway: CGFloat, near: Bool)] = [
            (18, 0.9...1.3, 7...11, 0.6, 0.35, 6, false),
            (12, 1.8...2.4, 13...19, 0.72, 0.65, 12, false),
            (5, 3.6...5, 24...32, 0.55, 1, 20, true),
        ]
        return depths.flatMap { depth in
            (0..<depth.count).map { _ in
                Flake(x: random.next(), offset: random.next(),
                      radius: depth.radius.lowerBound + random.next() * (depth.radius.upperBound - depth.radius.lowerBound),
                      fall: depth.fall.lowerBound + random.next() * (depth.fall.upperBound - depth.fall.lowerBound),
                      sway: depth.sway, swaySpeed: 0.3 + random.next() * 0.4, phase: random.next() * .pi * 2,
                      gust: depth.gust, opacity: depth.opacity, isNear: depth.near)
            }
        }
    }()
    static let blue = SeasonColor.make(0x8FA6B8)

    /// How far the gusts have pushed the snow by `t`: each is a 4-second
    /// sin² swell every 25 seconds, added up so the drift never jumps.
    static func gustOffset(_ t: CGFloat) -> CGFloat {
        let period: CGFloat = 25
        let g = t.truncatingRemainder(dividingBy: period)
        let done = (t / period).rounded(.down) * 2
        let current = g < 4 ? g / 2 - sin(.pi * g / 2) / .pi : 2
        return 38 * (done + current)
    }

    static func draw(in canvas: GraphicsContext, size page: CGSize, time t: CGFloat) {
        let gust = gustOffset(t)
        for flake in flakes {
            let travelY = page.height + 20
            let y = SeasonPainter.wrap(flake.offset * travelY + t * flake.fall, travelY) - 10
            let travelX = page.width + 20
            let x = SeasonPainter.wrap(flake.x * travelX + gust * flake.gust + flake.sway * sin(t * flake.swaySpeed + flake.phase), travelX) - 10
            let center = CGPoint(x: x, y: y)
            if flake.isNear {
                // Close to the eye: soft, like slightly out of focus.
                let outer = flake.radius * 1.6
                canvas.fill(circle(center, outer), with: .radialGradient(
                    Gradient(colors: [blue.opacity(flake.opacity), blue.opacity(0)]), center: center, startRadius: 0, endRadius: outer))
                canvas.fill(circle(center, flake.radius), with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.9), Color.white.opacity(0)]), center: center, startRadius: 0, endRadius: flake.radius))
            } else {
                // Pale blue-grey with a white centre, so it shows on the pale paper.
                canvas.fill(circle(center, flake.radius), with: .color(blue.opacity(flake.opacity)))
                canvas.fill(circle(center, flake.radius / 2), with: .color(.white.opacity(0.85)))
            }
        }
    }

    /// Fine frost in each corner: a soft white glow and a few branching
    /// crystals, kept small so it stays clear of the text.
    static func drawFrost(in canvas: GraphicsContext, size page: CGSize) {
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (.zero, 1, 1), (CGPoint(x: page.width, y: 0), -1, 1),
            (CGPoint(x: 0, y: page.height), 1, -1), (CGPoint(x: page.width, y: page.height), -1, -1),
        ]
        for (corner, sx, sy) in corners {
            canvas.fill(circle(corner, 70), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0)]), center: corner, startRadius: 0, endRadius: 70))
            var context = canvas
            context.translateBy(x: corner.x, y: corner.y)
            context.scaleBy(x: sx, y: sy)
            context.stroke(crystals, with: .color(blue.opacity(0.16)), lineWidth: 0.5)
        }
    }

    /// Five branching crystals growing out from a top-left corner.
    static let crystals: Path = {
        var random = SeededRandom(seed: 3)
        var path = Path()
        for _ in 0..<5 {
            var point = CGPoint.zero
            var angle = CGFloat.pi / 4 + (random.next() - 0.5) * 1.5
            path.move(to: point)
            for _ in 0..<5 {
                let next = CGPoint(x: point.x + cos(angle) * 9, y: point.y + sin(angle) * 9)
                path.addLine(to: next)
                for side: CGFloat in [-1, 1] {
                    path.move(to: next)
                    path.addLine(to: CGPoint(x: next.x + cos(angle + side * 0.9) * 4, y: next.y + sin(angle + side * 0.9) * 4))
                }
                path.move(to: next)
                point = next
                angle += (random.next() - 0.5) * 0.4
            }
        }
        return path
    }()

    static func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
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
