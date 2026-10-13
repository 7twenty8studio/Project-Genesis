import SwiftUI

/// Google's four-colour "G", drawn here because the official image can't be
/// bundled from this workspace: a ring open at the top right (red, yellow,
/// green, blue) and a blue crossbar. Brand colours, never themed. Decorative:
/// the button around it carries the label.
struct GoogleLogo: View {
    static let blue = Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255)    // #4285F4
    static let green = Color(red: 52 / 255, green: 168 / 255, blue: 83 / 255)    // #34A853
    static let yellow = Color(red: 251 / 255, green: 188 / 255, blue: 5 / 255)   // #FBBC05
    static let red = Color(red: 234 / 255, green: 67 / 255, blue: 53 / 255)      // #EA4335

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let line = side * 0.2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = (side - line) / 2
            // Angles in degrees, 0 at the right, growing clockwise on screen.
            let segments: [(from: Double, to: Double, color: Color)] = [
                (0, 45, Self.blue),
                (45, 145, Self.green),
                (145, 215, Self.yellow),
                (215, 318, Self.red),
            ]
            for segment in segments {
                var path = Path()
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(segment.from),
                    endAngle: .degrees(segment.to),
                    clockwise: false
                )
                context.stroke(path, with: .color(segment.color), style: StrokeStyle(lineWidth: line, lineCap: .butt))
            }
            // The crossbar, from the middle out to the ring's outer edge.
            let bar = CGRect(x: center.x, y: center.y - line / 2, width: side / 2, height: line)
            context.fill(Path(bar), with: .color(Self.blue))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
