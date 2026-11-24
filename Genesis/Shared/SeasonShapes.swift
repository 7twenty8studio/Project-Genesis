import SwiftUI

/// The seasons' shapes, shared by the reader (`SeasonalEffectView`) and the
/// drifting verse widget (`SeasonalMotion`): maple, oak and birch leaves,
/// six-sided snow crystals, cherry petals and whole blossoms, and summer's
/// butterfly. Every path is built once at unit size, centred on the origin
/// and pointing up; scale it with `scaled(_:)`.
enum SeasonShapes {
    // MARK: Leaves (length 1, tip at y = -0.5, stem below)

    enum LeafKind: Int, CaseIterable, Sendable {
        case maple, oak, birch

        /// The mix used across the page: maples most often.
        static func mixed(_ index: Int) -> LeafKind {
            [.maple, .oak, .birch, .maple, .birch, .oak, .maple][index % 7]
        }
    }

    static func leaf(_ kind: LeafKind) -> Path {
        switch kind {
        case .maple: maple
        case .oak: oak
        case .birch: birch
        }
    }

    /// The same leaves with far fewer points, for the verse widget: its
    /// leaves are 8–17 pt, and every point of every leaf in every timeline
    /// entry goes into WidgetKit's archive, which has a tight budget.
    static func lightLeaf(_ kind: LeafKind) -> Path {
        switch kind {
        case .maple: lightMaple
        case .oak: lightOak
        case .birch: lightBirch
        }
    }

    static func leafVeins(_ kind: LeafKind) -> Path {
        switch kind {
        case .maple: mapleVeins
        case .oak: oakVeins
        case .birch: birchVeins
        }
    }

    /// Five lobes, each broad with a pointed end and a tooth either side,
    /// and a notch where the stem joins.
    private static let mapleLobes: [(angle: CGFloat, reach: CGFloat, width: CGFloat)] = [
        (0, 1, 0.36), (0.9, 0.88, 0.34), (-0.9, 0.88, 0.34), (1.85, 0.5, 0.28), (-1.85, 0.5, 0.28),
    ]
    private static let mapleCentre: CGFloat = 0.08

    static let maple = mapleOutline(steps: 240)
    static let lightMaple = mapleOutline(steps: 90)

    private static func mapleOutline(steps: Int) -> Path {
        var path = Path()
        for i in 0...steps {
            let theta = -CGFloat.pi + 2 * .pi * CGFloat(i) / CGFloat(steps) // 0 points up
            var r: CGFloat = 0.12
            for lobe in mapleLobes {
                let d = angleBetween(theta, lobe.angle)
                let body = exp(-pow(d / lobe.width, 2))
                let tip = exp(-pow(d / (lobe.width * 0.28), 2)) * 0.18
                let tooth = exp(-pow(abs(d) - lobe.width * 0.75, 2) / (2 * pow(lobe.width * 0.09, 2))) * 0.10
                r = max(r, 0.12 + lobe.reach * (0.30 * body + tip) + lobe.reach * tooth * body)
            }
            let back = abs(angleBetween(theta, .pi))
            if back < 0.45 { r = min(r, 0.08 + 0.25 * back) }
            let point = CGPoint(x: sin(theta) * r, y: -cos(theta) * r + mapleCentre)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    static let mapleVeins: Path = {
        var path = Path()
        let centre = CGPoint(x: 0, y: mapleCentre)
        for lobe in mapleLobes {
            let r = 0.12 + lobe.reach * 0.42
            path.move(to: centre)
            path.addLine(to: CGPoint(x: sin(lobe.angle) * r, y: -cos(lobe.angle) * r + mapleCentre))
        }
        path.move(to: centre)
        path.addLine(to: CGPoint(x: 0, y: 0.45))
        return path
    }()

    /// Rounded lobes with deep bays between them, narrowing to the stem.
    static func oakHalfWidth(_ s: CGFloat) -> CGFloat {
        let envelope = pow(max(0, sin(.pi * min(1, s * 1.02))), 0.8) * 0.34 * (1 - 0.35 * s)
        return envelope * (0.45 + 0.55 * pow(abs(cos(.pi * 3.5 * s + 0.3)), 0.6))
    }

    /// An oval with a pointed tip and a finely toothed edge.
    static func birchHalfWidth(_ s: CGFloat) -> CGFloat {
        let envelope = sin(.pi * pow(s, 0.75)) * 0.3
        let saw = (s * 16).truncatingRemainder(dividingBy: 1)
        let tooth = (saw < 0.5 ? saw : 1 - saw) * 2
        return max(0, envelope * (1 + 0.08 * tooth - 0.04))
    }

    static let oak = outline(oakHalfWidth)
    static let birch = outline(birchHalfWidth)
    static let lightOak = outline(oakHalfWidth, steps: 24)
    static let lightBirch = outline(birchHalfWidth, steps: 32)
    static let oakVeins = veins(oakHalfWidth, pairs: 4)
    static let birchVeins = veins(birchHalfWidth, pairs: 6)

    /// A symmetrical leaf from its half-width at each point along it (0 tip, 1 base).
    private static func outline(_ halfWidth: (CGFloat) -> CGFloat, steps: Int = 80) -> Path {
        let side = (0...steps).map { i -> CGPoint in
            let s = CGFloat(i) / CGFloat(steps)
            return CGPoint(x: halfWidth(s), y: s - 0.5)
        }
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -0.5))
        side.forEach { path.addLine(to: $0) }
        side.reversed().forEach { path.addLine(to: CGPoint(x: -$0.x, y: $0.y)) }
        path.closeSubpath()
        return path
    }

