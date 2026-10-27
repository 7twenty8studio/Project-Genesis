import CoreGraphics
import Testing
@testable import Genesis

/// The widget photo's framing (`PhotoFraming`): the crop always fits the
/// photo, has the widget's shape, and follows the finger.
struct PhotoFramingTests {
    let photo = CGSize(width: 4000, height: 3000)

    @Test func atFirstTheWholeWidthOrHeightFillsTheShape() {
        let square = PhotoFraming().crop(imageSize: photo, aspect: 1)
        #expect(square == CGRect(x: 500, y: 0, width: 3000, height: 3000))
        let wide = PhotoFraming().crop(imageSize: photo, aspect: 2)
        #expect(wide == CGRect(x: 0, y: 500, width: 4000, height: 2000))
    }

    @Test func zoomingInKeepsTheShapeAndTheMiddle() {
        let crop = PhotoFraming(zoom: 2).crop(imageSize: photo, aspect: 1)
        #expect(crop.width == 1500 && crop.height == 1500)
        #expect(crop.midX == 2000 && crop.midY == 1500)
    }

    @Test func theCropNeverLeavesThePhoto() {
        let corner = PhotoFraming(zoom: 2, centerX: 0, centerY: 1).crop(imageSize: photo, aspect: 1)
        #expect(corner.minX == 0)
        #expect(corner.maxY == 3000)
        let tooFar = PhotoFraming(zoom: 99).crop(imageSize: photo, aspect: 1)
        #expect(tooFar.width == 3000 / PhotoFraming.maxZoom)
    }

    @Test func draggingRightShowsMoreOfTheLeft() {
        let start = PhotoFraming(zoom: 2)
        let frame = CGSize(width: 150, height: 150)
        let moved = start.panned(by: CGSize(width: 50, height: 0), frameSize: frame, imageSize: photo)
        let before = start.crop(imageSize: photo, aspect: 1)
        let after = moved.crop(imageSize: photo, aspect: 1)
        // 50 points of a 150-point frame is a third of the crop's width.
        #expect(abs((before.minX - after.minX) - before.width / 3) < 0.5)
        #expect(after.minY == before.minY)
    }

    @Test func aPanPastTheEdgeDoesNotBuildUp() {
        let frame = CGSize(width: 100, height: 100)
        let far = PhotoFraming().panned(by: CGSize(width: 5000, height: 0), frameSize: frame, imageSize: photo)
        #expect(far.crop(imageSize: photo, aspect: 1).minX == 0)
        let back = far.panned(by: CGSize(width: -10, height: 0), frameSize: frame, imageSize: photo)
        #expect(back.crop(imageSize: photo, aspect: 1).minX > 0)
    }

    @Test func pinchingOutNeverGoesBelowTheWholePhoto() {
        let zoomed = PhotoFraming(zoom: 2).zoomed(by: 0.1, imageSize: photo, aspect: 1)
        #expect(zoomed.zoom == 1)
    }
}
