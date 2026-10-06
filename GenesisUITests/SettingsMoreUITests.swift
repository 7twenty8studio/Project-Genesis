import XCTest

/// Settings from Home: reading and theme, sending feedback, and the Premium
/// morning welcome.
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

    @MainActor
    func testMorningWelcomeGreetsPremiumOnceAndContinuesReading() {
        let app = Genesis.launch(extra: ["-uiTestingPremium", "-uiTestingWelcome"])
        let greeting = app.descendants(matching: .any).matching(identifier: "welcome.greeting").firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: Genesis.launchTimeout), "Premium is welcomed on the first open of the day")
        XCTAssertTrue(greeting.label.contains("Good"), "A greeting by time of day: \(greeting.label)")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "welcome.verse").firstMatch.waitForExistence(timeout: Genesis.timeout), "Today's verse fades in")
        let continueReading = app.buttons["welcome.continue"]
        XCTAssertTrue(continueReading.waitForExistence(timeout: Genesis.timeout))
        continueReading.tap()
        XCTAssertTrue(Genesis.wait { !greeting.exists }, "The welcome closes")
        XCTAssertTrue(app.buttons["reader.translation"].waitForExistence(timeout: Genesis.timeout) || app.textViews.firstMatch.exists, "Continue Reading opens the reader")
    }

    @MainActor
    func testMorningWelcomeIsPremium() {
        let app = Genesis.launch(extra: ["-uiTestingWelcome"])
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: Genesis.launchTimeout))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "welcome.greeting").firstMatch.waitForExistence(timeout: 3), "Free accounts aren't shown it")
        openSettings(app)
        let row = app.buttons["settings.welcome"]
        Genesis.scrollIntoView(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: Genesis.timeout), "Settings offers it")
        row.tap()
        XCTAssertTrue(app.buttons["premium.subscribe"].waitForExistence(timeout: Genesis.timeout), "…as part of Premium")
    }
}