    /// A midrib running on into the stem, and side veins angled to the tip.
    private static func veins(_ halfWidth: (CGFloat) -> CGFloat, pairs: Int) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -0.46))
        path.addLine(to: CGPoint(x: 0, y: 0.62))
        for i in 1...pairs {
            let s = CGFloat(i) / CGFloat(pairs + 1)
            let y = s - 0.5
            let reach = halfWidth(s) * 0.75
            for side: CGFloat in [1, -1] {
                path.move(to: CGPoint(x: 0, y: y + 0.04))
                path.addLine(to: CGPoint(x: side * reach, y: y - 0.03))
            }
        }
        return path
    }

    // MARK: Snow crystals (radius 1)

    enum FlakeKind: Int, CaseIterable, Sendable {
        /// Six arms with two pairs of side branches.
        case stellar
        /// Feathery arms, branched all the way out, round a small hexagon.
        case fern
        /// A hexagonal plate with short arms ending in small plates.
        case plate
    }

    /// The arms, to be stroked.
    static func flakeArms(_ kind: FlakeKind) -> Path {
        switch kind {
        case .stellar: stellarArms
        case .fern: fernArms
        case .plate: plateArms
        }
    }

    /// The solid parts (centre hexagon, plate tips), if any.
    static func flakeCore(_ kind: FlakeKind) -> Path? {
        switch kind {
        case .stellar: nil
        case .fern: fernCore
        case .plate: plateCore
        }
    }

    private static let stellarArms = arms(branches: [(0.45, 0.3), (0.72, 0.2)])
    private static let fernArms = arms(branches: [(0.3, 0.32), (0.5, 0.36), (0.7, 0.26), (0.86, 0.14)])
    private static let plateArms = arms(branches: [(0.62, 0.16)])
    private static let fernCore = hexagon(radius: 0.16)
    private static let plateCore: Path = {
        var path = hexagon(radius: 0.28)
        for k in 0..<6 {
            let turn = CGAffineTransform(rotationAngle: CGFloat(k) * .pi / 3)
            var tip = Path()
            tip.move(to: CGPoint(x: 0, y: -1))
            tip.addLine(to: CGPoint(x: 0.1, y: -0.88))
            tip.addLine(to: CGPoint(x: 0, y: -0.76))
            tip.addLine(to: CGPoint(x: -0.1, y: -0.88))
            tip.closeSubpath()
            path.addPath(tip, transform: turn)
        }
        return path
    }()

    /// Six arms, each with side branches at 60° (position along the arm, length).
    private static func arms(branches: [(at: CGFloat, length: CGFloat)]) -> Path {
        var arm = Path()
        arm.move(to: .zero)
        arm.addLine(to: CGPoint(x: 0, y: -1))
        for branch in branches {
            for side: CGFloat in [1, -1] {
                arm.move(to: CGPoint(x: 0, y: -branch.at))
                arm.addLine(to: CGPoint(x: side * sin(.pi / 3) * branch.length, y: -branch.at - cos(.pi / 3) * branch.length))
            }
        }
        var path = Path()
        for k in 0..<6 {
            path.addPath(arm, transform: CGAffineTransform(rotationAngle: CGFloat(k) * .pi / 3))
        }
        return path
    }

    private static func hexagon(radius: CGFloat) -> Path {
        var path = Path()
        for k in 0..<6 {
            let angle = CGFloat(k) * .pi / 3
            let point = CGPoint(x: sin(angle) * radius, y: -cos(angle) * radius)
            if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: Blossom (petal: half-length 1; blossom: radius 1)

    /// A cherry petal with a small notch at its tip (y from -1 to 1).
    static let petal: Path = {
        let h: CGFloat = 1
        let w = h * 0.62
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        path.addQuadCurve(to: CGPoint(x: w * 0.4, y: -h), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -h * 0.68))
        path.addLine(to: CGPoint(x: -w * 0.4, y: -h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h), control: CGPoint(x: -w, y: 0))
        return path
    }()

    /// Five petals round the centre.
    static let blossomPetals: Path = {
        var path = Path()
        let one = petal.applying(CGAffineTransform(scaleX: 0.55, y: 0.55).translatedBy(x: 0, y: -1))
        for k in 0..<5 {
            path.addPath(one, transform: CGAffineTransform(rotationAngle: CGFloat(k) * 2 * .pi / 5))
        }
        return path
    }()

    static let blossomCentre = Path(ellipseIn: CGRect(x: -0.18, y: -0.18, width: 0.36, height: 0.36))

    private static let stamenAngles = (0..<8).map { CGFloat($0) * .pi / 4 + 0.2 }

    static let stamens: Path = {
        var path = Path()
        for angle in stamenAngles {
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: cos(angle) * 0.42, y: sin(angle) * 0.42))
        }
        return path
    }()

    static let stamenTips: Path = {
        var path = Path()
        for angle in stamenAngles {
            let c = CGPoint(x: cos(angle) * 0.44, y: sin(angle) * 0.44)
            path.addEllipse(in: CGRect(x: c.x - 0.05, y: c.y - 0.05, width: 0.1, height: 0.1))
        }
        return path
    }()

    // MARK: Butterfly (wingspan about 2, body along y)

    /// The right wings (mirror for the left): upper and lower.
    static let butterflyUpperWing: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -0.1))
        path.addCurve(to: CGPoint(x: 0.85, y: -0.15), control1: CGPoint(x: 0.3, y: -0.9), control2: CGPoint(x: 1.05, y: -0.75))
        path.addCurve(to: .zero, control1: CGPoint(x: 0.75, y: 0.05), control2: CGPoint(x: 0.3, y: 0.05))
        path.closeSubpath()
        return path
    }()

    static let butterflyLowerWing: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0.02))
        path.addCurve(to: CGPoint(x: 0.4, y: 0.7), control1: CGPoint(x: 0.55, y: 0.05), control2: CGPoint(x: 0.75, y: 0.55))
        path.addCurve(to: CGPoint(x: 0, y: 0.1), control1: CGPoint(x: 0.2, y: 0.75), control2: CGPoint(x: 0.05, y: 0.4))
        path.closeSubpath()
        return path
    }()

    static let butterflyBody = Path(ellipseIn: CGRect(x: -0.06, y: -0.3, width: 0.12, height: 0.9))

    static let butterflyAntennae: Path = {
        var path = Path()
        for side: CGFloat in [1, -1] {
            path.move(to: CGPoint(x: 0, y: -0.25))
            path.addQuadCurve(to: CGPoint(x: side * 0.2, y: -0.65), control: CGPoint(x: side * 0.05, y: -0.55))
        }
        return path
    }()

    // MARK: Helpers

    /// The signed angle from b to a, in -π...π.
    static func angleBetween(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        atan2(sin(a - b), cos(a - b))
    }
}

