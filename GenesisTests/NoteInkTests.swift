import Foundation
import PencilKit
import Testing
@testable import Genesis

/// Versely Ink against the cases Android tests too
/// (supabase/functions/_shared/fixtures/ink.json, InkTest.kt).
struct NoteInkTests {
    private static func fixture() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("supabase/functions/_shared/fixtures/ink.json")
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    @Test func readsTheSharedPage() throws {
        let fixture = try Self.fixture()
        let pageData = try JSONSerialization.data(withJSONObject: fixture["page"] ?? [:])
        let text = String(decoding: pageData, as: UTF8.self)
        let decoded = VerselyInk.decode(text)
        let page = try #require(decoded)
        let expect = fixture["expect"] as? [String: Any] ?? [:]

        let strokeCount = (expect["strokes"] as? NSNumber)?.intValue ?? -1
        #expect(page.strokes.count == strokeCount)
        let inks = page.strokes.map { $0.ink.rawValue }
        #expect(inks == (expect["inks"] as? [String] ?? []))
        let colors = page.strokes.map { VerselyInk.hex($0.color) }
        #expect(colors == (expect["colors"] as? [String] ?? []))
        let counts = page.strokes.map { $0.points.count }
        let expectedCounts = (expect["points"] as? [NSNumber] ?? []).map { $0.intValue }
        #expect(counts == expectedCounts)
        let defaultSize = (expect["defaultSize"] as? NSNumber)?.doubleValue ?? -1
        let lastSize = page.strokes[2].points[0].size
        #expect(lastSize == defaultSize)
        let bottom = (expect["bottom"] as? NSNumber)?.doubleValue ?? -1
        #expect(page.bottom == bottom)
    }

    @Test func rejectsWhatIsNotVerselyInk() throws {
        let fixture = try Self.fixture()
        for text in fixture["rejected"] as? [String] ?? [] {
            let decoded = VerselyInk.decode(text)
            #expect(decoded == nil)
        }
        let missing = VerselyInk.decode(nil)
        #expect(missing == nil)
    }

    @Test func followsTheSharedSpline() throws {
        let fixture = try Self.fixture()
        let spline = fixture["spline"] as? [String: Any] ?? [:]
        let controls = (spline["controls"] as? [[NSNumber]] ?? []).map {
            InkPoint(x: $0[0].doubleValue, y: $0[1].doubleValue, size: $0[2].doubleValue, opacity: $0[3].doubleValue)
        }
        try #require(controls.count == 4)
        for case let sample as [String: Any] in spline["at"] as? [Any] ?? [] {
            let t = (sample["t"] as? NSNumber)?.doubleValue ?? 0
            let expected = (sample["point"] as? [NSNumber] ?? []).map { $0.doubleValue }
            let point = VerselyInk.point(controls[0], controls[1], controls[2], controls[3], at: t)
            let actual = [point.x, point.y, point.size, point.opacity]
            let close = zip(actual, expected).allSatisfy { abs($0 - $1) < 0.001 }
            #expect(close)
        }
    }

    @Test func writesWhatItReads() {
        let page = InkPage(strokes: [
            InkStroke(ink: .fountainPen, color: 0x3366_CCFF, points: [
                InkPoint(x: 1.234, y: 2, size: 3.5, opacity: 1),
                InkPoint(x: 10, y: 20.5, size: 4, opacity: 0.75),
            ]),
        ])
        let text = VerselyInk.encode(page)
        let decoded = VerselyInk.decode(text)
        let point = decoded?.strokes.first?.points.first
        #expect(point?.x == 1.23)
        #expect(decoded?.strokes.first?.ink == .fountainPen)
        #expect(decoded?.strokes.first?.points.count == 2)
        let empty = VerselyInk.encode(InkPage())
        #expect(empty == nil)
    }

    @Test func padsOnlyOnce() {
        let a = InkPoint(x: 0, y: 0, size: 2)
        let b = InkPoint(x: 5, y: 5, size: 2)
        let once = VerselyInk.padded([a, b])
        #expect(once.count == 6)
        let twice = VerselyInk.padded(once)
        #expect(twice.count == 6)
    }

    @Test func pencilKitPagesTravelBothWays() {
        let page = InkPage(strokes: [
            InkStroke(ink: .marker, color: 0xFFD6_0A80, points: VerselyInk.padded([
                InkPoint(x: 100, y: 100, size: 12),
                InkPoint(x: 200, y: 140, size: 12),
                InkPoint(x: 300, y: 120, size: 12),
            ])),
            InkStroke(ink: .pen, color: 0x1C1C_1EFF, points: [InkPoint(x: 50, y: 60, size: 3)]),
        ])
        let drawing = NoteInk.drawing(from: page)
        #expect(drawing.strokes.count == 2)
        let back = NoteInk.page(from: drawing)
        let inks = back.strokes.map { $0.ink }
        #expect(inks == [.marker, .pen])
        let firstColor = back.strokes.first.map { VerselyInk.hex($0.color) }
        #expect(firstColor == "FFD60A80")
        let firstCount = back.strokes.first?.points.count ?? 0
        #expect(firstCount == 7)
        let data = NoteInk.drawingData(fromInk: VerselyInk.encode(page))
        #expect(data != nil)
    }
}
