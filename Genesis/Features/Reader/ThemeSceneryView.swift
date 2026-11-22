import SwiftUI
import UIKit

/// The material themes' surroundings, drawn over the reader at its edges
/// (never over the text: `SceneryArea`): Hearth's fire-glow and embers,
/// Leather Bound's cover, Cedar's wood and lamplight, Highlands' ridges and
/// mist, Storm on Galilee's sky, rain and water, and Ironstone's inset
/// tablet with brass corners. It never takes a tap and is hidden from
/// VoiceOver. Only Hearth, Highlands and Storm move, under the seasonal
/// rules: with the Touches switch on, 30 frames a second, the composed
/// still with Reduce Motion or in Low Power Mode.
struct ThemeSceneryView: View {
    let scenery: ThemeScenery
    let area: SceneryArea
    /// The person's Touches switch (`ReaderPreferences.seasonalEffects`).
    var animates = true
    var reduceMotion = false

    /// The moment shown when it holds still.
    static let stillMoment: TimeInterval = 7.3

    @State private var start = Date.now
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        let scenery = scenery
        let area = area
        let images = SceneryImages(
            wood: scenery == .cedar ? Image(uiImage: MaterialTiles.cedar) : nil,
            leather: scenery == .leatherBound ? Image(uiImage: MaterialTiles.leather) : nil
        )
        Group {
            if scenery.moves && animates && !reduceMotion && !lowPower {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    Canvas { canvas, _ in
                        let time = context.date.timeIntervalSince(start)
                        SceneryPainter.draw(scenery, in: canvas, area: area, images: images, time: time, moving: true)
                    }
                }
            } else {
                Canvas { canvas, _ in
                    SceneryPainter.draw(scenery, in: canvas, area: area, images: images, time: Self.stillMoment, moving: false)
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

/// Material pictures, resolved on the main actor before drawing.
struct SceneryImages {
    var wood: Image?
    var leather: Image?
}

/// The drawing itself, for each scenery. `moving` is false for the still.
enum SceneryPainter {
    static func draw(_ scenery: ThemeScenery, in canvas: GraphicsContext, area: SceneryArea, images: SceneryImages, time: TimeInterval, moving: Bool) {
        let t = CGFloat(time)
        switch scenery {
        case .hearth: Hearth.draw(in: canvas, area: area, time: t, moving: moving)
        case .leatherBound: LeatherCover.draw(in: canvas, area: area, leather: images.leather)
        case .cedar: CedarDesk.draw(in: canvas, area: area, wood: images.wood)
        case .highlands: Highlands.draw(in: canvas, area: area, time: t)
        case .galileeStorm: Storm.draw(in: canvas, area: area, time: t, moving: moving)
        case .ironstone: Tablet.draw(in: canvas, area: area)
        }
    }

    static func color(_ hex: UInt32) -> Color { Color(uiColor: UIColor(hex: hex)) }

    static func ellipse(_ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2))
    }

    /// A soft round glow.
    static func glow(_ canvas: GraphicsContext, at center: CGPoint, radius: CGFloat, color: Color, opacity: CGFloat) {
        canvas.fill(ellipse(center, radius, radius), with: .radialGradient(
            Gradient(colors: [color.opacity(opacity), color.opacity(0)]), center: center, startRadius: 0, endRadius: radius))
    }
}

// MARK: - Hearth

/// A warm glow along the foot of the page, breathing like a fire, and a
/// dozen embers rising from it that die out low on the page. The still
/// keeps the glow.
private enum Hearth {
    static let amber = SceneryPainter.color(0xC8743A)
    static let core = SceneryPainter.color(0xFFD696)
    static let spark = SceneryPainter.color(0xE6783A)