extension Path {
    /// A unit-size season shape at a given size.
    func scaled(_ size: CGFloat) -> Path {
        applying(CGAffineTransform(scaleX: size, y: size))
    }
}

/// A unit season path as a SwiftUI shape, scaled to fit its frame.
struct SeasonShape: Shape {
    let unit: Path
    /// The unit path's extent that should fill the frame's shorter side.
    var span: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / span
        return unit.applying(CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: scale, y: scale))
    }
}

/// Summer's butterfly: now and then it crosses the page from left to right
/// the way a real one flies: an unsteady, wandering path (now and then
/// doubling back), a little lift with every wingbeat, bursts of flapping
/// between short glides on open wings, and its head always turned the way
/// it's going. Pure, so the reader, verse images and tests agree on where
/// it is.
enum ButterflyFlight {
    /// Seconds between crossings, and how long a crossing takes.
    static let period: CGFloat = 90
    static let crossing: CGFloat = 16

    struct State: Equatable {
        let position: CGPoint
        /// The drawing's rotation: its head (drawn pointing up) turned
        /// toward where it's flying, banking a little into turns.
        let angle: CGFloat
        /// 0.35...1, how open the wings are (they beat by narrowing).
        let wingOpen: CGFloat
    }

    /// Where it is at `time`, or nil between crossings.
    static func state(at time: CGFloat, page: CGSize) -> State? {
        let phase = time.truncatingRemainder(dividingBy: period)
        guard phase >= 0, phase < crossing else { return nil }
        let flap = flapping(at: phase)
        // Each downstroke lifts it a little; it sinks between them.
        let beat = sin(phase * beatSpeed)
        var position = course(at: phase, page: page)
        position.y -= 2.5 * flap * beat
        return State(position: position, angle: heading(at: phase, page: page),
                     wingOpen: 1 - 0.65 * flap * abs(beat))
    }

