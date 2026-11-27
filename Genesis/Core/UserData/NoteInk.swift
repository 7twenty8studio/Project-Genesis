import PencilKit
import UIKit

/// A note's handwritten page between PencilKit (how iOS draws and stores
/// it, `Note.drawing`) and Versely Ink (what Android reads and writes,
/// notes.ink). PencilKit's own data stays the iPhone's copy; Versely Ink is
/// made from it on each push and turned into a drawing when a page comes
/// only as ink (written on Android).
enum NoteInk {
    /// Versely Ink for a note's drawing; nil without one (or an empty page).
    static func ink(fromDrawing data: Data?) -> String? {
        guard let data, let drawing = try? PKDrawing(data: data) else { return nil }
        return VerselyInk.encode(page(from: drawing))
    }

    /// PencilKit's data for a page that came as Versely Ink; nil when it can't be read or is empty.
    static func drawingData(fromInk text: String?) -> Data? {
        guard let page = VerselyInk.decode(text), !page.isEmpty else { return nil }
        return drawing(from: page).dataRepresentation()
    }

    /// The page as it looks: each stroke's transform applied, and an erased
    /// stroke written as its visible parts.
    static func page(from drawing: PKDrawing) -> InkPage {
        var strokes: [InkStroke] = []
        for stroke in drawing.strokes {
            let transform = stroke.transform
            let scale = Double(sqrt(abs(transform.a * transform.d - transform.b * transform.c)))
            let ink = inkType(stroke.ink.inkType)
            let color = rgba(stroke.ink.color)
            func point(_ p: PKStrokePoint) -> InkPoint {
                let location = p.location.applying(transform)
                return InkPoint(x: Double(location.x), y: Double(location.y), size: Double(max(p.size.width, p.size.height)) * scale, opacity: Double(p.opacity))
            }
            if stroke.mask == nil {
                let points = stroke.path.map(point)
                guard !points.isEmpty else { continue }
                strokes.append(InkStroke(ink: ink, color: color, points: VerselyInk.padded(points)))
            } else {
                // Partly erased: each visible part becomes a stroke of its own,
                // sampled closely enough that the curve through it is the same line.
                for range in stroke.maskedPathRanges {
                    let points = stroke.path.interpolatedPoints(in: range, by: .distance(2)).map(point)
                    guard !points.isEmpty else { continue }
                    strokes.append(InkStroke(ink: ink, color: color, points: VerselyInk.padded(points)))
                }
            }
        }
        return InkPage(strokes: strokes, width: Double(HandwritingLayout.pageWidth))
    }

    /// A drawing from a page, scaled to this app's page width.
    static func drawing(from page: InkPage) -> PKDrawing {
        let scale = Double(HandwritingLayout.pageWidth) / (page.width > 0 ? page.width : InkPage.pageWidth)
        let strokes: [PKStroke] = page.strokes.compactMap { stroke in
            // A dot is one point; PencilKit draws a curve, so it gets four of the same.
            let source = stroke.points.count == 1 ? Array(repeating: stroke.points[0], count: 4) : stroke.points
            guard !source.isEmpty else { return nil }
            let points = source.enumerated().map { index, p in
                PKStrokePoint(
                    location: CGPoint(x: p.x * scale, y: p.y * scale),
                    timeOffset: TimeInterval(index) * 0.008,
                    size: CGSize(width: p.size * scale, height: p.size * scale),
                    opacity: CGFloat(p.opacity),
                    force: 1,
                    azimuth: 0,
                    altitude: .pi / 2
                )
            }
            let path = PKStrokePath(controlPoints: points, creationDate: Date())
            return PKStroke(ink: PKInk(pkInkType(stroke.ink), color: color(stroke.color)), path: path, transform: .identity, mask: nil)
        }
        return PKDrawing(strokes: strokes)
    }

    static func inkType(_ type: PKInk.InkType) -> InkType {
        switch type {
        case .pen: .pen
        case .pencil: .pencil
        case .marker: .marker
        case .monoline: .monoline
        case .fountainPen: .fountainPen
        case .watercolor: .watercolor
        case .crayon: .crayon
        @unknown default: .pen
        }
    }

    static func pkInkType(_ type: InkType) -> PKInk.InkType {
        switch type {
        case .pen: .pen
        case .pencil: .pencil
        case .marker: .marker
        case .monoline: .monoline
        case .fountainPen: .fountainPen
        case .watercolor: .watercolor
        case .crayon: .crayon
        }
    }

    /// The ink's colour on light paper, as sRGB 0xRRGGBBAA.
    static func rgba(_ color: UIColor) -> UInt32 {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0x0000_00FF }
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return byte(r) << 24 | byte(g) << 16 | byte(b) << 8 | byte(a)
    }

    static func color(_ rgba: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((rgba >> 24) & 0xFF) / 255,
            green: CGFloat((rgba >> 16) & 0xFF) / 255,
            blue: CGFloat((rgba >> 8) & 0xFF) / 255,
            alpha: CGFloat(rgba & 0xFF) / 255
        )
    }
}
