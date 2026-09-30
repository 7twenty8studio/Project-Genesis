import XCTest

/// First launch: choose a translation and be reading quickly (PRD: within 30 seconds).
final class OnboardingUITests: GenesisUITestCase {
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

        XCTAssertEqual(Genesis.chapterTitle(app), "Genesis 1")
        XCTAssertEqual(app.buttons["reader.translation"].label, "Translation, World English Bible")
        XCTAssertLessThan(Date().timeIntervalSince(start), 30, "Reading should begin within 30 seconds")
    }

    @MainActor
    func testStartWithJohn() {
        let app = Genesis.launch(onboarding: true)
        let john = app.buttons["onboarding.john"]
        XCTAssertTrue(john.waitForExistence(timeout: Genesis.launchTimeout))
        john.tap()
        XCTAssertEqual(Genesis.chapterTitle(app), "John 1")
    }
}