    /// Wingbeats per second × 2π (abs(sin) beats twice a turn).
    static let beatSpeed: CGFloat = 7

    /// 0...1: flapping hard, or 0 while it glides on open wings.
    static func flapping(at phase: CGFloat) -> CGFloat {
        let glide = sin(phase * 0.9 + 1.3) * 0.6 + sin(phase * 2.3) * 0.4
        // Glides when `glide` is high, easing in and out.
        let x = min(max((glide - 0.35) / 0.3, 0), 1)
        return 1 - x * x * (3 - 2 * x)
    }

    /// The smooth course (without the beat's bob): across and a little up
    /// the page, wandering on top, the wander fading at both ends so it
    /// always enters and leaves off the page.
    static func course(at phase: CGFloat, page: CGSize) -> CGPoint {
        let progress = phase / crossing
        let envelope = sin(.pi * min(max(progress, 0), 1))
        let span = min(page.width, page.height)
        let wanderX = span * (0.09 * sin(phase * 0.55 + 0.4) + 0.05 * sin(phase * 1.35 + 2.1))
        let wanderY = span * (0.07 * sin(phase * 0.8 + 1) + 0.035 * sin(phase * 1.9 + 0.3))
        return CGPoint(x: -20 + (page.width + 40) * progress + envelope * wanderX,
                       y: page.height * (0.7 - 0.25 * progress) + envelope * wanderY)
    }

    /// The direction it's flying (from the course a moment either side),
    /// turned so the drawing's head leads, plus a slight bank into turns.
    static func heading(at phase: CGFloat, page: CGSize) -> CGFloat {
        let step: CGFloat = 0.12
        let before = course(at: phase - step, page: page)
        let now = course(at: phase, page: page)
        let after = course(at: phase + step, page: page)
        let incoming = atan2(now.y - before.y, now.x - before.x)
        let outgoing = atan2(after.y - now.y, after.x - now.x)
        let direction = atan2(after.y - before.y, after.x - before.x)
        let turn = SeasonShapes.angleBetween(outgoing, incoming)
        return direction + .pi / 2 + max(-0.3, min(0.3, turn * 2))
    }
}
