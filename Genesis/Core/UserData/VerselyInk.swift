import Foundation

/// Versely Ink: a handwritten page that iPhone, iPad and Android all read
/// and write (docs/HANDWRITING_FORMAT.md). Pure, so it's tested against the
/// same cases as Android (supabase/functions/_shared/fixtures/ink.json);
/// `NoteInk` turns it into PencilKit's drawing and back.
enum InkType: String, CaseIterable, Sendable {
    case pen, pencil, marker, monoline, fountainPen, watercolor, crayon

    /// An unknown type is drawn as a pen.
    init(id: String?) {
        self = id.flatMap(InkType.init(rawValue:)) ?? .pen
    }
}

/// A control point: position in page points, the nib's width there, and its opacity.
struct InkPoint: Equatable, Sendable {
    var x: Double
    var y: Double
    var size: Double
    var opacity: Double = 1
}

/// One stroke; `color` is sRGB 0xRRGGBBAA.
struct InkStroke: Equatable, Sendable {
    var ink: InkType
    var color: UInt32
    var points: [InkPoint]
}

struct InkPage: Equatable, Sendable {
    /// HandwritingLayout.pageWidth.
    static let pageWidth = 768.0

    var strokes: [InkStroke] = []
    var width: Double = InkPage.pageWidth

    var isEmpty: Bool { strokes.isEmpty }

    /// How far down the writing goes, in page points (0 for an empty page).
    var bottom: Double {
        strokes.flatMap(\.points).map { $0.y + $0.size / 2 }.max() ?? 0
    }
}

enum VerselyInk {
    static let format = "versely-ink"
    static let version = 1

    /// The database's limit on notes.ink, in bytes (as notes.drawing).
    static let maxSyncedBytes = 2_097_152

    /// Whether pages go up as `ink` (migration 20261129000000_note_ink.sql).
    /// Off until that migration has run; reading `ink` from the server is
    /// always on. Turning it on also sends every page once (`NoteInkBackfill`).
    static let syncs = false

    /// The page as JSON text; nil for an empty page (a note without one).
    static func encode(_ page: InkPage) -> String? {
        guard !page.isEmpty else { return nil }
        let strokes = page.strokes.map { stroke in
            let points = stroke.points
                .map { "[\(number($0.x)),\(number($0.y)),\(number($0.size)),\(number($0.opacity))]" }
                .joined(separator: ",")
            return "{\"ink\":\"\(stroke.ink.rawValue)\",\"color\":\"\(hex(stroke.color))\",\"points\":[\(points)]}"
        }
        return "{\"format\":\"\(format)\",\"version\":\(version),\"width\":\(number(page.width)),\"strokes\":[\(strokes.joined(separator: ","))]}"
    }

    /// Reads a page; nil when the text isn't Versely Ink (or is a newer version this app can't read).
    static func decode(_ text: String?) -> InkPage? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["format"] as? String == format,
              let version = (root["version"] as? NSNumber)?.intValue, version <= Self.version
        else { return nil }
        let width = (root["width"] as? NSNumber)?.doubleValue ?? InkPage.pageWidth
        let strokes: [InkStroke] = ((root["strokes"] as? [Any]) ?? []).compactMap { element in
            guard let stroke = element as? [String: Any] else { return nil }
            let color = (stroke["color"] as? String).flatMap(parseHex) ?? 0x0000_00FF
            let points: [InkPoint] = ((stroke["points"] as? [Any]) ?? []).compactMap { point in
                guard let values = point as? [Any] else { return nil }
                let numbers = values.map { ($0 as? NSNumber)?.doubleValue }
                guard numbers.count >= 2, let x = numbers[0], let y = numbers[1] else { return nil }
                let size = numbers.count > 2 ? (numbers[2].flatMap { $0 > 0 ? $0 : nil } ?? 2) : 2
                let opacity = numbers.count > 3 ? (numbers[3] ?? 1) : 1
                return InkPoint(x: x, y: y, size: size, opacity: min(max(opacity, 0), 1))
            }
            guard !points.isEmpty else { return nil }
            return InkStroke(ink: InkType(id: stroke["ink"] as? String), color: color, points: points)
        }
        return InkPage(strokes: strokes, width: width > 0 ? width : InkPage.pageWidth)
    }

    /// True when the page (or no page) can go to the server.
    static func fitsSync(_ text: String?) -> Bool {
        guard let text else { return true }
        return text.utf8.count <= maxSyncedBytes
    }

    static func hex(_ color: UInt32) -> String {
        String(format: "%08X", color)
    }

    static func parseHex(_ text: String) -> UInt32? {
        let clean = text.hasPrefix("#") ? String(text.dropFirst()) : text
        switch clean.count {
        case 8: return UInt32(clean, radix: 16)
        case 6: return UInt32(clean, radix: 16).map { ($0 << 8) | 0xFF }
        default: return nil
        }
    }

    /// The first and last points repeated twice more, so the curve reaches
    /// both ends; left as it is when they already are (a page read back).
    static func padded(_ points: [InkPoint]) -> [InkPoint] {
        guard points.count > 1 else { return points }
        let starts = points.count >= 3 && points[0] == points[1] && points[1] == points[2]
        let ends = points.count >= 3 && points[points.count - 1] == points[points.count - 2] && points[points.count - 2] == points[points.count - 3]
        return (starts ? [] : [points[0], points[0]]) + points + (ends ? [] : [points[points.count - 1], points[points.count - 1]])
    }

    /// One point of the uniform cubic B-spline segment between p1 and p2, t in 0...1 (PKStrokePath's curve).
    static func point(_ p0: InkPoint, _ p1: InkPoint, _ p2: InkPoint, _ p3: InkPoint, at t: Double) -> InkPoint {
        let t2 = t * t, t3 = t2 * t
        let b0 = (1 - t) * (1 - t) * (1 - t) / 6
        let b1 = (3 * t3 - 6 * t2 + 4) / 6
        let b2 = (-3 * t3 + 3 * t2 + 3 * t + 1) / 6
        let b3 = t3 / 6
        func mix(_ value: (InkPoint) -> Double) -> Double {
            b0 * value(p0) + b1 * value(p1) + b2 * value(p2) + b3 * value(p3)
        }
        return InkPoint(x: mix(\.x), y: mix(\.y), size: mix(\.size), opacity: mix(\.opacity))
    }

    /// Two decimals at most, and whole numbers without a fraction, so pages stay small.
    private static func number(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int64(rounded)) }
        return String(format: "%.2f", rounded)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}
