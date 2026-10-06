import XCTest

/// Settings from Home: reading and theme, and sending feedback.
final class SettingsMoreUITests: GenesisUITestCase {
    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: Genesis.launchTimeout), "Home has a Settings button")
        settings.tap()
    }

    @MainActor
    func testThemeCanBeChangedFromSettings() {
        let app = Genesis.launch()
        openSettings(app)
        let reading = app.buttons["settings.reading"]
        XCTAssertTrue(reading.waitForExistence(timeout: Genesis.timeout), "Settings offers Theme & Reading")
        reading.tap()
        XCTAssertTrue(app.buttons["settings.theme.automatic"].waitForExistence(timeout: Genesis.timeout), "The themes are there")
    }

    @MainActor
    func testFeedbackFormOpens() {
        let app = Genesis.launch()
        openSettings(app)
        let feedback = app.buttons["settings.feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: Genesis.timeout), "Settings offers Send Feedback")
        feedback.tap()
        let message = app.textViews["feedback.message"]
        XCTAssertTrue(message.waitForExistence(timeout: Genesis.timeout), "There's a message box")
        let send = app.buttons["feedback.send"]
        Genesis.scrollIntoView(send, in: app)
        XCTAssertFalse(send.isEnabled, "Nothing to send until something is written")
    }
}
