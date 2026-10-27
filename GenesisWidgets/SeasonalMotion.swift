import SwiftUI
import WidgetKit

// The seasons' touches, moving in the verse widget: leaves drifting down in
// autumn, snow in winter, petals in spring, warm motes of light in summer.
// Endless: every movement is a rotation the system keeps turning itself (the
// effect clock widgets use for their hands), so it runs without the widget
// being refreshed. Leaves ride on a slow, very large wheel whose centre is
// above and left of the widget: across the widget that is a gentle fall
// down and to the left, and they come round again for ever. Each leaf also
// flutters on a small circle and spins. Kept to the edges (a soft mask) so
// the words stay clear; nothing with Reduce Motion.

struct SeasonalMotionLayer: View {
    let style: WidgetArtStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func moves(_ style: WidgetArtStyle) -> Bool {
        Season(style) != nil
    }

    var body: some View {
        if !reduceMotion, let season = Season(style) {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack(alignment: .topLeading) {
                    ForEach(season.wheels.indices, id: \.self) { index in
                        WheelView(wheel: season.wheels[index], season: season, size: size, seed: UInt64(index + 1) * 7919)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
                .mask(EdgeMask())
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Seasons

private enum Season {
    case autumn, winter, spring, summer

    init?(_ style: WidgetArtStyle) {
        switch style {
        case .autumn: self = .autumn
        case .winter: self = .winter
        case .spring: self = .spring
        case .summer: self = .summer
        default: return nil
        }
    }

    /// One wheel per depth: far ones carry smaller, fainter, slower pieces.
    struct Wheel {
        let count: Int
        /// Seconds for a full turn (slower is gentler).
        let period: TimeInterval
        let sizes: ClosedRange<CGFloat>
        let opacity: Double
    }

    var wheels: [Wheel] {
        switch self {
        case .autumn:
            [Wheel(count: 38, period: 210, sizes: 8...11, opacity: 0.6),
             Wheel(count: 30, period: 150, sizes: 12...17, opacity: 0.9)]
        case .winter:
            // The reader's three depths (SeasonalEffectView's WinterSnow):
            // sizes are diameters, speeds about its falls (9, 16, 28 pt/s).
            [Wheel(count: 36, period: 190, sizes: 1.8...2.6, opacity: 1),
             Wheel(count: 24, period: 107, sizes: 3.6...4.8, opacity: 1),
             Wheel(count: 10, period: 61, sizes: 7.2...10, opacity: 1)]
        case .spring:
            [Wheel(count: 38, period: 200, sizes: 5...7, opacity: 0.65),
             Wheel(count: 30, period: 140, sizes: 8...11, opacity: 0.9)]
        case .summer:
            [Wheel(count: 40, period: 260, sizes: 3...6, opacity: 0.6),
             Wheel(count: 22, period: 190, sizes: 6...10, opacity: 0.45)]
        }
    }

    /// Flutter on a small circle (radius, seconds), none for snow and light.
    var flutter: (radius: CGFloat, period: ClosedRange<Double>)? {
        switch self {
        case .autumn: (5, 4...7)
        case .spring: (4, 3...6)
        case .winter, .summer: nil
        }
    }

    var spins: Bool { self == .autumn || self == .spring }

    @ViewBuilder
    func piece(size: CGFloat, tint: Int) -> some View {
        switch self {
        case .autumn:
            let colors: [Color] = [
                Color(red: 0.71, green: 0.34, blue: 0.17),
                Color(red: 0.79, green: 0.54, blue: 0.18),
                Color(red: 0.56, green: 0.23, blue: 0.16),
                Color(red: 0.65, green: 0.48, blue: 0.23),
            ]
            Image(systemName: "leaf.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(colors[tint % colors.count])
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        case .spring:
            let colors: [Color] = [
                Color(red: 0.95, green: 0.76, blue: 0.80),
                Color(red: 0.97, green: 0.86, blue: 0.89),
                Color(red: 1.0, green: 0.97, blue: 0.96),
            ]
            Ellipse()
                .fill(colors[tint % colors.count])
                .frame(width: size * 0.65, height: size)
                .shadow(color: .black.opacity(0.1), radius: 1, y: 0.5)
        case .winter:
            // Exactly the reader's flakes: pale blue-grey (#8FA6B8) with a
            // white centre; the near ones soft, as if out of focus.
            let blue = Color(red: 0x8F / 255, green: 0xA6 / 255, blue: 0xB8 / 255)
            if size >= 6 {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [blue.opacity(0.55), blue.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.8))
                        .frame(width: size * 1.6, height: size * 1.6)
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.9), .white.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
                        .frame(width: size, height: size)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(blue.opacity(size < 3 ? 0.6 : 0.72))
                        .frame(width: size, height: size)
                    Circle()
                        .fill(.white.opacity(0.85))
                        .frame(width: size / 2, height: size / 2)
                }
            }
        case .summer:
            Circle()
                .fill(Color(red: 0.98, green: 0.85, blue: 0.55))
                .frame(width: size, height: size)
                .blur(radius: size * 0.3)
        }
    }
}

// MARK: - A wheel

private struct WheelView: View {
    let wheel: Season.Wheel
    let season: Season
    let size: CGSize
    let seed: UInt64

    var body: some View {
        // The centre sits above and left of the widget; the wheel reaches
        // from just past its nearest corner to beyond its farthest.
        let center = CGPoint(x: -0.1 * size.width, y: -0.35 * size.height)
        let near = hypot(center.x, center.y) * 0.9
        let far = hypot(size.width - center.x, size.height - center.y) * 1.05
        let diameter = far * 2
        var random = SeededRandom(seed: seed)
        let pieces = (0..<wheel.count).map { _ in
            Piece(
                angle: random.next() * 2 * .pi,
                radius: near + (far - near) * CGFloat(random.next()),
                size: wheel.sizes.lowerBound + (wheel.sizes.upperBound - wheel.sizes.lowerBound) * CGFloat(random.next()),
                spin: 5 + random.next() * 9,
                flutter: random.next(),
                tint: Int(random.next() * 8)
            )
        }
        return ZStack {
            ForEach(pieces.indices, id: \.self) { index in
                let piece = pieces[index]
                PieceView(piece: piece, season: season)
                    .opacity(wheel.opacity)
                    .position(
                        x: far + cos(piece.angle) * piece.radius,
                        y: far + sin(piece.angle) * piece.radius
                    )
            }
        }
        .frame(width: diameter, height: diameter)
        .endlessRotation(period: wheel.period)
        .position(x: center.x, y: center.y)
    }
}

private struct Piece {
    let angle: Double
    let radius: CGFloat
    let size: CGFloat
    let spin: TimeInterval
    /// 0…1, picks the flutter's speed.
    let flutter: Double
    let tint: Int
}

private struct PieceView: View {
    let piece: Piece
    let season: Season

    var body: some View {
        let shape = season.piece(size: piece.size, tint: piece.tint)
        if let flutter = season.flutter {
            let period = flutter.period.lowerBound + (flutter.period.upperBound - flutter.period.lowerBound) * piece.flutter
            // The piece sits on the rim of a small turning circle: a flutter.
            ZStack(alignment: .top) {
                spinning(shape)
            }
            .frame(width: flutter.radius * 2 + piece.size, height: flutter.radius * 2 + piece.size)
            .endlessRotation(period: period)
        } else {
            shape
        }
    }

    @ViewBuilder
    private func spinning(_ shape: some View) -> some View {
        if season.spins {
            shape.endlessRotation(period: piece.spin)
        } else {
            shape
        }
    }
}

// MARK: - Helpers

/// Clear in the middle, where the words are; the seasons show at the edges.
private struct EdgeMask: View {
    var body: some View {
        EllipticalGradient(
            stops: [
                .init(color: .black.opacity(0.5), location: 0),
                .init(color: .black.opacity(0.65), location: 0.55),
                .init(color: .black, location: 1),
            ],
            center: .center,
            startRadiusFraction: 0,
            endRadiusFraction: 0.75
        )
    }
}

/// The same pieces every time (no flicker between refreshes).
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    /// 0…1
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

extension View {
    /// A rotation the system turns endlessly, a full turn every `period`
    /// seconds (the effect behind clock widgets' hands), so it keeps going
    /// between widget refreshes.
    ///
    /// Not available: the iOS 26 SDK no longer offers SwiftUI's
    /// `_clockHandRotationEffect`, so this does nothing and the layer is
    /// off (VerseWidget) until there's a way to turn it.
    func endlessRotation(period: TimeInterval, anchor: UnitPoint = .center) -> some View {
        self
    }
}
