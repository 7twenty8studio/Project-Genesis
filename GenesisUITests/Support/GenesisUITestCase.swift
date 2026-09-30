import XCTest

/// Base class for the UI tests. When a test fails it keeps a screenshot and
/// the app's accessibility tree, whatever kind of failure it was (XCTest only
/// does this by itself when an element can't be found), so build.sh can export
/// them with the failures.
class GenesisUITestCase: XCTestCase {
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
