import XCTest

/// Memorise Scripture (Premium).
final class MemoriseUITests: GenesisUITestCase {
    private let john316 = 43_003_016

    @MainActor
    func testMemoriseIsLockedForFreeAccounts() {
        let app = Genesis.launch()
        let card = app.buttons["home.memorise"]
        XCTAssertTrue(card.waitForExistence(timeout: Genesis.launchTimeout), "Memorise is on Home")
        Genesis.scrollIntoView(card, in: app)
        card.tap()
        XCTAssertTrue(app.buttons["premium.subscribe"].waitForExistence(timeout: Genesis.timeout), "Free accounts are offered Premium")
    }

    @MainActor
    func testMemoriseAVerseAndReviewIt() {
        let app = Genesis.launch(verse: john316, extra: ["-uiTestingPremium"])
        XCTAssertTrue(Genesis.readerText(app).waitForExistence(timeout: Genesis.launchTimeout))
        XCTAssertTrue(Genesis.selectVerse(app), "A verse can be selected")
        let memorise = app.buttons["selection.memorise"]
        XCTAssertTrue(memorise.waitForExistence(timeout: Genesis.timeout), "Selected verses can be memorised")
        memorise.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reader.confirmation"].waitForExistence(timeout: Genesis.timeout), "It says it was added")

        Genesis.showControls(app)
        Genesis.openTab("Home", in: app)
        let card = app.buttons["home.memorise"]
        XCTAssertTrue(card.waitForExistence(timeout: Genesis.timeout))
        Genesis.scrollIntoView(card, in: app)
        card.tap()

        let review = app.buttons["memorise.review"]
        XCTAssertTrue(review.waitForExistence(timeout: Genesis.timeout), "The new verse is due")
        review.tap()

        XCTAssertTrue(app.staticTexts["memorise.card.reference"].waitForExistence(timeout: Genesis.timeout), "A card shows the reference")
        app.buttons["memorise.hint"].tap()
        XCTAssertTrue(app.staticTexts["memorise.card.hint"].waitForExistence(timeout: Genesis.timeout), "A hint shows the opening words")
        app.buttons["memorise.reveal"].tap()
        XCTAssertTrue(app.staticTexts["memorise.card.text"].waitForExistence(timeout: Genesis.timeout), "Turning the card shows the verse")
        app.buttons["memorise.grade.good"].tap()

        XCTAssertTrue(app.buttons["memorise.done"].waitForExistence(timeout: Genesis.timeout), "The session ends")
        app.buttons["memorise.done"].tap()
        XCTAssertTrue(app.staticTexts["memorise.dueCount"].waitForExistence(timeout: Genesis.timeout))
        XCTAssertEqual(app.staticTexts["memorise.dueCount"].label, "All caught up", "Reviewed verses wait for another day")
    }

    @MainActor
    func testWordOrderShowsTheVersesWordsAsChips() {
        let app = Genesis.launch(verse: john316, extra: ["-uiTestingPremium"])
        XCTAssertTrue(Genesis.readerText(app).waitForExistence(timeout: Genesis.launchTimeout))
        XCTAssertTrue(Genesis.selectVerse(app), "A verse can be selected")
        let memorise = app.buttons["selection.memorise"]
        XCTAssertTrue(memorise.waitForExistence(timeout: Genesis.timeout), "Selected verses can be memorised")
        memorise.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reader.confirmation"].waitForExistence(timeout: Genesis.timeout), "It says it was added")

        Genesis.showControls(app)
        Genesis.openTab("Home", in: app)
        let card = app.buttons["home.memorise"]
        XCTAssertTrue(card.waitForExistence(timeout: Genesis.timeout))
        Genesis.scrollIntoView(card, in: app)
        card.tap()

        XCTAssertTrue(app.staticTexts["memorise.level"].waitForExistence(timeout: Genesis.timeout), "The level shows with a saved verse")
        let wordOrder = app.buttons["memorise.game.wordOrder"]
        Genesis.scrollIntoView(wordOrder, in: app)
        XCTAssertTrue(wordOrder.waitForExistence(timeout: Genesis.timeout), "Word Order is offered")
        XCTAssertTrue(app.buttons["memorise.game.fillGaps"].exists, "Fill the Gaps is offered")
        XCTAssertTrue(app.buttons["memorise.game.speed"].exists, "Speed Round is offered")
        wordOrder.tap()

        XCTAssertTrue(app.staticTexts["memorise.game.reference"].waitForExistence(timeout: Genesis.timeout), "The game shows the reference")
        XCTAssertTrue(app.buttons["memorise.chip.0"].waitForExistence(timeout: Genesis.timeout), "The verse's words appear as chips")
        XCTAssertTrue(app.buttons["memorise.chip.1"].exists)
        app.buttons["memorise.close"].tap()
        XCTAssertTrue(app.buttons["memorise.game.wordOrder"].waitForExistence(timeout: Genesis.timeout), "Closing returns to Memorise")
    }
}