    static func draw(in canvas: GraphicsContext, area: SceneryArea, time t: CGFloat, moving: Bool) {
        let page = area.size
        // Below the last line (a little over it while text scrolls).
        let height = max(area.bottom, 30) + 12
        let breathe: CGFloat = moving ? 0.9 + 0.1 * sin(t * 1.7) * sin(t * 0.63 + 1) : 1
        let rect = CGRect(x: 0, y: page.height - height, width: page.width, height: height)
        canvas.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [
                .init(color: amber.opacity(0), location: 0),
                .init(color: amber.opacity(0.1 * breathe), location: 0.55),
                .init(color: amber.opacity(0.3 * breathe), location: 1),
            ]),
            startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        guard moving else { return }
        for (index, ember) in HearthEmbers.embers.enumerated() {
            var state = HearthEmbers.state(of: ember, index: index, at: t, page: page)
            // Two in three rise in the side margins; the rest glow only
            // below the text. None crosses the words.
            if index % 3 != 0 {
                let leftSide = index.isMultiple(of: 2)
                let margin = leftSide ? area.left : area.right
                let within = margin * (0.2 + 0.6 * ember.x)
                state = HearthEmbers.State(point: CGPoint(x: leftSide ? within : page.width - within, y: state.point.y),
                                           radius: state.radius, opacity: state.opacity)
            }
            guard !area.isInText(state.point) else { continue }
            let r = state.radius * 4
            canvas.fill(SceneryPainter.ellipse(state.point, r, r), with: .radialGradient(
                Gradient(stops: [
                    .init(color: core.opacity(state.opacity), location: 0),
                    .init(color: spark.opacity(state.opacity * 0.7), location: 0.3),
                    .init(color: spark.opacity(0), location: 1),
                ]), center: state.point, startRadius: 0, endRadius: r))
        }
    }
}

// MARK: - Leather Bound

/// The page set in an oxblood leather cover: fine grain, one tooled gold
/// line, a soft shadow at the gutter and a glimpse of the paper stack at
/// the outer edges. Still.
private enum LeatherCover {
    static let oxblood = SceneryPainter.color(0x522622)
    static let gold = SceneryPainter.color(0xA88954)
    static let stack = SceneryPainter.color(0xDCC8A8)

    static func draw(in canvas: GraphicsContext, area: SceneryArea, leather: Image?) {
        let page = area.size
        let border = area.sideWidth(maximum: 36)
        let inner = CGRect(x: border, y: border, width: page.width - border * 2, height: page.height - border * 2)
        guard inner.width > 0, inner.height > 0 else { return }
        var cover = Path(CGRect(origin: .zero, size: page))
        cover.addPath(Path(roundedRect: inner, cornerRadius: 5))
        let fill: GraphicsContext.Shading = if let leather { .tiledImage(leather, scale: 0.5) } else { .color(oxblood) }
        canvas.fill(cover, with: fill, style: FillStyle(eoFill: true))
        // Tooling: one restrained line in worn gold, set into the leather.
        if border >= 8 {
            let inset = border * 0.45
            let line = CGRect(x: inset, y: inset, width: page.width - inset * 2, height: page.height - inset * 2)
            canvas.stroke(Path(roundedRect: line, cornerRadius: 3), with: .color(gold.opacity(0.75)), lineWidth: 0.8)
        }
        // The edge of the page casts a little shadow onto the leather.
        canvas.stroke(Path(roundedRect: inner.insetBy(dx: -0.75, dy: -0.75), cornerRadius: 5.5), with: .color(.black.opacity(0.3)), lineWidth: 1.5)

        // The gutter: at the spine side of one page, or in the middle of two.
        let gutterWidth = min(18, max(10, border * 1.4))
        if area.spread {
            let mid = page.width / 2
            for side: CGFloat in [-1, 1] {
                let rect = CGRect(x: side < 0 ? mid - gutterWidth * 1.4 : mid, y: inner.minY, width: gutterWidth * 1.4, height: inner.height)
                canvas.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [.black.opacity(0.14), .black.opacity(0)]),
                    startPoint: CGPoint(x: mid, y: 0), endPoint: CGPoint(x: mid + side * gutterWidth * 1.4, y: 0)))
            }
            stackLines(canvas, x: inner.minX, inner: inner, direction: 1)
            stackLines(canvas, x: inner.maxX, inner: inner, direction: -1)
        } else {
            let rect = CGRect(x: inner.minX, y: inner.minY, width: gutterWidth, height: inner.height)
            canvas.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [.black.opacity(0.1), .black.opacity(0)]),
                startPoint: CGPoint(x: inner.minX, y: 0), endPoint: CGPoint(x: inner.minX + gutterWidth, y: 0)))
            stackLines(canvas, x: inner.maxX, inner: inner, direction: -1)
        }
        // The stack shows along the foot too.
        var foot = Path()
        for k in 1...2 {
            let y = inner.maxY - CGFloat(k) * 1.5
            foot.move(to: CGPoint(x: inner.minX + 8, y: y))
            foot.addLine(to: CGPoint(x: inner.maxX - 8, y: y))
        }
        canvas.stroke(foot, with: .color(stack.opacity(0.9)), lineWidth: 0.6)
    }

    /// Three thin page edges just inside the cover, at an outer edge.
    static func stackLines(_ canvas: GraphicsContext, x: CGFloat, inner: CGRect, direction: CGFloat) {
        var path = Path()
        for k in 1...3 {
            let lineX = x + direction * CGFloat(k) * 1.5
            path.move(to: CGPoint(x: lineX, y: inner.minY + 6))
            path.addLine(to: CGPoint(x: lineX, y: inner.maxY - 6))
        }
        canvas.stroke(path, with: .color(stack.opacity(0.9)), lineWidth: 0.6)
    }
}

