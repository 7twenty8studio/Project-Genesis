import SwiftUI
import WidgetKit

// The seasons' touches, drifting in the verse widget: leaves in autumn, snow
// in winter, petals in spring, warm motes of light in summer. Widgets can't
// animate continuously, so the widget's timeline has an entry every minute
// with a seasonal background (`SeasonalDrift.entryDates`), and each entry
// moves every piece a little further along its path; WidgetKit glides them
// there over two seconds while the widget is on screen. It never stops, a
// small step at a time.
//
// Pieces ride huge, slowly turning wheels whose centre is above and left of
// the widget: across the widget that's a gentle fall down and to the left,
// and they come round again for ever. Each piece also flutters and spins.
// Kept to the edges (a soft mask) so the words stay clear; nothing with
// Reduce Motion (the painted still stays).

enum SeasonalDrift {
    /// Seconds of the reader's drift that one minute of the widget moves on.
    static let secondsPerStep: TimeInterval = 4
    /// One step a minute, for the next hour (the timeline then reloads).
    static let steps = 60

    static func moves(_ style: WidgetArtStyle) -> Bool {
        Season(style) != nil
    }

    /// An entry every minute for an hour, plus the verse's own changes.
    static func entryDates(adding verseDates: [Date], from now: Date) -> [Date] {
        let start = (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        let minutes = (0..<steps).map { Date(timeIntervalSinceReferenceDate: start + Double($0) * 60) }
        let end = minutes.last ?? now
        return (minutes + verseDates.filter { $0 > now && $0 < end }).sorted()
    }

    /// The drift's clock at a date: whole minutes since a fixed day, so
    /// positions carry on smoothly from one entry (and one reload) to the next.
    static func time(at date: Date) -> TimeInterval {
        (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * secondsPerStep
    }
}

struct SeasonalMotionLayer: View {
    let style: WidgetArtStyle
    let date: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion, let season = Season(style) {
            GeometryReader { proxy in
                let size = proxy.size
                let time = SeasonalDrift.time(at: date)
                ZStack(alignment: .topLeading) {
                    ForEach(season.wheels.indices, id: \.self) { index in
                        WheelView(wheel: season.wheels[index], season: season, size: size, seed: UInt64(index + 1) * 7919, time: time)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                // Each minute's step glides in (widgets allow up to two seconds).
                .animation(.easeInOut(duration: 2), value: date)
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
        /// Seconds of drift for a full turn (slower is gentler).
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

    /// Flutter on a small circle (radius, seconds per loop), none for snow and light.
    var flutter: (radius: CGFloat, period: ClosedRange<Double>)? {
        switch self {
        case .autumn: (5, 15...25)
        case .spring: (4, 12...20)
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
    /// The drift's clock (`SeasonalDrift.time`).
    let time: TimeInterval

    var body: some View {
        // The centre sits above and left of the widget; the wheel reaches
        // from just past its nearest corner to beyond its farthest.
        let center = CGPoint(x: -0.1 * size.width, y: -0.35 * size.height)
        let near = hypot(center.x, center.y) * 0.9
        let far = hypot(size.width - center.x, size.height - center.y) * 1.05
        // Turning clockwise: across the widget, down and to the left.
        let turn = (time / wheel.period).truncatingRemainder(dividingBy: 1) * 2 * .pi
        var random = DriftRandom(seed: seed)
        let pieces = (0..<wheel.count).map { _ in
            Piece(
                angle: random.next() * 2 * .pi,
                radius: near + (far - near) * CGFloat(random.next()),
                size: wheel.sizes.lowerBound + (wheel.sizes.upperBound - wheel.sizes.lowerBound) * CGFloat(random.next()),
                spin: 20 + random.next() * 20,
                flutter: random.next(),
                tint: Int(random.next() * 8)
            )
        }
        return ZStack(alignment: .topLeading) {
            ForEach(pieces.indices, id: \.self) { index in
                let piece = pieces[index]
                let angle = piece.angle + turn
                PieceView(piece: piece, season: season, time: time)
                    .opacity(wheel.opacity)
                    .position(
                        x: center.x + cos(angle) * piece.radius,
                        y: center.y + sin(angle) * piece.radius
                    )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

private struct Piece {
    let angle: Double
    let radius: CGFloat
    let size: CGFloat
    /// Seconds per turn of its own.
    let spin: TimeInterval
    /// 0…1, picks the flutter's speed.
    let flutter: Double
    let tint: Int
}

private struct PieceView: View {
    let piece: Piece
    let season: Season
    let time: TimeInterval

    var body: some View {
        season.piece(size: piece.size, tint: piece.tint)
            // Never wrapped, so each glide turns the same way.
            .rotationEffect(.radians(season.spins ? time / piece.spin * 2 * .pi : 0))
            .offset(flutterOffset)
    }

    /// Where the piece is on its small flutter circle.
    private var flutterOffset: CGSize {
        guard let flutter = season.flutter else { return .zero }
        let period = flutter.period.lowerBound + (flutter.period.upperBound - flutter.period.lowerBound) * piece.flutter
        let phase = (time / period).truncatingRemainder(dividingBy: 1) * 2 * .pi
        return CGSize(width: cos(phase) * flutter.radius, height: sin(phase) * flutter.radius)
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

/// The same pieces every time (no flicker between entries).
private struct DriftRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    /// 0…1
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}
