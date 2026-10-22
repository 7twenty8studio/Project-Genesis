import CoreGraphics
import Testing
@testable import Genesis

/// Starlight's moving sky: shooting stars every 3–8 seconds, twinkling and
/// the haze keeping clear of the words.
@Suite("Night sky")
struct NightSkyTests {
    private var starts: [Double] {
        (0..<200).flatMap(NightSky.streaks(inSlot:)).map(\.start)
    }

    @Test func theFirstShootingStarWaitsAFewSeconds() throws {
        let first = try #require(starts.first)
        #expect(first >= 3 && first <= 5.5)
        #expect(NightSky.activeStreaks(at: 0).isEmpty)
        #expect(NightSky.activeStreaks(at: 2.9).isEmpty)
    }

    @Test func shootingStarsComeEveryThreeToEightSeconds() {
        // Pairs follow 0.45 s behind their first star; the rest are spaced out.
        let lone = (0..<200).compactMap { NightSky.streaks(inSlot: $0).first?.start }
        let gaps = zip(lone.dropFirst(), lone).map { $0 - $1 }
        #expect(gaps.allSatisfy { $0 >= 3 && $0 <= 8 })
        let average = gaps.reduce(0, +) / Double(gaps.count)
        #expect(abs(average - 5.5) < 0.5)
        let pairs = (0..<200).filter { NightSky.streaks(inSlot: $0).count == 2 }.count
        #expect(pairs > 15 && pairs < 55) // about one in six
    }

    @Test func aShootingStarIsSeenOnlyWhileItFalls() throws {
        let streak = try #require(NightSky.streaks(inSlot: 4).first)
        #expect(streak.duration >= 0.6 && streak.duration <= 0.9)
        #expect(NightSky.activeStreaks(at: streak.start + 0.1).contains(streak))
        #expect(!NightSky.activeStreaks(at: streak.start + streak.duration + 0.01).contains(streak))
        #expect(!NightSky.activeStreaks(at: streak.start - 0.01).contains(streak))
    }

    @Test func shootingStarsStayInTheSkyBand() {
        for streak in (0..<100).flatMap(NightSky.streaks(inSlot:)) {
            let (from, travel) = streak.path(width: 390, height: 65)
            #expect(from.y >= 4 && from.y + travel.dy <= 61.0001)
            #expect(from.x >= 0 && from.x <= 390)
            #expect(travel.dy >= 0)
        }
    }

    @Test func starsTwinkleBetweenRestAndFullBrightness() {
        let values = stride(from: 0.0, to: 20, by: 0.05).map { NightSky.brightness(at: $0, period: 5, offset: 1, reduceMotion: false) }
        #expect(values.min()! >= 0.3 - 1e-9)
        #expect(values.max()! > 0.99)
        let calm = stride(from: 0.0, to: 20, by: 0.05).map { NightSky.brightness(at: $0, period: 5, offset: 1, reduceMotion: true) }
        #expect(calm.min()! >= 0.19 && calm.max()! <= 0.81)
    }

    @Test func theEaseOutStartsFastAndLandsSoftly() {
        #expect(NightSky.easeOut(0) < 0.001)
        #expect(NightSky.easeOut(1) > 0.999)
        #expect(NightSky.easeOut(0.2) > 0.6)
    }

    @Test func theHazeFadesBeforeTheText() {
        let text = CGRect(x: 30, y: 100, width: 300, height: 500)
        #expect(NightSky.hazeFade(at: CGPoint(x: 180, y: 300), text: text) == 0)
        #expect(NightSky.hazeFade(at: CGPoint(x: 31, y: 300), text: text) < 0.5)
        #expect(NightSky.hazeFade(at: CGPoint(x: 0, y: 20), text: text) == 1)
        // Smooth: no jump at the text's edge.
        let inside = NightSky.hazeFade(at: CGPoint(x: 30.5, y: 300), text: text)
        let outside = NightSky.hazeFade(at: CGPoint(x: 29.5, y: 300), text: text)
        #expect(abs(inside - outside) < 0.05)
    }

    @Test func theAnnouncementIsNew() {
        let ids = WhatsNewCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains("starlight-shooting-stars"))
    }
}