// MARK: - Cedar

/// Parchment on a cedar desk: narrow strips of fine, long-grained wood at
/// the sides (more desk on wide layouts), a warm lamp highlight along the
/// seam and a faint pool of lamplight on the page. Still.
private enum CedarDesk {
    static let cedar = SceneryPainter.color(0x795239)
    static let lamp = SceneryPainter.color(0xFFD9A0)

    static func draw(in canvas: GraphicsContext, area: SceneryArea, wood: Image?) {
        let page = area.size
        let width = area.sideWidth(maximum: 56)
        // Lamplight from above, to the right.
        SceneryPainter.glow(canvas, at: CGPoint(x: page.width * 0.78, y: -40), radius: max(page.width, page.height) * 0.75, color: lamp, opacity: 0.13)
        for side in [false, true] {
            let x = side ? page.width - width : 0
            let strip = CGRect(x: x, y: 0, width: width, height: page.height)
            let fill: GraphicsContext.Shading = if let wood { .tiledImage(wood, origin: CGPoint(x: x, y: 0), scale: 0.5) } else { .color(cedar) }
            canvas.fill(Path(strip), with: fill)
            // The paper's edge throws a slim shadow onto the wood…
            let seam = side ? strip.minX : strip.maxX
            let shadow = CGRect(x: side ? seam : seam - 3, y: 0, width: 3, height: page.height)
            canvas.fill(Path(shadow), with: .linearGradient(
                Gradient(colors: [.black.opacity(0.28), .black.opacity(0)]),
                startPoint: CGPoint(x: seam, y: 0), endPoint: CGPoint(x: side ? seam + 3 : seam - 3, y: 0)))
            // …and the lamp catches the paper along the seam, brightest at the top.
            let highlight = CGRect(x: side ? seam - 2 : seam, y: 0, width: 2, height: page.height)
            canvas.fill(Path(highlight), with: .linearGradient(
                Gradient(colors: [lamp.opacity(0.55), lamp.opacity(0.08)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: page.height)))
        }
    }
}

// MARK: - Highlands

/// Low pine ridges below the page number, in four soft layers from far to
/// near, with mist drifting slowly between them. They fold away when the
/// foot has no room.
private enum Highlands {
    static let layers: [(color: UInt32, base: CGFloat, height: CGFloat, seed: UInt64)] = [
        (0xCED5CC, 0.55, 0.42, 5),
        (0xB6C1B7, 0.42, 0.42, 6),
        (0x98A79B, 0.22, 0.45, 7),
        (0x7A8B7F, 0.0, 0.5, 8),
    ]
    static let mist = SceneryPainter.color(0xF0F2EE)

