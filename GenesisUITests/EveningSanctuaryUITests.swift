import XCTest

/// Evening Sanctuary (Premium): a candle-lit reading space for night.
/// UI tests play no sounds (the app uses a silent ambient output).
final class EveningSanctuaryUITests: GenesisUITestCase {
    private let john316 = 43_003_016

    /// The moon button, or the same item in the "More" menu on narrow screens.
    @MainActor
    private func openSanctuary(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: Genesis.launchTimeout))
        let sanctuary = app.buttons["reader.sanctuary"]
        if !sanctuary.waitForExistence(timeout: 2) {
            let more = app.buttons["reader.more"]
            XCTAssertTrue(more.waitForExistence(timeout: Genesis.timeout), "Evening Sanctuary is in the controls or the More menu")
            Genesis.openMenu(more, expecting: sanctuary)
        }
        XCTAssertTrue(sanctuary.waitForExistence(timeout: Genesis.timeout), "The reader offers Evening Sanctuary")
        sanctuary.tap()
    }

    @MainActor
    func testEveningSanctuaryShowsTheChapter() {
        let app = Genesis.launch(verse: john316, extra: ["-uiTestingPremium", "-uiTestingEvening"])
        openSanctuary(app)

        let title = app.staticTexts["sanctuary.title"]
        XCTAssertTrue(title.waitForExistence(timeout: Genesis.timeout), "The sanctuary opens on the chapter")
        let verse = app.staticTexts["sanctuary.verse.16"]
        XCTAssertTrue(verse.waitForExistence(timeout: Genesis.timeout), "It opens at the verse being read")
        XCTAssertTrue(verse.label.contains("For God so loved the world"), "The verse is the Bible's own text")
        XCTAssertTrue(app.buttons["sanctuary.sleepTimer"].exists, "A sleep timer is offered")

        app.buttons["sanctuary.close"].tap()
        XCTAssertTrue(Genesis.wait { !title.exists }, "Closing returns to the reader")
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: Genesis.timeout))
    }

    @MainActor
    func testEveningSanctuaryIsLockedForFreeAccounts() {
        let app = Genesis.launch(verse: john316, extra: ["-uiTestingEvening"])
        openSanctuary(app)
        XCTAssertTrue(app.buttons["premium.subscribe"].waitForExistence(timeout: Genesis.timeout), "Free accounts are offered Premium")
        XCTAssertFalse(app.staticTexts["sanctuary.title"].exists)
    }

    @MainActor
    func testHomeOffersTheSanctuaryInTheEvening() {
        let app = Genesis.launch(extra: ["-uiTestingEvening", "-uiTestingPremium"])
        Genesis.openTab("Home", in: app)
        let card = app.buttons["home.sanctuary"]
        XCTAssertTrue(card.waitForExistence(timeout: Genesis.launchTimeout), "Home shows the evening card")
        card.tap()
        XCTAssertTrue(app.staticTexts["sanctuary.title"].waitForExistence(timeout: Genesis.timeout))
    }
}
