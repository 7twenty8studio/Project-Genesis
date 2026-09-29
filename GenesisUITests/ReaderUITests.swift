import XCTest

/// The reader: page turns, controls, chapter navigation.
final class ReaderUITests: XCTestCase {
    /// Psalm 119 is long, so there are always pages to turn in both directions.
    private let psalm119 = 19_119_001

    @MainActor
    func testTapRightEdgeTurnsPageAndLeftEdgeTurnsBack() throws {
        try XCTSkipIf(Genesis.isScrollPass, "Edge taps turn pages only in page mode")
        let app = Genesis.launch(verse: psalm119)
        let text = Genesis.readerText(app)
        XCTAssertTrue(text.waitForExistence(timeout: Genesis.timeout))

        var first: String?
        XCTAssertTrue(Genesis.wait { first = Genesis.visiblePageSignature(app); return first != nil })

        text.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        var second: String?
        XCTAssertTrue(Genesis.wait {
            second = Genesis.visiblePageSignature(app)
            return second != nil && second != first
        }, "Tapping the right edge should turn to the next page")

        Genesis.readerText(app).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(Genesis.wait { Genesis.visiblePageSignature(app) == first }, "Tapping the left edge should turn back")
    }

    @MainActor
    func testSwipeTurnsPage() throws {
        try XCTSkipIf(Genesis.isScrollPass, "Swipes change chapters in scroll mode")
        let app = Genesis.launch(verse: psalm119)
        let text = Genesis.readerText(app)
        XCTAssertTrue(text.waitForExistence(timeout: Genesis.timeout))
        var first: String?
        XCTAssertTrue(Genesis.wait { first = Genesis.visiblePageSignature(app); return first != nil })

        text.swipeLeft()
        XCTAssertTrue(Genesis.wait {
            let now = Genesis.visiblePageSignature(app)
            return now != nil && now != first
        }, "Swiping left should turn the page")
    }

    @MainActor
    func testTapCenterTogglesControls() {
        let app = Genesis.launch(verse: 1_001_001)
        let chapterButton = app.buttons["reader.chapterButton"]
        XCTAssertTrue(chapterButton.waitForExistence(timeout: Genesis.timeout), "Controls start visible")

        Genesis.tapCenter(of: Genesis.readerText(app))
        XCTAssertTrue(Genesis.wait { !chapterButton.exists }, "Tapping the page hides the controls")

        Genesis.tapCenter(of: Genesis.readerText(app))
        XCTAssertTrue(chapterButton.waitForExistence(timeout: Genesis.timeout), "Tapping again shows them")
    }

    @MainActor
    func testNextAndPreviousChapterCrossBooks() {
        let app = Genesis.launch(verse: 1_050_001) // Genesis 50
        XCTAssertEqual(Genesis.chapterTitle(app), "Genesis 50")

        app.buttons["reader.nextChapter"].tap()
        XCTAssertTrue(Genesis.wait { Genesis.chapterTitle(app) == "Exodus 1" })

        app.buttons["reader.previousChapter"].tap()
        XCTAssertTrue(Genesis.wait { Genesis.chapterTitle(app) == "Genesis 50" })
    }

    @MainActor
    func testChapterPickerOpensChosenChapter() {
        let app = Genesis.launch(verse: 1_001_001)
        let chapterButton = app.buttons["reader.chapterButton"]
        XCTAssertTrue(chapterButton.waitForExistence(timeout: Genesis.launchTimeout))
        chapterButton.tap()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Genesis.timeout))
        search.tap()
        search.typeText("Romans")
        // The row reads "Romans, 16" (name and chapter count).
        let romans = Genesis.button(startingWith: "Romans", in: app)
        XCTAssertTrue(romans.waitForExistence(timeout: Genesis.timeout))
        romans.tap()
        let chapter8 = app.buttons["Chapter 8"]
        XCTAssertTrue(chapter8.waitForExistence(timeout: Genesis.timeout))
        chapter8.tap()

        XCTAssertTrue(Genesis.wait { Genesis.chapterTitle(app) == "Romans 8" })
    }

    @MainActor
    func testSwitchTranslation() {
        let app = Genesis.launch(verse: 43_003_016)
        let translation = app.buttons["reader.translation"]
        XCTAssertTrue(translation.waitForExistence(timeout: Genesis.timeout))
        // Menu items can appear as buttons (iPhone) or menu items (iPad).
        let asv = Genesis.anyElement(startingWith: "ASV", in: app)
        Genesis.openMenu(translation, expecting: asv)
        XCTAssertTrue(asv.exists, "The translation menu lists ASV")
        asv.tap()
        XCTAssertTrue(Genesis.wait { translation.label == "Translation, American Standard Version" })
        XCTAssertEqual(Genesis.chapterTitle(app), "John 3", "Switching translation keeps your place")
    }
}
