import XCTest

/// The Search tab: references and full-text search.
final class SearchUITests: XCTestCase {
    @MainActor
    private func search(_ text: String, in app: XCUIApplication) {
        Genesis.openTab("Search", in: app)
        let field = Genesis.searchField(in: app)
        XCTAssertTrue(field.exists)
        field.tap()
        field.typeText(text)
    }

    @MainActor
    func testReferenceSearchOpensPassage() {
        let app = Genesis.launch()
        search("jn 3:16", in: app)

        let goTo = app.buttons["search.goToReference"]
        XCTAssertTrue(goTo.waitForExistence(timeout: Genesis.timeout))
        XCTAssertTrue(goTo.label.contains("John 3:16"))
        goTo.tap()

        XCTAssertTrue(Genesis.wait { Genesis.chapterTitle(app) == "John 3" })
    }

    @MainActor
    func testWordSearchListsVerses() {
        let app = Genesis.launch()
        // An exact phrase keeps the list short, so the expected verse is on screen.
        search("\"my shepherd\"", in: app)

        let count = app.staticTexts["search.resultCount"]
        XCTAssertTrue(count.waitForExistence(timeout: Genesis.timeout), "A result count appears")
        // Section headers may be shown in capitals ("3 VERSES").
        XCTAssertTrue(count.label.lowercased().contains("verse"), "Count reads \(count.label)")
        XCTAssertTrue(Genesis.element(containing: "Psalms 23:1", in: app).waitForExistence(timeout: Genesis.timeout))
    }

    @MainActor
    func testTappingResultOpensReader() {
        let app = Genesis.launch()
        search("\"Jesus wept\"", in: app)
        let result = Genesis.element(containing: "John 11:35", in: app)
        XCTAssertTrue(result.waitForExistence(timeout: Genesis.timeout))
        result.tap()
        XCTAssertTrue(Genesis.wait { Genesis.chapterTitle(app) == "John 11" })
    }
}