    static func draw(in canvas: GraphicsContext, area: SceneryArea, time t: CGFloat) {
        let band = area.footDecoration
        guard band > 0 else { return }
        let page = area.size
        for (index, layer) in layers.enumerated() {
            let baseY = page.height - band * layer.base
            canvas.fill(ridge(width: page.width, baseY: baseY, bottom: page.height, height: band * layer.height, seed: layer.seed, scale: 0.8 + CGFloat(index) * 0.2),
                        with: .color(SceneryPainter.color(layer.color)))
            // Mist after the second and third ridges.
            if index == 1 || index == 2 {
                let speed: CGFloat = index == 1 ? 3 : 5
                let travel = page.width * 1.8
                let x = (t * speed + CGFloat(index) * page.width * 0.6).truncatingRemainder(dividingBy: travel) - page.width * 0.4
                for copy in [x, x - travel] where copy > -page.width && copy < page.width * 1.4 {
                    let center = CGPoint(x: copy + page.width * 0.4, y: baseY - band * 0.08)
                    canvas.fill(SceneryPainter.ellipse(center, page.width * 0.55, band * 0.22), with: .radialGradient(
                        Gradient(colors: [mist.opacity(0.6), mist.opacity(0)]), center: center, startRadius: 0, endRadius: page.width * 0.55))
                }
            }
        }
    }

    /// A row of pines: soft triangles of irregular width and height.
    static func ridge(width: CGFloat, baseY: CGFloat, bottom: CGFloat, height: CGFloat, seed: UInt64, scale: CGFloat) -> Path {
        var random = SeededRandom(seed: seed)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: bottom))
        path.addLine(to: CGPoint(x: 0, y: baseY))
        var x: CGFloat = -4
        while x < width + 4 {
            let w = (7 + random.next() * 6) * scale
            let h = height * (0.45 + 0.55 * random.next())
            path.addLine(to: CGPoint(x: x + w / 2, y: baseY - h))
            path.addLine(to: CGPoint(x: x + w, y: baseY - h * 0.2 + random.next() * 2))
            x += w
        }
        path.addLine(to: CGPoint(x: width, y: bottom))
        path.closeSubpath()
        return path
    }
}

// MARK: - Storm on Galilee

/// A clouded sky above the running head, muted swells below the page
/// number, fine slanting rain only at the outer edges (never across the
/// text), and now and then the horizon brightens and fades (`StormFlash`).
/// The still keeps the clouds and calm water.
private enum Storm {
    static let cloud = SceneryPainter.color(0x3A4A5C)
    static let light = SceneryPainter.color(0xB8C8DA)
    static let rain = SceneryPainter.color(0xBECDDC)
    static let water: [UInt32] = [0x24323F, 0x2B3B4A, 0x33465A]

    struct Drop: Sendable {
        let x, offset, speed, length: CGFloat
        let atEdge: Bool
    }

    static let drops: [Drop] = {
        var random = SeededRandom(seed: 31)
        return (0..<60).map { _ in
            Drop(x: random.next(), offset: random.next(), speed: 380 + random.next() * 140,
                 length: 9 + random.next() * 7, atEdge: random.next() < 0.75)
        }
    }()

