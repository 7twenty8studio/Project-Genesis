import UIKit

/// The textured paper behind the Premium themes: a faint grain with a few
/// long fibres, like good book paper. It's drawn once per colour (no image
/// files) and repeats seamlessly; it sits behind the text, so contrast and
/// legibility are unchanged.
@MainActor
enum PaperTexture {
    private static var cache: [UInt32: UIColor] = [:]
    private static let tile: CGFloat = 256

    /// The page colour for a theme: textured paper for Premium themes, the
    /// plain colour otherwise.
    static func pageColor(for theme: ReaderTheme) -> UIColor {
        let palette = theme.palette
        guard theme.hasPaperTexture else { return palette.uiBackground }
        if let cached = cache[palette.backgroundHex] { return cached }
        let color = UIColor(patternImage: render(base: palette.uiBackground, dark: theme.isDark))
        cache[palette.backgroundHex] = color
        return color
    }

    private static func render(base: UIColor, dark: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let size = CGSize(width: tile, height: tile)
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
            for _ in 0..<5200 {
                let point = CGPoint(x: random.next() * tile, y: random.next() * tile)
                let radius = 0.35 + random.next() * 0.55
                let color = random.next() < 0.6 ? ink(0.035 + random.next() * 0.045) : light
                drawTiled(cg, around: point) { origin in
                    color.setFill()
                    cg.fillEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
                }
            }
            // A few soft blotches, so the paper isn't perfectly even.
            for _ in 0..<14 {
                let point = CGPoint(x: random.next() * tile, y: random.next() * tile)
                let radius = 18 + random.next() * 40
                let color = ink(0.012 + random.next() * 0.015)
                drawTiled(cg, around: point) { origin in
                    color.setFill()
                    cg.fillEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 1.4))
                }
            }
            // Fibres: short, thin curved strokes.
            cg.setLineCap(.round)
            for _ in 0..<70 {
                let start = CGPoint(x: random.next() * tile, y: random.next() * tile)
                let angle = random.next() * .pi * 2
                let length = 6 + random.next() * 18
                let bend = (random.next() - 0.5) * 6
                let color = ink(0.04 + random.next() * 0.05)
                let width = 0.3 + random.next() * 0.4
                drawTiled(cg, around: start) { origin in
                    let end = CGPoint(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length)
                    let control = CGPoint(x: (origin.x + end.x) / 2 - sin(angle) * bend, y: (origin.y + end.y) / 2 + cos(angle) * bend)
                    cg.setStrokeColor(color.cgColor)
                    cg.setLineWidth(width)
                    cg.move(to: origin)
                    cg.addQuadCurve(to: end, control: control)
                    cg.strokePath()
                }
            }
        }
    }

    /// Draws at a point and at its copies across the tile's edges, so the
    /// texture repeats without seams.
    private static func drawTiled(_ cg: CGContext, around point: CGPoint, draw: (CGPoint) -> Void) {
        for dx in [-tile, 0, tile] {
            for dy in [-tile, 0, tile] {
                let origin = CGPoint(x: point.x + dx, y: point.y + dy)
                // Only copies that can reach into the tile.
                guard origin.x > -60, origin.x < tile + 60, origin.y > -60, origin.y < tile + 60 else { continue }
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
