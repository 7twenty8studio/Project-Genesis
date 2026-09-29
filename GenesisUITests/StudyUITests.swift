import XCTest

/// Selecting verses, highlighting, notes and bookmarks.
final class StudyUITests: XCTestCase {
    private let john3 = 43_003_001

    @MainActor
    func testLongPressSelectsVerseAndHighlightAppearsInLibrary() {
        let app = Genesis.launch(verse: john3)
        XCTAssertTrue(Genesis.readerText(app).waitForExistence(timeout: Genesis.timeout))

        XCTAssertTrue(Genesis.selectVerse(app), "Long-press should select a verse")
        let reference = app.staticTexts["selection.reference"]
        XCTAssertTrue(reference.label.hasPrefix("John 3:"), "Selected \(reference.label)")
        let selected = reference.label

        app.buttons["selection.highlight.yellow"].tap()
        XCTAssertTrue(Genesis.wait { !reference.exists }, "Highlighting ends the selection")

        Genesis.openTab("Library", in: app)
        XCTAssertTrue(Genesis.element(containing: selected, in: app).waitForExistence(timeout: Genesis.timeout),
                      "\(selected) should be listed under Highlights")
    }

    @MainActor
    func testWriteNoteOnVerse() {
        let app = Genesis.launch(verse: john3)
        XCTAssertTrue(Genesis.readerText(app).waitForExistence(timeout: Genesis.timeout))

        XCTAssertTrue(Genesis.selectVerse(app), "Long-press should select a verse")
        XCTAssertTrue(app.buttons["selection.note"].waitForExistence(timeout: Genesis.timeout))
        app.buttons["selection.note"].tap()

        // A multi-line SwiftUI TextField may surface as a text field or a text view.
        let body = app.descendants(matching: .any).matching(identifier: "note.body").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: Genesis.timeout), "The note editor opens")
        body.tap()
        body.typeText("Born of water and the Spirit")
        app.buttons["note.done"].tap()

        Genesis.openTab("Library", in: app)
        app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(Genesis.element(containing: "Born of water", in: app).waitForExistence(timeout: Genesis.timeout))
    }

    @MainActor
    func testBookmarkFromControls() {
        let app = Genesis.launch(verse: 19_023_001)
        let bookmark = app.buttons["reader.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: Genesis.launchTimeout))
        XCTAssertEqual(bookmark.label, "Add bookmark")
        bookmark.tap()
        XCTAssertTrue(Genesis.wait { bookmark.label == "Remove bookmark" })

        Genesis.openTab("Library", in: app)
        app.buttons["Bookmarks"].firstMatch.tap()
        XCTAssertTrue(Genesis.element(containing: "Psalms 23", in: app).waitForExistence(timeout: Genesis.timeout))
    }

    @MainActor
    func testCancelSelection() {
        let app = Genesis.launch(verse: john3)
        XCTAssertTrue(Genesis.readerText(app).waitForExistence(timeout: Genesis.timeout))
        XCTAssertTrue(Genesis.selectVerse(app), "Long-press should select a verse")
        XCTAssertTrue(app.buttons["selection.done"].waitForExistence(timeout: Genesis.timeout))
        app.buttons["selection.done"].tap()
        XCTAssertTrue(Genesis.wait { !app.staticTexts["selection.reference"].exists })
    }
}