    static func draw(in canvas: GraphicsContext, area: SceneryArea, time t: CGFloat, moving: Bool) {
        let page = area.size
        let flash = moving ? CGFloat(StormFlash.intensity(at: Double(t))) : 0
        // Clouds over the top band.
        let top = max(area.topBand, 24)
        for (index, x) in [0.15, 0.55, 0.9].enumerated() {
            let center = CGPoint(x: page.width * x, y: top * 0.2)
            SceneryPainter.glow(canvas, at: center, radius: page.width * (0.35 + 0.05 * CGFloat(index)), color: cloud, opacity: 0.45)
        }
        if flash > 0 {
            SceneryPainter.glow(canvas, at: CGPoint(x: page.width * 0.75, y: 0), radius: page.width * 0.6, color: light, opacity: 0.12 * flash)
        }

        // Water at the foot, with the horizon's glow along its top.
        let band = area.footDecoration
        if band > 0 {
            let horizon = page.height - band * 0.8
            if flash > 0 {
                let center = CGPoint(x: page.width * 0.6, y: horizon)
                canvas.fill(SceneryPainter.ellipse(center, page.width * 0.7, band * 0.6), with: .radialGradient(
                    Gradient(colors: [light.opacity(0.35 * flash), light.opacity(0)]), center: center, startRadius: 0, endRadius: page.width * 0.7))
            }
            for (k, hex) in water.enumerated() {
                let layer = CGFloat(k)
                let phase = moving ? t * (0.25 + 0.1 * layer) : 0
                var path = Path()
                path.move(to: CGPoint(x: 0, y: page.height))
                var x: CGFloat = 0
                while x <= page.width + 4 {
                    let y = horizon + layer * band * 0.25
                        + sin(x / (26 - layer * 4) + layer * 2 + phase) * (4 - layer)
                        + sin(x / 9 + layer + phase * 1.6) * 1.2
                    path.addLine(to: CGPoint(x: x, y: y))
                    x += 4
                }
                path.addLine(to: CGPoint(x: page.width, y: page.height))
                path.closeSubpath()
                canvas.fill(path, with: .color(SceneryPainter.color(hex).opacity(0.75 + 0.08 * layer)))
            }
        }

        // Rain: only where there's no text.
        guard moving else { return }
        var streaks = Path()
        let travel = page.height + 40
        for drop in drops {
            let x: CGFloat
            if drop.atEdge {
                // Into the left or right margin.
                let leftSide = drop.x < 0.5
                let margin = leftSide ? area.left : area.right
                let within = (leftSide ? drop.x : drop.x - 0.5) * 2 * margin
                x = leftSide ? within : page.width - within
            } else {
                x = drop.x * page.width
            }
            let y = (drop.offset * travel + t * drop.speed).truncatingRemainder(dividingBy: travel) - 20
            let start = CGPoint(x: x, y: y)
            let end = CGPoint(x: x - drop.length * 0.28, y: y + drop.length)
            guard !area.isInText(start), !area.isInText(end) else { continue }
            streaks.move(to: start)
            streaks.addLine(to: end)
        }
        canvas.stroke(streaks, with: .color(rain.opacity(0.28)), lineWidth: 0.8)
    }
}

// MARK: - Ironstone

/// Dark stone with the page set into it like a tablet: a slightly darker
/// surround, a recessed edge (dark above, a faint light below) and small
/// brass brackets at the four corners. Still; the stone's grain is the
/// paper texture's.
private enum Tablet {
    static let brass = SceneryPainter.color(0xB79B63)

