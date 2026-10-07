import XCTest

/// The Sermon Companion: notes in Church Mode with a verse looked up, then
/// found again through favourites and search.
final class SermonsUITests: GenesisUITestCase {
    @MainActor
    func testSermonWithAVerseFromChurchModeIsFoundAgain() {
        let app = Genesis.launch()
        Genesis.openTab("Library", in: app)
        let shelf = app.segmentedControls.buttons["Sermons"].firstMatch
        XCTAssertTrue(shelf.waitForExistence(timeout: Genesis.launchTimeout), "The Library has a Sermons shelf")
        shelf.tap()

        let add = app.buttons["sermons.new"]
        XCTAssertTrue(add.waitForExistence(timeout: Genesis.timeout), "Sermon notes can be started")
        add.tap()

        // Church Mode: a dim screen with a quick verse lookup.
        Genesis.tapToolbarButton("sermon.churchMode", in: app)
        let lookup = app.textFields["sermon.lookupField"]
        XCTAssertTrue(lookup.waitForExistence(timeout: Genesis.timeout), "Church Mode offers a verse lookup")
        lookup.tap()
        lookup.typeText("John 3:16")
        let words = Genesis.element(containing: "For God so loved the world", in: app)
        XCTAssertTrue(words.waitForExistence(timeout: Genesis.timeout), "The verse is shown verbatim from the KJV")
        let insert = app.buttons["sermon.lookupInsert"]
        XCTAssertTrue(insert.waitForExistence(timeout: Genesis.timeout), "It can be inserted")
        insert.tap()

        let title = app.descendants(matching: .any).matching(identifier: "sermon.title").firstMatch
        Genesis.scrollIntoView(title, in: app)
        XCTAssertTrue(title.waitForExistence(timeout: Genesis.timeout), "The sermon has a title field")
        title.tap()
        title.typeText("Grace upon grace")

        let passage = app.descendants(matching: .any).matching(identifier: "sermon.passage").firstMatch
        Genesis.scrollIntoView(passage, in: app)
        XCTAssertTrue(passage.waitForExistence(timeout: Genesis.timeout), "The looked-up passage is attached")

        Genesis.tapToolbarButton("sermon.favourite", in: app)
        Genesis.tapToolbarButton("sermon.done", in: app)

        let row = Genesis.element(containing: "Grace upon grace", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: Genesis.timeout), "The sermon is listed")

        let favourites = app.buttons["sermons.favourites"]
        XCTAssertTrue(favourites.waitForExistence(timeout: Genesis.timeout), "Favourites can be filtered")
        favourites.tap()
        XCTAssertTrue(row.waitForExistence(timeout: Genesis.timeout), "It's among the favourites")

        let search = Genesis.searchField(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: Genesis.timeout), "Sermons can be searched")
        search.tap()
        search.typeText("upon grace")
        XCTAssertTrue(Genesis.element(containing: "Grace upon grace", in: app).waitForExistence(timeout: Genesis.timeout), "Search finds it")
    }
}
