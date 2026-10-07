import UIKit

/// The textured paper behind the Premium themes: a faint grain with a few
/// long fibres, like good book paper. It's drawn once per colour (no image
/// files) and repeats seamlessly; it sits behind the text, so contrast and
/// legibility are unchanged.
@MainActor
enum PaperTexture {
    private static var cache: [UInt32: UIColor] = [:]
    private static var tileCache: [UInt32: UIImage] = [:]
    private static let tileSize: CGFloat = 256
    /// Starlight repeats over a wider tile, so its stars don't form a
    /// visible pattern.
    private static let starTileSize: CGFloat = 640

    /// The page colour for a theme: textured paper for Premium themes, the
    /// plain colour otherwise.
    static func pageColor(for theme: ReaderTheme) -> UIColor {
        let palette = theme.palette
        guard theme.hasPaperTexture else { return palette.uiBackground }
        if let cached = cache[palette.backgroundHex] { return cached }
        let color = UIColor(patternImage: render(base: palette.uiBackground, dark: theme.isDark, stars: theme.hasStars))
        cache[palette.backgroundHex] = color
        return color
    }

    /// One tile of a theme's paper, for drawing in SwiftUI (verse images).
    static func tile(for theme: ReaderTheme) -> UIImage {
        let key = theme.palette.backgroundHex
        if let cached = tileCache[key] { return cached }
        let image = render(base: theme.palette.uiBackground, dark: theme.isDark, stars: theme.hasStars)
        tileCache[key] = image
        return image
    }

    private static func render(base: UIColor, dark: Bool, stars: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let side = stars ? starTileSize : tileSize
        let size = CGSize(width: side, height: side)
        // The same density of grain whatever the tile's size.
        let area = (side * side) / (tileSize * tileSize)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            base.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            var random = SeededRandom(seed: 7)
            // Light specks on dark paper, dark specks on light paper.
            let ink: (CGFloat) -> UIColor = { alpha in
                dark ? UIColor(white: 1, alpha: alpha) : UIColor(red: 0.35, green: 0.27, blue: 0.16, alpha: alpha)
            }
            let light = UIColor(white: 1, alpha: dark ? 0.015 : 0.05)

            // Fine grain.
            for _ in 0..<Int(5200 * area) {
                let point = CGPoint(x: random.next() * side, y: random.next() * side)
                let radius = 0.35 + random.next() * 0.55
                let color = random.next() < 0.6 ? ink(0.035 + random.next() * 0.045) : light
                drawTiled(cg, around: point, side: side) { origin in
                    color.setFill()
                    cg.fillEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
                }
            }
            // A few soft blotches, so the paper isn't perfectly even.
            for _ in 0..<Int(14 * area) {
                let point = CGPoint(x: random.next() * side, y: random.next() * side)
                let radius = 18 + random.next() * 40
                let color = ink(0.012 + random.next() * 0.015)
                drawTiled(cg, around: point, side: side) { origin in
                    color.setFill()
                    cg.fillEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 1.4))
                }
            }
            // Fibres: short, thin curved strokes.
            cg.setLineCap(.round)
            for _ in 0..<Int(70 * area) {
                let start = CGPoint(x: random.next() * side, y: random.next() * side)
                let angle = random.next() * .pi * 2
                let length = 6 + random.next() * 18
                let bend = (random.next() - 0.5) * 6
                let color = ink(0.04 + random.next() * 0.05)
                let width = 0.3 + random.next() * 0.4
                drawTiled(cg, around: start, side: side) { origin in
                    let end = CGPoint(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length)
                    let control = CGPoint(x: (origin.x + end.x) / 2 - sin(angle) * bend, y: (origin.y + end.y) / 2 + cos(angle) * bend)
                    cg.setStrokeColor(color.cgColor)
                    cg.setLineWidth(width)
                    cg.move(to: origin)
                    cg.addQuadCurve(to: end, control: control)
                    cg.strokePath()
                }
            }
            if stars { drawStars(cg, side: side) }
        }
    }

    /// Starlight: a sparse field of tiny, faint stars, a few with a soft
    /// glow. Muted and small, so the text in front stays easy to read.
    private static func drawStars(_ cg: CGContext, side: CGFloat) {
        var random = SeededRandom(seed: 29)
        let tints = [UIColor(hex: 0xDCE3F0), UIColor(hex: 0xE8DFC8), UIColor(hex: 0xC9D3E6)]
        for index in 0..<46 {
            let point = CGPoint(x: random.next() * side, y: random.next() * side)
            let bright = random.next() < 0.15
            let radius = bright ? 0.9 + random.next() * 0.5 : 0.4 + random.next() * 0.45
            let alpha = bright ? 0.28 + random.next() * 0.1 : 0.12 + random.next() * 0.12
            let tint = tints[index % tints.count]
            drawTiled(cg, around: point, side: side) { origin in
                if bright {
                    let glow = radius * 4
                    tint.withAlphaComponent(alpha * 0.18).setFill()
                    cg.fillEllipse(in: CGRect(x: origin.x - glow, y: origin.y - glow, width: glow * 2, height: glow * 2))
                }
                tint.withAlphaComponent(alpha).setFill()
                cg.fillEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
            }
        }
    }

    /// Draws at a point and at its copies across the tile's edges, so the
    /// texture repeats without seams.
    private static func drawTiled(_ cg: CGContext, around point: CGPoint, side: CGFloat, draw: (CGPoint) -> Void) {
        for dx in [-side, 0, side] {
            for dy in [-side, 0, side] {
                let origin = CGPoint(x: point.x + dx, y: point.y + dy)
                // Only copies that can reach into the tile.
                guard origin.x > -60, origin.x < side + 60, origin.y > -60, origin.y < side + 60 else { continue }
                draw(origin)
            }
        }
    }
}

/// A small deterministic random number generator, so the paper (and the
/// seasonal effects) look the same every time.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    /// A number in 0..<1.
    mutating func next() -> CGFloat {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let value = state &* 0x2545_F491_4F6C_DD1D
        return CGFloat(value >> 11) / CGFloat(1 << 53)
    }
}
