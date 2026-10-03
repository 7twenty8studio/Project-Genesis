import SwiftUI

/// A few seconds of the season drifting across the page when the reader
/// opens with a seasonal theme: autumn leaves, winter snow, spring blossom or
/// summer light. Sparse, soft and translucent, it fades out on its own, never
/// takes a tap, and is skipped with Reduce Motion (ReaderView checks).
struct SeasonalEffectView: View {
    let season: Season

    static let duration: TimeInterval = 9

    @State private var start = Date.now
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(paused: finished)) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSince(start)
                guard time < Self.duration else { return }
                // Fade in over the first second, out over the last two.
                canvas.opacity = min(1, time, max(0, (Self.duration - time) / 2))
                for particle in particles {
                    particle.draw(in: canvas, size: size, time: time, season: season)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(Self.duration))
            finished = true
        }
    }

    private var particles: [SeasonParticle] {
        SeasonParticle.make(for: season)
    }
}

/// One leaf, snowflake, petal or mote, described by fixed random numbers so
/// its path is a pure function of time.
private struct SeasonParticle {
    let x: CGFloat          // 0...1 across the page
    let delay: TimeInterval // when it appears
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
        case .autumn: 14
        case .winter: 36
        case .spring: 18
        case .summer: 20
        }
        return (0..<count).map { _ in
            SeasonParticle(
                x: random.next(),
                delay: Double(random.next()) * 4,
                speed: 45 + random.next() * 55,
                sway: 12 + random.next() * 30,
                swaySpeed: 0.6 + random.next() * 0.9,
                phase: random.next() * .pi * 2,
                size: random.next(),
                spin: (random.next() - 0.5) * 2.4,
                tone: Int(random.next() * 3)
            )
        }
    }

    func draw(in canvas: GraphicsContext, size page: CGSize, time: TimeInterval, season: Season) {
        let t = CGFloat(time - delay)
        guard t > 0 else { return }
        let drift = sin(t * swaySpeed + phase) * sway
        var context = canvas
        switch season {
        case .autumn:
            let position = CGPoint(x: x * page.width + drift, y: -24 + t * speed)
            guard position.y < page.height + 30 else { return }
            context.translateBy(x: position.x, y: position.y)
            context.rotate(by: .radians(Double(phase + t * spin)))
            // Tumbling: the leaf turns over as it falls.
            context.scaleBy(x: max(0.2, abs(cos(t * swaySpeed * 1.3 + phase))), y: 1)
            let length = 14 + size * 10
            context.fill(Self.leaf(length: length), with: .color(Self.autumn[tone].opacity(0.75)))
            var vein = Path()
            vein.move(to: CGPoint(x: 0, y: -length / 2))
            vein.addLine(to: CGPoint(x: 0, y: length / 2 + 3))
            context.stroke(vein, with: .color(Self.autumn[tone].opacity(0.9)), lineWidth: 0.8)
        case .winter:
            let position = CGPoint(x: x * page.width + drift * 0.6, y: -10 + t * speed * 0.55)
            guard position.y < page.height + 10 else { return }
            let diameter = 2.5 + size * 4
            let flake = Path(ellipseIn: CGRect(x: position.x - diameter / 2, y: position.y - diameter / 2, width: diameter, height: diameter))
            // Pale blue-grey with a white centre, so it shows on the pale paper.
            context.fill(flake, with: .color(Self.winter.opacity(0.55)))
            context.fill(Path(ellipseIn: CGRect(x: position.x - diameter / 4, y: position.y - diameter / 4, width: diameter / 2, height: diameter / 2)), with: .color(.white.opacity(0.8)))
        case .spring:
            let position = CGPoint(x: x * page.width + drift, y: -16 + t * speed * 0.75)
            guard position.y < page.height + 20 else { return }
            context.translateBy(x: position.x, y: position.y)
            context.rotate(by: .radians(Double(phase + t * spin)))
            context.scaleBy(x: 1, y: max(0.25, abs(sin(t * swaySpeed + phase))))
            let width = 7 + size * 5
            context.fill(Path(ellipseIn: CGRect(x: -width / 2, y: -width / 3, width: width, height: width * 0.66)), with: .color(Self.spring[tone].opacity(0.7)))
        case .summer:
            // Motes of light rise slowly and twinkle.
            let position = CGPoint(x: x * page.width + drift * 0.5, y: page.height + 10 - t * speed * 0.45)
            guard position.y > -10 else { return }
            let diameter = 3 + size * 4
            let twinkle = 0.45 + 0.35 * sin(t * 2.2 + phase)
            context.addFilter(.blur(radius: 1.6))
            context.fill(Path(ellipseIn: CGRect(x: position.x - diameter, y: position.y - diameter, width: diameter * 2, height: diameter * 2)), with: .color(Self.summer.opacity(twinkle * 0.5)))
            context.fill(Path(ellipseIn: CGRect(x: position.x - diameter / 2, y: position.y - diameter / 2, width: diameter, height: diameter)), with: .color(Self.summer.opacity(twinkle)))
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
    private static let autumn: [Color] = [0xB4693A, 0xC99541, 0x9C4F2E].map(color)
    private static let winter = color(0x8FA6B8)
    private static let spring: [Color] = [0xE2A9B5, 0xEDC4CB, 0xD493A2].map(color)
    private static let summer = color(0xE0B866)

    private static func color(_ hex: UInt32) -> Color {
        Color(uiColor: UIColor(hex: hex))
    }
}
