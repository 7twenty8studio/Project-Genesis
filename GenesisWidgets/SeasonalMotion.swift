import SwiftUI
import WidgetKit

// The seasons' touches, drifting in the verse widget: maple, oak and birch
// leaves in autumn, snow (crystals up close) in winter, petals and blossoms
// in spring, warm motes of light (and the butterfly) in summer, turning
// stars (and shooting stars) at night. Widgets can't
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
//
// Light on purpose: WidgetKit renders every entry of the hour ahead of time
// within a small memory and time budget, and a widget over it shows only its
// grey placeholder (autumn's 68 detailed leaves, each with its own shadow,
// went over it). So only the pieces on or near the widget are drawn
// (`DriftCull`: most of each wheel is off it), leaf outlines are light
// (`SeasonShapes.lightLeaf`), and nothing has its own shadow or blur (one
// shadow for the whole layer instead).

enum SeasonalDrift {
    /// Seconds of the reader's drift that one minute of the widget moves on.
    static let secondsPerStep: TimeInterval = 4
    /// One step a minute, for the next hour (the timeline then reloads).
    static let steps = 60

    static func moves(_ style: WidgetArtStyle) -> Bool {
        DriftSeason(style) != nil
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
        if !reduceMotion, let season = DriftSeason(style), ClockHandMotion.isAvailable {
            // Turning all the time, like the Clock widget's hands.
            GeometryReader { proxy in
                let size = proxy.size
                ZStack(alignment: .topLeading) {
                    ForEach(season.wheels.indices, id: \.self) { index in
                        ClockWheelView(wheel: season.wheels[index], season: season, size: size, seed: UInt64(index + 1) * 7919)
                    }
                    ForEach(season.flyers.indices, id: \.self) { index in
                        FlyerView(flyer: season.flyers[index], size: size)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
                .mask(DriftMask(season: season))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else if !reduceMotion, let season = DriftSeason(style) {
            GeometryReader { proxy in
                let size = proxy.size
                let time = SeasonalDrift.time(at: date)
                ZStack(alignment: .topLeading) {
                    ForEach(season.wheels.indices, id: \.self) { index in
                        WheelView(wheel: season.wheels[index], season: season, size: size, seed: UInt64(index + 1) * 7919, time: time)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                // One soft shadow for the whole layer, never one per piece.
                .compositingGroup()
                .shadow(color: .black.opacity(DriftSeason(style)?.casts == true ? 0.12 : 0), radius: 1, y: 1)
                // Each minute's step glides in (widgets allow up to two seconds).
                .animation(.easeInOut(duration: 2), value: date)
                .clipped()
                .mask(DriftMask(season: season))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Seasons

private enum DriftSeason {
    case autumn, winter, spring, summer, night, hearth

    init?(_ style: WidgetArtStyle) {
        switch style {
        case .autumn: self = .autumn
        case .winter: self = .winter
        case .spring: self = .spring
        case .summer: self = .summer
        case .night: self = .night
        case .hearth: self = .hearth
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
        /// Where it turns about, in shares of the widget (above and left
        /// unless set), and how far its pieces reach, in widget widths
        /// (corner to corner unless set).
        var center: UnitPoint? = nil
        var reach: ClosedRange<CGFloat>? = nil
        /// Embers rise: their wheel turns the other way.
        var counterClockwise = false
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
             // The near ones are crystals, big enough to see their arms.
             Wheel(count: 10, period: 61, sizes: 12...16, opacity: 1)]
        case .spring:
            [Wheel(count: 38, period: 200, sizes: 5...7, opacity: 0.65),
             Wheel(count: 30, period: 140, sizes: 8...11, opacity: 0.9)]
        case .summer:
            [Wheel(count: 40, period: 260, sizes: 3...6, opacity: 0.6),
             Wheel(count: 22, period: 190, sizes: 6...10, opacity: 0.45)]
        case .night:
            // The sky turning slowly; the brighter ones glint.
            [Wheel(count: 44, period: 900, sizes: 1.2...2, opacity: 0.8),
             Wheel(count: 16, period: 700, sizes: 4...6, opacity: 0.95)]
        case .hearth:
            // Embers rising from the foot: a wheel turning the other way
            // about a point off the left, so its right side climbs (and
            // leans a little right). Only a slice of it crosses the widget,
            // hence so many (each is a tiny glow).
            [Wheel(count: 110, period: 240, sizes: 1.5...2.6, opacity: 0.9,
                   center: UnitPoint(x: -0.6, y: 0.95), reach: 0.62...1.55, counterClockwise: true),
             Wheel(count: 50, period: 170, sizes: 2.6...3.8, opacity: 0.75,
                   center: UnitPoint(x: -0.6, y: 0.95), reach: 0.62...1.55, counterClockwise: true)]
        }
    }

    /// Leaves and petals cast a faint shadow (the whole layer's, once).
    var casts: Bool { self == .autumn || self == .spring }

    /// Flutter on a small circle (radius, seconds per loop), none for snow and light.
    var flutter: (radius: CGFloat, period: ClosedRange<Double>)? {
        switch self {
        case .autumn: (5, 15...25)
        case .spring: (4, 12...20)
        case .winter, .summer, .night, .hearth: nil
        }
    }

    var spins: Bool { self != .summer && self != .hearth }

    /// Seconds per turn of a piece's own spin, from its 20–40: the night's
    /// glints turn fast, so the stars seem to twinkle.
    func spinPeriod(_ spin: TimeInterval) -> TimeInterval {
        self == .night ? spin * 0.15 : spin
    }

    /// What crosses the widget now and then (only while it turns with the
    /// clock): shooting stars at night, the butterfly in summer.
    var flyers: [Flyer] {
        switch self {
        case .night:
            // About 500 pt a second, one every 12 or 17 seconds.
            [Flyer(kind: .shootingStar, radius: 950, period: 12, angle: .pi / 2 - 0.5, target: UnitPoint(x: 0.5, y: 0.3)),
             Flyer(kind: .shootingStar, radius: 1150, period: 17, angle: .pi / 2 - 0.35, target: UnitPoint(x: 0.7, y: 0.18))]
        case .summer:
            // Low across the widget, left to right, dipping a little at
            // each side: about 12 seconds a crossing. Five round the wheel,
            // so one sets off every 15 seconds (owner, 24 November 2026).
            [Flyer(kind: .butterfly, radius: 420, period: 75, angle: -.pi / 2, target: UnitPoint(x: 0.5, y: 0.7), count: 5)]
        case .autumn, .winter, .spring, .hearth:
            []
        }
    }

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
            // Maple, oak and birch (`SeasonShapes`), as in the reader.
            let kind = SeasonShapes.LeafKind.mixed(tint)
            let color = colors[tint % colors.count]
            ZStack {
                SeasonShape(unit: SeasonShapes.lightLeaf(kind), span: 1.1).fill(color)
                SeasonShape(unit: SeasonShapes.leafVeins(kind), span: 1.1)
                    .stroke(color.opacity(0.75), lineWidth: max(0.5, size * 0.04))
            }
            .frame(width: size, height: size)
        case .spring:
            let colors: [Color] = [
                Color(red: 0.95, green: 0.76, blue: 0.80),
                Color(red: 0.97, green: 0.86, blue: 0.89),
                Color(red: 1.0, green: 0.97, blue: 0.96),
            ]
            if tint % 4 == 0 {
                // One in four is a whole blossom, as in the reader.
                ZStack {
                    SeasonShape(unit: SeasonShapes.blossomPetals, span: 2.2).fill(colors[tint % colors.count])
                    SeasonShape(unit: SeasonShapes.blossomCentre, span: 2.2).fill(Color(red: 0.79, green: 0.49, blue: 0.56))
                    SeasonShape(unit: SeasonShapes.stamenTips, span: 2.2).fill(Color(red: 0.88, green: 0.70, blue: 0.35))
                }
                .frame(width: size * 1.6, height: size * 1.6)
            } else {
                Ellipse()
                    .fill(colors[tint % colors.count])
                    .frame(width: size * 0.65, height: size)
            }
        case .winter:
            // The reader's flakes: pale blue-grey (#8FA6B8) with white; the
            // near ones are crystals (`SeasonShapes`) with a soft halo.
            let blue = Color(red: 0x8F / 255, green: 0xA6 / 255, blue: 0xB8 / 255)
            if size >= 6 {
                let kind = SeasonShapes.FlakeKind(rawValue: tint % 3) ?? .stellar
                let arms = SeasonShape(unit: SeasonShapes.flakeArms(kind), span: 2)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [blue.opacity(0.3), blue.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.65))
                        .frame(width: size * 1.3, height: size * 1.3)
                    arms.stroke(blue.opacity(0.75), style: StrokeStyle(lineWidth: max(1, size * 0.08), lineCap: .round))
                    if let core = SeasonShapes.flakeCore(kind) {
                        SeasonShape(unit: core, span: 2).fill(blue.opacity(0.75))
                    }
                    arms.stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: max(0.45, size * 0.03), lineCap: .round))
                }
                .frame(width: size, height: size)
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
        case .night:
            // Starlight's colours: blue-white, white and warm.
            let tints: [Color] = [
                Color(red: 0xCD / 255, green: 0xDA / 255, blue: 0xFF / 255),
                Color(red: 0xF4 / 255, green: 0xF1 / 255, blue: 0xE8 / 255),
                Color(red: 0xFF / 255, green: 0xE4 / 255, blue: 0xBA / 255),
            ]
            let color = tints[tint % tints.count]
            if size >= 3 {
                // A bright star: a core and a four-pointed glint that turns.
                ZStack {
                    Capsule().fill(color.opacity(0.7)).frame(width: 0.7, height: size * 2)
                    Capsule().fill(color.opacity(0.7)).frame(width: size * 2, height: 0.7)
                    Circle()
                        .fill(RadialGradient(colors: [color, color.opacity(0.35), color.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.5))
                        .frame(width: size, height: size)
                }
                .frame(width: size * 2, height: size * 2)
            } else {
                Circle().fill(color).frame(width: size, height: size)
            }
        case .hearth:
            // A glowing ember, as at the reader's Hearth.
            let ember = Color(red: 1, green: 0.62, blue: 0.28)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.86, blue: 0.6), ember.opacity(0.7), ember.opacity(0)], center: .center, startRadius: 0, endRadius: size))
                .frame(width: size * 2, height: size * 2)
        case .summer:
            // A soft mote: a gradient rather than a blur (one less pass each).
            let warm = Color(red: 0.98, green: 0.85, blue: 0.55)
            Circle()
                .fill(RadialGradient(colors: [warm, warm.opacity(0.5), warm.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.8))
                .frame(width: size * 1.6, height: size * 1.6)
        }
    }
}

// MARK: - A wheel

private struct WheelView: View {
    let wheel: DriftSeason.Wheel
    let season: DriftSeason
    let size: CGSize
    let seed: UInt64
    /// The drift's clock (`SeasonalDrift.time`).
    let time: TimeInterval

    var body: some View {
        let layout = WheelLayout(wheel: wheel, size: size, seed: seed)
        let center = layout.center
        let pieces = layout.pieces
        // Turning clockwise: across the widget, down and to the left.
        let turn = (time / wheel.period).truncatingRemainder(dividingBy: 1) * 2 * .pi * (wheel.counterClockwise ? -1 : 1)
        // Only the pieces on or near the widget: those just outside are kept
        // so they glide in, rather than appearing, on the next step.
        let step = SeasonalDrift.secondsPerStep / wheel.period * 2 * .pi
        let shown = pieces.indices.compactMap { index -> (index: Int, point: CGPoint)? in
            let piece = pieces[index]
            let angle = piece.angle + turn
            let point = CGPoint(x: center.x + cos(angle) * piece.radius, y: center.y + sin(angle) * piece.radius)
            let margin = DriftCull.margin(radius: piece.radius, step: step, pieceSize: piece.size * 1.6)
            return DriftCull.isNear(point, size: size, margin: margin) ? (index, point) : nil
        }
        return ZStack(alignment: .topLeading) {
            // Identified by the piece, not its place in the list, so each one
            // glides from where it was.
            ForEach(shown, id: \.index) { item in
                PieceView(piece: pieces[item.index], season: season, time: time)
                    .opacity(wheel.opacity)
                    .position(item.point)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// A wheel's centre, reach and pieces: the same every time for a seed, so
/// both ways of turning it (and every entry) agree.
private struct WheelLayout {
    let center: CGPoint
    let far: CGFloat
    let pieces: [Piece]

    init(wheel: DriftSeason.Wheel, size: CGSize, seed: UInt64) {
        // The centre sits above and left of the widget unless the wheel
        // says otherwise; the wheel reaches from just past its nearest
        // corner to beyond its farthest.
        let unit = wheel.center ?? UnitPoint(x: -0.1, y: -0.35)
        let center = CGPoint(x: unit.x * size.width, y: unit.y * size.height)
        let near = wheel.reach.map { $0.lowerBound * size.width } ?? hypot(center.x, center.y) * 0.9
        let far = wheel.reach.map { $0.upperBound * size.width } ?? hypot(size.width - center.x, size.height - center.y) * 1.05
        var random = DriftRandom(seed: seed)
        self.center = center
        self.far = far
        self.pieces = (0..<wheel.count).map { _ in
            Piece(
                angle: random.next() * 2 * .pi,
                radius: near + (far - near) * CGFloat(random.next()),
                size: wheel.sizes.lowerBound + (wheel.sizes.upperBound - wheel.sizes.lowerBound) * CGFloat(random.next()),
                spin: 20 + random.next() * 20,
                flutter: random.next(),
                tint: Int(random.next() * 8)
            )
        }
    }
}

// MARK: - Turning with the clock

/// A whole wheel, drawn once and turned by the clock effect: one turn every
/// `wheel.period` seconds, as fast as the reader's drift. Each piece spins
/// and flutters the same way.
private struct ClockWheelView: View {
    let wheel: DriftSeason.Wheel
    let season: DriftSeason
    let size: CGSize
    let seed: UInt64

    var body: some View {
        let layout = WheelLayout(wheel: wheel, size: size, seed: seed)
        let side = layout.far * 2
        ZStack(alignment: .topLeading) {
            ForEach(layout.pieces.indices, id: \.self) { index in
                let piece = layout.pieces[index]
                ClockPieceView(piece: piece, season: season)
                    .opacity(wheel.opacity)
                    .position(x: layout.far + cos(piece.angle) * piece.radius, y: layout.far + sin(piece.angle) * piece.radius)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
        // Clockwise about its centre (across the widget, down and to the
        // left), or the other way for rising embers.
        .wheelRotation(period: wheel.period, counterClockwise: wheel.counterClockwise)
        // The square's centre on the wheel's centre, above and left.
        .position(layout.center)
    }
}

private struct ClockPieceView: View {
    let piece: Piece
    let season: DriftSeason

    var body: some View {
        if let flutter = season.flutter {
            let period = flutter.period.lowerBound + (flutter.period.upperBound - flutter.period.lowerBound) * piece.flutter
            let box = piece.size * 2 + flutter.radius * 2
            // Off centre in a box that turns: round its small flutter circle.
            spinning
                .offset(y: -flutter.radius)
                .frame(width: box, height: box)
                .clockHandRotation(period: period)
        } else {
            spinning
        }
    }

    @ViewBuilder
    private var spinning: some View {
        if season.spins {
            season.piece(size: piece.size, tint: piece.tint)
                .clockHandRotation(period: season.spinPeriod(piece.spin))
        } else {
            season.piece(size: piece.size, tint: piece.tint)
        }
    }
}

/// Something that crosses the widget once a turn: it rides a wheel so big
/// that only a short arc of it passes over the widget, through `target`
/// (a point in the widget) at `angle` on the wheel, heading clockwise.
private struct Flyer {
    enum Kind { case shootingStar, butterfly }

    let kind: Kind
    let radius: CGFloat
    let period: TimeInterval
    let angle: Double
    let target: UnitPoint
    /// How many ride the wheel, evenly spaced (one every period / count).
    var count = 1
}

private struct FlyerView: View {
    let flyer: Flyer
    let size: CGSize

    var body: some View {
        let r = flyer.radius
        let point = CGPoint(x: flyer.target.x * size.width, y: flyer.target.y * size.height)
        let center = CGPoint(x: point.x - r * cos(flyer.angle), y: point.y - r * sin(flyer.angle))
        ZStack(alignment: .topLeading) {
            ForEach(0..<flyer.count, id: \.self) { index in
                let angle = flyer.angle + Double(index) * 2 * .pi / Double(flyer.count)
                // Butterflies cross at different heights, one after another.
                let reach = r + lane(index)
                item(index)
                    // Drawn heading up; turned to head along the wheel, clockwise.
                    .rotationEffect(.radians(angle + .pi))
                    .position(x: r + reach * cos(angle), y: r + reach * sin(angle))
            }
        }
        .frame(width: r * 2, height: r * 2, alignment: .topLeading)
        .clockHandRotation(period: flyer.period)
        .position(center)
    }

    private func lane(_ index: Int) -> CGFloat {
        guard flyer.kind == .butterfly else { return 0 }
        let lanes: [CGFloat] = [0, -20, 14, -8, 22]
        return lanes[index % lanes.count]
    }

    @ViewBuilder
    private func item(_ index: Int) -> some View {
        switch flyer.kind {
        case .shootingStar:
            // A bright head and a tail fading behind it.
            Capsule()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.97, blue: 0.88), Color(red: 0.98, green: 0.95, blue: 0.82).opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: 1.6, height: 46)
        case .butterfly:
            // A wandering path: a quick bob one way on top of a slower,
            // wider loop the other way (each butterfly at its own pace),
            // so it rises, dips and drifts rather than gliding on a rail.
            // Both circles are undone inside, so it keeps facing ahead.
            let i = Double(index)
            let bob = 1.3 + 0.17 * i
            let loop = 4.6 + 0.9 * i
            WidgetButterfly(flap: 0.85 + 0.06 * i)
                .counterClockHandRotation(period: bob)
                .offset(y: -3)
                .frame(width: 38, height: 38)
                .clockHandRotation(period: bob)
                .clockHandRotation(period: loop)
                .offset(y: -9)
                .frame(width: 60, height: 60)
                .counterClockHandRotation(period: loop)
        }
    }
}

/// Summer's butterfly, as in the reader: warm amber, its wings beating.
private struct WidgetButterfly: View {
    /// Seconds per turn of the beat's clock (two wingbeats a turn).
    let flap: TimeInterval

    var body: some View {
        let upper = Color(red: 0xD9 / 255, green: 0x9A / 255, blue: 0x4E / 255)
        let lower = Color(red: 0xC9 / 255, green: 0x81 / 255, blue: 0x3C / 255)
        let bodyColor = Color(red: 0x6B / 255, green: 0x4A / 255, blue: 0x2E / 255)
        ZStack {
            ForEach([CGFloat(1), -1], id: \.self) { side in
                ZStack {
                    SeasonShape(unit: SeasonShapes.butterflyUpperWing, span: 2).fill(upper)
                    SeasonShape(unit: SeasonShapes.butterflyLowerWing, span: 2).fill(lower)
                }
                .wingBeat(period: flap)
                .scaleEffect(x: side, y: 1)
            }
            SeasonShape(unit: SeasonShapes.butterflyBody, span: 2).fill(bodyColor)
            SeasonShape(unit: SeasonShapes.butterflyAntennae, span: 2).stroke(bodyColor, lineWidth: 0.5)
        }
        .frame(width: 26, height: 26)
        .opacity(0.95)
    }
}

/// WidgetKit's own clock-hand rotation (`_ClockHandRotationEffect`, what the
/// Clock widget's hands use): turning continuously with the system clock,
/// drawn by iOS, with no timeline entries. It's private API, used on the
/// owner's decision (24 November 2026) knowing App Review may object or an
/// iOS update may stop it: `isEnabled` turns it off, and wherever it isn't
/// available the widget falls back to the minute steps. Since Xcode 26.1
/// the underscored modifier does nothing for other apps, so it's built at
/// runtime from its Codable form, as ClockHandKit does (github.com/giljihun/
/// ClockHandKit, MIT License, Copyright (c) 2026 GIL).
enum ClockHandMotion {
    /// The switch: false goes back to the minute steps everywhere.
    static let isEnabled = true

    /// Only in the widget extension (the app's Widget Styles previews keep
    /// the still), and only when WidgetKit still has the effect.
    static let isAvailable: Bool = {
        guard isEnabled, Bundle.main.bundlePath.hasSuffix(".appex") else { return false }
        return effect(period: 60) != nil
    }()

    /// The effect for a period, or nil if WidgetKit no longer offers it.
    static func effect(period: TimeInterval) -> (any ViewModifier)? {
        guard let type = _typeByName("9WidgetKit24_ClockHandRotationEffectV"),
              let decodable = type as? any Decodable.Type,
              let json = try? JSONEncoder().encode(ClockHandPayload(period: period)),
              let decoded = try? JSONDecoder().decode(decodable, from: json)
        else { return nil }
        return decoded as? any ViewModifier
    }
}

/// `_ClockHandRotationEffect`'s Codable form. WidgetKit in the 27 releases
/// requires `honorIdealizedDate`; earlier ones ignore it.
private struct ClockHandPayload: Encodable {
    let period: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case period, timeZone, anchor, honorIdealizedDate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(period, forKey: .period)
        try container.encode(TimeZone.current, forKey: .timeZone)
        // The real time, not the gallery's idealised one.
        try container.encode(false, forKey: .honorIdealizedDate)
        var anchor = container.nestedUnkeyedContainer(forKey: .anchor)
        try anchor.encode(0.5)
        try anchor.encode(0.5)
    }
}

private extension View {
    /// Turns the view about its centre once every `period` seconds, or
    /// leaves it still where the effect isn't available.
    @ViewBuilder
    func clockHandRotation(period: TimeInterval) -> some View {
        if ClockHandMotion.isAvailable, let effect = ClockHandMotion.effect(period: period) {
            applying(effect)
        } else {
            self
        }
    }

    @ViewBuilder
    func wheelRotation(period: TimeInterval, counterClockwise: Bool) -> some View {
        if counterClockwise {
            counterClockHandRotation(period: period)
        } else {
            clockHandRotation(period: period)
        }
    }

    /// The same, turning the other way: mirrored, turned, mirrored back.
    func counterClockHandRotation(period: TimeInterval) -> some View {
        scaleEffect(x: -1, y: 1)
            .clockHandRotation(period: period)
            .scaleEffect(x: -1, y: 1)
    }

    /// A wingbeat from two clock turns: turned back, squeezed sideways,
    /// turned forward again. The squeeze's axis goes round, so the wing
    /// narrows and widens twice a turn, its tip lifting as it narrows
    /// (mirrored for the other wing, so both rise together), like wings
    /// seen from just above. Still where the effect isn't available.
    @ViewBuilder
    func wingBeat(period: TimeInterval) -> some View {
        if ClockHandMotion.isAvailable {
            counterClockHandRotation(period: period)
                .scaleEffect(x: 0.45, y: 1)
                .clockHandRotation(period: period)
        } else {
            self
        }
    }

    func applying<M: ViewModifier>(_ effect: M) -> AnyView {
        AnyView(modifier(effect))
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
    let season: DriftSeason
    let time: TimeInterval

    var body: some View {
        season.piece(size: piece.size, tint: piece.tint)
            // Never wrapped, so each glide turns the same way.
            .rotationEffect(.radians(season.spins ? time / season.spinPeriod(piece.spin) * 2 * .pi : 0))
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

/// Which pieces are worth drawing: those within a step's travel of the
/// widget (plus the flutter and their own size). Pure, so it's tested.
enum DriftCull {
    /// How far outside the widget a piece is still drawn.
    static func margin(radius: CGFloat, step: Double, pieceSize: CGFloat) -> CGFloat {
        radius * CGFloat(step) + pieceSize + 8
    }

    static func isNear(_ point: CGPoint, size: CGSize, margin: CGFloat) -> Bool {
        point.x >= -margin && point.x <= size.width + margin
            && point.y >= -margin && point.y <= size.height + margin
    }
}

/// Where the pieces show: the edges, or for embers the lower part (they
/// fade as they climb, as at the reader's Hearth).
private struct DriftMask: View {
    let season: DriftSeason

    var body: some View {
        if season == .hearth {
            LinearGradient(stops: [
                .init(color: .black.opacity(0), location: 0.05),
                .init(color: .black.opacity(0.55), location: 0.5),
                .init(color: .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        } else {
            EdgeMask()
        }
    }
}

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
