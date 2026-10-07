import SwiftUI
import UIKit

/// Starlight's slow twinkle: a few tiny stars in the side margins that
/// brighten and fade over several seconds. The still field of stars is part
/// of the paper (`PaperTexture`); these stay out of the text column, never
/// take a tap, are hidden from VoiceOver, pause in Low Power Mode and are
/// left out with Reduce Motion (ReaderView checks).
struct StarlightTwinkleView: View {
    /// The text column's insets; stars stay in the margins outside it.
    let textInsets: UIEdgeInsets

    @State private var start = Date.now
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        let left = textInsets.left
        let right = textInsets.right
        // A slow fade needs few frames.
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: lowPower)) { context in
            let time = context.date.timeIntervalSince(start)
            Canvas { canvas, size in
                Self.draw(in: canvas, size: size, time: time, left: left, right: right)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    nonisolated private static func draw(in canvas: GraphicsContext, size: CGSize, time: TimeInterval, left: CGFloat, right: CGFloat) {
        // Keep clear of the text by a few points on each side.
        let gap: CGFloat = 8
        let fadeIn = min(1, time / 3)
        for star in TwinkleStar.all {
            let width = star.onLeft ? left - gap * 2 : right - gap * 2
            guard width > 4 else { continue }
            let x = star.onLeft ? gap + star.x * width : size.width - right + gap + star.x * width
            let y = (0.08 + star.y * 0.84) * size.height
            let glow = 0.5 + 0.5 * sin(time * star.speed + star.phase)
            let opacity = (0.08 + 0.32 * glow) * fadeIn
            let radius = star.radius
            let halo = radius * 4
            canvas.fill(
                Path(ellipseIn: CGRect(x: x - halo, y: y - halo, width: halo * 2, height: halo * 2)),
                with: .color(TwinkleStar.tint.opacity(opacity * 0.2))
            )
            canvas.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(TwinkleStar.tint.opacity(opacity))
            )
        }
    }
}

/// One twinkling star, from fixed random numbers so it's the same every time.
private struct TwinkleStar {
    let onLeft: Bool
    let x: CGFloat       // 0...1 across its margin
    let y: CGFloat       // 0...1 down the page
    let radius: CGFloat
    let speed: Double    // radians per second: one twinkle every 7–14 s
    let phase: Double

    static let all: [TwinkleStar] = {
        var random = SeededRandom(seed: 53)
        return (0..<8).map { index in
            TwinkleStar(
                onLeft: index.isMultiple(of: 2),
                x: random.next(),
                y: random.next(),
                radius: 0.8 + random.next() * 0.5,
                speed: Double(0.45 + random.next() * 0.45),
                phase: Double(random.next()) * .pi * 2
            )
        }
    }()

    /// A soft, slightly warm white.
    static let tint = Color(uiColor: UIColor(hex: 0xE6E2D3))
}
