import SwiftUI

/// The season drifting gently across the page while reading with a seasonal
/// theme, each with its own kind of motion: maple, oak and birch leaves
/// tumbling down, spring petals and blossoms riding a breeze over patches of
/// warm light, winter snow (real crystals up close) falling at three depths
/// with a gust now and then and frost in the corners, or summer sunlight
/// (slow rays, warm colour washes, dust in the beams and a passing
/// butterfly). Shapes live in `SeasonShapes`. Sparse
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
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: DispatchQueue.main)) { _ in
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

/// Seven leaves at a time (maple, oak and birch, `SeasonShapes`), falling
/// 14–26 points a second, swaying and turning over as they go.
private enum AutumnLeaves {
    struct Leaf {
        let x, offset, speed, sway, swaySpeed, phase, size, spin: CGFloat
        let tone: Int
        let kind: SeasonShapes.LeafKind
    }

    static let leaves: [Leaf] = {
        var random = SeededRandom(seed: 14)
        return (0..<7).map { index in
            Leaf(x: random.next(), offset: random.next(), speed: 14 + random.next() * 12,
                 sway: 18 + random.next() * 22, swaySpeed: 0.35 + random.next() * 0.35,
                 phase: random.next() * .pi * 2, size: random.next(), spin: (random.next() - 0.5) * 1.2,
                 tone: Int(random.next() * 3) % 3, kind: .mixed(index))
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
            // Large enough for a maple's points and an oak's lobes to show.
            let length = 20 + leaf.size * 14
            context.fill(SeasonShapes.leaf(leaf.kind).scaled(length), with: .color(colors[leaf.tone].opacity(0.45)))
            context.stroke(SeasonShapes.leafVeins(leaf.kind).scaled(length), with: .color(colors[leaf.tone].opacity(0.6)), lineWidth: 0.8)
        }
    }
}

/// Twelve blossom petals drifting down and to the right on one shared
/// breeze that swells and settles over 50 seconds, each fluttering and
/// flipping on its own, over two slow patches of warm light. One in four
/// is a whole cherry blossom.
private enum SpringPetals {
    struct Petal {
        let x, offset, fall, drift, flutter, flutterSpeed, phase, spin, size: CGFloat
        let tone: Int
        let isBlossom: Bool
    }

    static let petals: [Petal] = {
        var random = SeededRandom(seed: 8)
        return (0..<12).map { index in
            Petal(x: random.next(), offset: random.next(), fall: 12 + random.next() * 8, drift: 6 + random.next() * 6,
                  flutter: 8 + random.next() * 14, flutterSpeed: 0.5 + random.next() * 0.6, phase: random.next() * .pi * 2,
                  spin: (random.next() - 0.5) * 1.4, size: 6.5 + random.next() * 4, tone: Int(random.next() * 3) % 3,
                  isBlossom: index % 4 == 0)
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
            if petal.isBlossom {
                // A whole flower turns over less far, so it keeps its shape.
                context.scaleBy(x: max(0.45, abs(cos(t * petal.flutterSpeed * 1.4 + petal.phase))), y: 1)
                drawBlossom(in: context, radius: petal.size * 1.9, tone: petal.tone)
            } else {
                // Flipping on both axes reads lighter than a leaf's tumble.
                context.scaleBy(x: max(0.2, abs(cos(t * petal.flutterSpeed * 1.4 + petal.phase))),
                                y: 0.65 + 0.35 * sin(t * petal.flutterSpeed + petal.phase * 2))
                context.fill(SeasonShapes.petal.scaled(petal.size), with: .color(colors[petal.tone].opacity(0.55)))
            }
        }
    }

    static let heart = SeasonColor.make(0xC97D8E)
    static let pollen = SeasonColor.make(0xE0B25A)

    /// Five petals, a deep pink heart and a ring of stamens.
    static func drawBlossom(in context: GraphicsContext, radius r: CGFloat, tone: Int) {
        context.fill(SeasonShapes.blossomPetals.scaled(r), with: .color(colors[tone].opacity(0.6)))
        context.fill(SeasonShapes.blossomCentre.scaled(r), with: .color(heart.opacity(0.6)))
        context.stroke(SeasonShapes.stamens.scaled(r), with: .color(heart.opacity(0.6)), lineWidth: max(0.4, r * 0.04))
        context.fill(SeasonShapes.stamenTips.scaled(r), with: .color(pollen.opacity(0.6)))
    }
}

/// Snow at three depths, so the page has distance: small slow flakes far
/// away (dots, too small to show a shape), six-armed crystals in the middle,
/// and a few large ones close by, stellar, fern and plate crystals
/// (`SeasonShapes`) turning slowly as they fall. Every 25 seconds a gentle
/// 4-second gust leans it all sideways, the near flakes most. A still frost
/// pattern sits in the four corners.
private enum WinterSnow {
    struct Flake {
        let x, offset, radius, fall, sway, swaySpeed, phase, gust, opacity, turn: CGFloat
        let isNear: Bool
        /// Nil: a far-away dot.
        let kind: SeasonShapes.FlakeKind?
    }

    static let flakes: [Flake] = {
        var random = SeededRandom(seed: 21)
        let depths: [(count: Int, radius: ClosedRange<CGFloat>, fall: ClosedRange<CGFloat>, opacity: CGFloat, gust: CGFloat, sway: CGFloat, near: Bool, kinds: [SeasonShapes.FlakeKind])] = [
            (18, 0.9...1.3, 7...11, 0.6, 0.35, 6, false, []),
            (12, 3...4.2, 13...19, 0.9, 0.65, 12, false, [.stellar, .plate]),
            (5, 7...10, 24...32, 0.8, 1, 20, true, [.fern, .plate, .stellar]),
        ]
        return depths.flatMap { depth in
            (0..<depth.count).map { index in
                Flake(x: random.next(), offset: random.next(),
                      radius: depth.radius.lowerBound + random.next() * (depth.radius.upperBound - depth.radius.lowerBound),
                      fall: depth.fall.lowerBound + random.next() * (depth.fall.upperBound - depth.fall.lowerBound),
                      sway: depth.sway, swaySpeed: 0.3 + random.next() * 0.4, phase: random.next() * .pi * 2,
                      gust: depth.gust, opacity: depth.opacity, turn: index.isMultiple(of: 2) ? 0.15 : -0.15,
                      isNear: depth.near, kind: depth.kinds.isEmpty ? nil : depth.kinds[index % depth.kinds.count])
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
            // Room past the edges for the near crystals and their halos.
            let travelY = page.height + 40
            let y = SeasonPainter.wrap(flake.offset * travelY + t * flake.fall, travelY) - 20
            let travelX = page.width + 40
            let x = SeasonPainter.wrap(flake.x * travelX + gust * flake.gust + flake.sway * sin(t * flake.swaySpeed + flake.phase), travelX) - 20
            let center = CGPoint(x: x, y: y)
            if let kind = flake.kind {
                var context = canvas
                context.translateBy(x: x, y: y)
                context.rotate(by: .radians(Double(flake.phase + t * flake.turn)))
                if flake.isNear {
                    // Close to the eye: a soft halo, as if slightly out of focus.
                    let halo = flake.radius * 1.3
                    context.fill(circle(.zero, halo), with: .radialGradient(
                        Gradient(colors: [blue.opacity(0.25), blue.opacity(0)]), center: .zero, startRadius: 0, endRadius: halo))
                }
                drawCrystal(kind, radius: flake.radius, opacity: flake.opacity, in: context)
            } else {
                // Pale blue-grey with a white centre, so it shows on the pale paper.
                canvas.fill(circle(center, flake.radius), with: .color(blue.opacity(flake.opacity)))
                canvas.fill(circle(center, flake.radius / 2), with: .color(.white.opacity(0.85)))
            }
        }
    }

    /// A crystal in blue-grey with a white line down every arm, so it shows
    /// on the pale paper.
    static func drawCrystal(_ kind: SeasonShapes.FlakeKind, radius r: CGFloat, opacity: CGFloat, in context: GraphicsContext) {
        let arms = SeasonShapes.flakeArms(kind).scaled(r)
        let core = SeasonShapes.flakeCore(kind)?.scaled(r)
        context.stroke(arms, with: .color(blue.opacity(opacity * 0.75)), style: StrokeStyle(lineWidth: max(1.1, r * 0.16), lineCap: .round))
        if let core { context.fill(core, with: .color(blue.opacity(opacity * 0.75))) }
        context.stroke(arms, with: .color(.white.opacity(0.95 * opacity)), style: StrokeStyle(lineWidth: max(0.45, r * 0.06), lineCap: .round))
        if let core { context.stroke(core, with: .color(.white.opacity(0.95 * opacity)), lineWidth: max(0.45, r * 0.06)) }
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
/// through leaves; specks of dust float and twinkle in the beams, and now
/// and then a butterfly crosses the page (`ButterflyFlight`).
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
            let angle = beamAngle(index) + sway  // pointing down and to the left
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

        drawMotes(in: canvas, size: page, source: source, length: length, time: t)
        drawButterfly(in: canvas, size: page, time: t)
    }

    static let ray = SeasonColor.make(0xF0C25E)

    /// The beams' direction (they point down and to the left).
    static func beamAngle(_ index: Int) -> CGFloat { .pi * 0.62 + CGFloat(index) * 0.075 }

    struct Mote {
        let beam: Int
        let start, speed, jitter, radius, twinkle, phase: CGFloat
    }

    static let motes: [Mote] = {
        var random = SeededRandom(seed: 5)
        return (0..<22).map { _ in
            Mote(beam: Int(random.next() * 6) % 6, start: random.next(), speed: 0.004 + random.next() * 0.006,
                 jitter: (random.next() - 0.5) * 0.05, radius: 0.7 + random.next() * 1.1,
                 twinkle: 0.6 + random.next(), phase: random.next() * .pi * 2)
        }
    }()
    static let moteCore = SeasonColor.make(0xFFF8E1)

    /// Dust drifting slowly down each beam, fading in and out at its ends.
    static func drawMotes(in canvas: GraphicsContext, size page: CGSize, source: CGPoint, length: CGFloat, time t: CGFloat) {
        for (index, mote) in motes.enumerated() {
            let i = CGFloat(index)
            let along = (mote.start + t * mote.speed).truncatingRemainder(dividingBy: 1) // 0..<1 along its stretch
            let angle = beamAngle(mote.beam) + mote.jitter
            let distance = length * (0.15 + 0.75 * along) * 0.75
            let center = CGPoint(x: source.x + cos(angle) * distance + sin(t * 0.3 + i) * 6,
                                 y: source.y + sin(angle) * distance + cos(t * 0.25 + i) * 4)
            let opacity = (0.35 + 0.45 * abs(sin(t * mote.twinkle + mote.phase))) * sin(.pi * along)
            let glow = mote.radius * 3
            canvas.fill(Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
                        with: .radialGradient(Gradient(stops: [
                            .init(color: moteCore.opacity(opacity), location: 0),
                            .init(color: ray.opacity(opacity * 0.55), location: 0.35),
                            .init(color: ray.opacity(0), location: 1),
                        ]), center: center, startRadius: 0, endRadius: glow))
        }
    }

    static let wingUpper = SeasonColor.make(0xD99A4E)
    static let wingLower = SeasonColor.make(0xC9813C)
    static let wingSpot = SeasonColor.make(0xFFF5E1)
    static let butterflyBody = SeasonColor.make(0x6B4A2E)

    /// A small butterfly in warm amber, wings beating by narrowing.
    static func drawButterfly(in canvas: GraphicsContext, size page: CGSize, time t: CGFloat) {
        guard let flight = ButterflyFlight.state(at: t, page: page) else { return }
        let size: CGFloat = 11
        var context = canvas
        context.opacity *= 0.6
        context.translateBy(x: flight.position.x, y: flight.position.y)
        context.rotate(by: .radians(Double(flight.angle)))
        for side: CGFloat in [1, -1] {
            var wing = context
            wing.scaleBy(x: side * flight.wingOpen, y: 1)
            wing.fill(SeasonShapes.butterflyUpperWing.scaled(size), with: .color(wingUpper))
            wing.fill(SeasonShapes.butterflyLowerWing.scaled(size), with: .color(wingLower))
            let spot = CGPoint(x: size * 0.6, y: -size * 0.45)
            let r = size * 0.09
            wing.fill(Path(ellipseIn: CGRect(x: spot.x - r, y: spot.y - r, width: r * 2, height: r * 2)), with: .color(wingSpot.opacity(0.8)))
        }
        context.fill(SeasonShapes.butterflyBody.scaled(size), with: .color(butterflyBody))
        context.stroke(SeasonShapes.butterflyAntennae.scaled(size), with: .color(butterflyBody), lineWidth: max(0.4, size * 0.03))
    }
}

private enum SeasonColor {
    static func make(_ hex: UInt32) -> Color {
        Color(uiColor: UIColor(hex: hex))
    }
}
