import XCTest

/// The one-time What's New sheet.
final class WhatsNewUITests: GenesisUITestCase {
    @MainActor
    func testStudyAssistantIsAnnouncedOnceItIsSwitchedOn() {
        let app = Genesis.launch(verse: 43_003_016, extra: ["-uiTestingAI", "-uiTestingWhatsNew"])
        let announcement = app.descendants(matching: .any).matching(identifier: "whatsNew.study-assistant").firstMatch
        XCTAssertTrue(announcement.waitForExistence(timeout: Genesis.launchTimeout), "The new feature is announced")
        XCTAssertTrue(app.staticTexts["whatsNew.title"].exists)
        let done = app.buttons["whatsNew.continue"]
        XCTAssertTrue(done.exists)
        done.tap()
        XCTAssertTrue(Genesis.wait { !done.exists }, "Continue closes it")
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: Genesis.timeout), "Back to reading")
        // It doesn't come back while the app keeps running.
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertFalse(app.buttons["whatsNew.continue"].exists, "Shown only once")
    }

    @MainActor
    func testNothingIsAnnouncedWhileTheFeatureIsOff() {
        let app = Genesis.launch(verse: 43_003_016, extra: ["-uiTestingWhatsNew"])
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: Genesis.launchTimeout))
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        // Other features may be announced; the switched-off assistant isn't.
        let assistant = app.descendants(matching: .any).matching(identifier: "whatsNew.study-assistant").firstMatch
        XCTAssertFalse(assistant.exists, "No announcement for a feature that's switched off")
    }
}