    static func draw(in canvas: GraphicsContext, area: SceneryArea) {
        let page = area.size
        let inset = area.sideWidth(maximum: 28)
        // Clear of the screen's rounded corners: the tablet starts in the
        // status bar's band and ends in the home indicator's.
        let top = max(inset, area.topBand * 0.75)
        let bottom = max(inset, area.footBand * 0.75)
        let tablet = CGRect(x: inset, y: top, width: page.width - inset * 2, height: page.height - top - bottom)
        guard tablet.width > 0, tablet.height > 0 else { return }
        var surround = Path(CGRect(origin: .zero, size: page))
        surround.addPath(Path(roundedRect: tablet, cornerRadius: 8))
        canvas.fill(surround, with: .color(.black.opacity(0.14)), style: FillStyle(eoFill: true))
        // Recessed: the upper edge in shadow, the lower edge catching light.
        canvas.stroke(Path(roundedRect: tablet.offsetBy(dx: 0.5, dy: 0.5), cornerRadius: 8), with: .color(.black.opacity(0.45)), lineWidth: 1)
        canvas.stroke(Path(roundedRect: tablet.offsetBy(dx: -0.5, dy: -0.5), cornerRadius: 8), with: .color(.white.opacity(0.06)), lineWidth: 1)
        // Brass brackets.
        let arm = min(22, max(10, inset * 1.6))
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: tablet.minX + 4, y: tablet.minY + 4), 1, 1),
            (CGPoint(x: tablet.maxX - 4, y: tablet.minY + 4), -1, 1),
            (CGPoint(x: tablet.minX + 4, y: tablet.maxY - 4), 1, -1),
            (CGPoint(x: tablet.maxX - 4, y: tablet.maxY - 4), -1, -1),
        ]
        var brackets = Path()
        var rivets = Path()
        for (corner, sx, sy) in corners {
            brackets.move(to: CGPoint(x: corner.x, y: corner.y + sy * arm))
            brackets.addLine(to: corner)
            brackets.addLine(to: CGPoint(x: corner.x + sx * arm, y: corner.y))
            rivets.addPath(SceneryPainter.ellipse(CGPoint(x: corner.x + sx * 4, y: corner.y + sy * 4), 1.4, 1.4))
        }
        canvas.stroke(brackets, with: .color(brass.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
        canvas.fill(rivets, with: .color(brass.opacity(0.8)))
    }
}

// MARK: - Material pictures

/// Leather and cedar, drawn once (no image files) as seamless tiles at 2×.
@MainActor
enum MaterialTiles {
    /// Fine pebbled oxblood leather.
    static let leather: UIImage = {
        let side: CGFloat = 256
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            UIColor(hex: 0x522622).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
            var random = SeededRandom(seed: 19)
            for _ in 0..<2600 {
                let point = CGPoint(x: random.next() * side, y: random.next() * side)
                let radius = 0.8 + random.next() * 1.6
                let dark = random.next() < 0.55
                let color = dark ? UIColor(white: 0, alpha: 0.12 + random.next() * 0.12) : UIColor(red: 0.55, green: 0.24, blue: 0.2, alpha: 0.12 + random.next() * 0.1)
                color.setFill()
                for dx in [-side, 0, side] {
                    for dy in [-side, 0, side] {
                        cg.fillEllipse(in: CGRect(x: point.x + dx - radius, y: point.y + dy - radius, width: radius * 2, height: radius * 2))
                    }
                }
            }
        }
    }()

    /// Matte cedar with fine, long grain running down the strip.
    static let cedar: UIImage = {
        let size = CGSize(width: 128, height: 1024)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colors = [UIColor(hex: 0x6E4526).cgColor, UIColor(hex: 0x86583A).cgColor, UIColor(hex: 0x6A4224).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
            }
            var random = SeededRandom(seed: 4)
            cg.setLineCap(.round)
            for line in 0..<34 {
                let x0 = random.next() * size.width
                let dark = random.next() < 0.6
                let color = dark ? UIColor(red: 0.16, green: 0.09, blue: 0.04, alpha: 0.18 + random.next() * 0.2) : UIColor(red: 0.67, green: 0.47, blue: 0.3, alpha: 0.15 + random.next() * 0.2)
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(0.6 + random.next() * 1.6)
                // Waves that repeat exactly over the tile's height, so it tiles.
                let waves = CGFloat(1 + line % 3)
                let amplitude = 1.5 + random.next() * 3
                let phase = random.next() * .pi * 2
                cg.move(to: CGPoint(x: x0 + sin(phase) * amplitude, y: 0))
                var y: CGFloat = 8
                while y <= size.height {
                    cg.addLine(to: CGPoint(x: x0 + sin(y / size.height * .pi * 2 * waves + phase) * amplitude, y: y))
                    y += 8
                }
                cg.strokePath()
            }
        }
    }()
}
