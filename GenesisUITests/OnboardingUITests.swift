import XCTest

/// First launch: choose a translation, optionally choose features, and be
/// reading quickly (PRD: within 30 seconds).
final class OnboardingUITests: GenesisUITestCase {
    @MainActor
    private func continuePastFeatures(_ app: XCUIApplication, simple: Bool = false) {
        let button = app.buttons[simple ? "features.simple" : "features.continue"]
        Genesis.scrollIntoView(button, in: app)
        XCTAssertTrue(button.waitForExistence(timeout: Genesis.timeout), "Feature choices come next")
        button.tap()
    }

    @MainActor
    func testChooseTranslationAndBeginReading() {
        let app = Genesis.launch(onboarding: true)

        let web = app.buttons["onboarding.translation.WEB"]
        XCTAssertTrue(web.waitForExistence(timeout: Genesis.launchTimeout), "Translation choices should appear")
        // Timed from the first screen, not simulator start-up, which is slow
        // when several simulators run at once.
        let start = Date()
        web.tap()
        app.buttons["onboarding.begin"].tap()
        continuePastFeatures(app)

        XCTAssertEqual(Genesis.chapterTitle(app), "Genesis 1")
        XCTAssertEqual(app.buttons["reader.translation"].label, "Translation, World English Bible")
        XCTAssertLessThan(Date().timeIntervalSince(start), 30, "Reading should begin within 30 seconds")
        XCTAssertTrue(app.buttons["reader.listen"].exists, "Listening is on by default")
    }

    @MainActor
    func testStartWithJohn() {
        let app = Genesis.launch(onboarding: true)
        let john = app.buttons["onboarding.john"]
        XCTAssertTrue(john.waitForExistence(timeout: Genesis.launchTimeout))
        john.tap()
        continuePastFeatures(app)
        XCTAssertEqual(Genesis.chapterTitle(app), "John 1")
    }

    @MainActor
    func testKeepItSimpleHidesOptionalFeatures() {
        let app = Genesis.launch(onboarding: true)
        let begin = app.buttons["onboarding.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: Genesis.launchTimeout))
        begin.tap()
        continuePastFeatures(app, simple: true)
        XCTAssertEqual(Genesis.chapterTitle(app), "Genesis 1")
        XCTAssertTrue(app.buttons["reader.settings"].exists)
        XCTAssertFalse(app.buttons["reader.listen"].exists, "Listening is hidden")
        XCTAssertFalse(app.tabBars.buttons["Explore"].exists || app.buttons["Explore"].exists, "Explore is hidden")
    }
}
