import CoreGraphics
import SwiftUI
import Testing
@testable import Genesis

@Suite("Season shapes")
struct SeasonShapesTests {
    @Test func leavesFitTheirUnitLength() {
        for kind in SeasonShapes.LeafKind.allCases {
            let box = SeasonShapes.leaf(kind).boundingRect
            let isDrawn = box.width > 0.3 && box.height > 0.5
            let fits = box.minX >= -0.6 && box.maxX <= 0.6 && box.minY >= -0.6 && box.maxY <= 0.6
            #expect(isDrawn, "\(kind) has no body")
            #expect(fits, "\(kind) spills out: \(box)")
        }
    }

    @Test func leavesAreSymmetrical() {
        for kind in SeasonShapes.LeafKind.allCases {
            let box = SeasonShapes.leaf(kind).boundingRect
            let offCentre = abs(box.midX)
            #expect(offCentre < 0.01, "\(kind) leans by \(offCentre)")
        }
    }

    @Test func theMixHasEveryLeafAndMostlyMaples() {
        let mix = (0..<7).map { SeasonShapes.LeafKind.mixed($0) }
        let maples = mix.filter { $0 == .maple }.count
        #expect(Set(mix) == Set(SeasonShapes.LeafKind.allCases))
        #expect(maples == 3)
        #expect(SeasonShapes.LeafKind.mixed(7) == SeasonShapes.LeafKind.mixed(0))
    }

    @Test func snowflakesReachTheirRadiusInSixArms() {
        for kind in SeasonShapes.FlakeKind.allCases {
            let box = SeasonShapes.flakeArms(kind).boundingRect
            let reachesTop = abs(box.minY + 1) < 0.01
            let fits = box.width <= 2.01 && box.height <= 2.01
            #expect(reachesTop, "\(kind) arm doesn't reach the radius")
            #expect(fits, "\(kind) is too big: \(box)")
        }
        #expect(SeasonShapes.flakeCore(.stellar) == nil)
        #expect(SeasonShapes.flakeCore(.plate) != nil)
    }

    @Test func blossomFitsItsRadius() {
        let box = SeasonShapes.blossomPetals.boundingRect
        let fits = box.minX >= -1.2 && box.maxX <= 1.2 && box.minY >= -1.2 && box.maxY <= 1.2
        #expect(fits, "blossom spills out: \(box)")
    }

    @Test func butterflyCrossesNowAndThen() {
        let page = CGSize(width: 390, height: 760)
        // The painted still (Reduce Motion, verse images) shows it mid-page.
        let still = ButterflyFlight.state(at: 7.3, page: page)
        #expect(still != nil)
        if let still {
            #expect(still.position.x > 0 && still.position.x < page.width)
            #expect(still.wingOpen >= 0.35 && still.wingOpen <= 1)
        }
        #expect(ButterflyFlight.state(at: 30, page: page) == nil)
        let again = ButterflyFlight.state(at: ButterflyFlight.period + 7.3, page: page)
        let repeats = abs((again?.position.x ?? 0) - (still?.position.x ?? 1)) < 0.01
        #expect(repeats)
        let start = ButterflyFlight.state(at: 0, page: page)
        let end = ButterflyFlight.state(at: ButterflyFlight.crossing - 0.01, page: page)
        #expect((start?.position.x ?? 0) < 0)
        #expect((end?.position.x ?? 0) > page.width)
    }

    @Test func butterflyFacesWhereItFlies() {
        let page = CGSize(width: 390, height: 760)
        var lowest: CGFloat = .infinity
        var highest: CGFloat = -.infinity
        var glides = false
        var step: CGFloat = 0.5
        while step < ButterflyFlight.crossing - 0.5 {
            let here = ButterflyFlight.course(at: step, page: page)
            let next = ButterflyFlight.course(at: step + 0.05, page: page)
            let angle = ButterflyFlight.heading(at: step, page: page)
            // The drawing's head points up (−y); rotated by `angle` it points here.
            let head = CGPoint(x: sin(angle), y: -cos(angle))
            let move = CGPoint(x: next.x - here.x, y: next.y - here.y)
            let length = max(0.0001, hypot(move.x, move.y))
            let along = (head.x * move.x + head.y * move.y) / length
            #expect(along > 0.85, "heading off course at \(step)s: \(along)")
            lowest = min(lowest, angle)
            highest = max(highest, angle)
            if ButterflyFlight.flapping(at: step) < 0.05 { glides = true }
            let open = ButterflyFlight.state(at: step, page: page)?.wingOpen ?? 0
            #expect(open >= 0.35 - 0.0001 && open <= 1.0001)
            step += 0.05
        }
        // It turns as it wanders, not one fixed angle, and glides now and then.
        #expect(highest - lowest > 1)
        #expect(glides)
    }
}
