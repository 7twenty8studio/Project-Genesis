import XCTest

/// Base class for the UI tests. When a test fails it keeps a screenshot and
/// the app's accessibility tree, whatever kind of failure it was (XCTest only
/// does this by itself when an element can't be found), so build.sh can export
/// them with the failures.
class GenesisUITestCase: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        // setUp runs on the main thread.
        let rotated = MainActor.assumeIsolated { Genesis.isLandscapePass ? Self.rotateToLandscape() : true }
        let isDuo = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.contains("Duo") == true
        if !rotated && isDuo {
            throw XCTSkip("The iPhone Duo simulator doesn't turn to landscape from UI tests in this Xcode beta. Check landscape on the Duo by hand (Device > Rotate Left).")
        }
    }

    /// Turns the device and waits for the Home Screen to follow. False if it stays upright.
    @MainActor
    private static func rotateToLandscape() -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            let turned = Genesis.wait(timeout: 3) {
                let frame = springboard.windows.firstMatch.frame
                return frame.width > frame.height
            }
            if turned { return true }
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        return false
    }

    /// Set when the test records a failure. (`testRun.hasSucceeded` isn't
    /// final until after tearDown, so it can't be used there.)
    private var didFail = false

    override func record(_ issue: XCTIssue) {
        didFail = true   // skips aren't issues, so they don't land here
        super.record(issue)
    }

    override func tearDown() {
        if didFail {
            // Synchronous tearDown runs on the main thread. Only plain data
            // crosses to the main actor and back, so `self` stays here.
            let state = MainActor.assumeIsolated { Self.captureFailureState() }
            let screenshot = XCTAttachment(data: state.screenshotPNG, uniformTypeIdentifier: "public.png")
            screenshot.name = "Screen at failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            if let tree = state.accessibilityTree {
                let attachment = XCTAttachment(string: tree)
                attachment.name = "Accessibility tree at failure"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        super.tearDown()
    }

    private struct FailureState: Sendable {
        let screenshotPNG: Data
        let accessibilityTree: String?
    }

    @MainActor
    private static func captureFailureState() -> FailureState {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let app = XCUIApplication()
        let running = app.state == .runningForeground || app.state == .runningBackground
        return FailureState(screenshotPNG: png, accessibilityTree: running ? app.debugDescription : nil)
    }
}
