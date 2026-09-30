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

    override func tearDown() {
        if let run = testRun, !run.hasSucceeded {
            // Synchronous tearDown runs on the main thread.
            MainActor.assumeIsolated {
                for attachment in Self.failureAttachments() { add(attachment) }
            }
        }
        super.tearDown()
    }

    @MainActor
    private static func failureAttachments() -> [XCTAttachment] {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Screen at failure"
        screenshot.lifetime = .keepAlways
        var attachments = [screenshot]

        let app = XCUIApplication()
        if app.state == .runningForeground || app.state == .runningBackground {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Accessibility tree at failure"
            tree.lifetime = .keepAlways
            attachments.append(tree)
        }
        return attachments
    }
}
