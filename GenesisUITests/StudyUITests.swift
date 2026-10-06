import XCTest

/// Selecting verses, highlighting, notes and bookmarks.
final class StudyUITests: GenesisUITestCase {
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
        Genesis.tapToolbarButton("note.done", in: app)

        Genesis.openTab("Library", in: app)
        app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(Genesis.element(containing: "Born of water", in: app).waitForExistence(timeout: Genesis.timeout))
    }

    @MainActor
    func testJournalEntryOffersPromptAndHandwritingPage() throws {
        let app = Genesis.launch()
        Genesis.openTab("Library", in: app)
        app.buttons["Notes"].firstMatch.tap()

        // The New Note menu's "Journal" item, not the kind filter's "Journal" segment.
        let newNote = app.buttons["library.newNote"].firstMatch
        XCTAssertTrue(newNote.waitForExistence(timeout: Genesis.timeout))
        let filterSegment = app.segmentedControls.buttons["Journal"].firstMatch
        let journalItems = app.buttons.matching(NSPredicate(format: "label == %@", "Journal"))
        Genesis.openMenu(newNote, expecting: journalItems.element(boundBy: filterSegment.exists ? 1 : 0))
        var menuItem: XCUIElement?
        for index in 0..<journalItems.count {
            let item = journalItems.element(boundBy: index)
            if !filterSegment.exists || item.frame != filterSegment.frame { menuItem = item }
        }
        try XCTUnwrap(menuItem, "The New Note menu lists Journal").tap()

        // A new journal entry offers a reflection prompt.
        XCTAssertTrue(app.buttons["note.prompt"].waitForExistence(timeout: Genesis.timeout), "A reflection prompt is offered")

        // Switch to the handwritten page; the canvas appears (no drawing here).
        let pageControl = app.segmentedControls["note.handwriting"]
        let handwriting = pageControl.exists
            ? pageControl.buttons.element(boundBy: 1)
            : app.buttons.matching(NSPredicate(format: "label == %@", "Handwriting")).firstMatch
        XCTAssertTrue(handwriting.waitForExistence(timeout: Genesis.timeout), "The Text / Handwriting switch is showing")
        handwriting.tap()
        let canvas = app.descendants(matching: .any).matching(identifier: "note.canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: Genesis.timeout), "The handwriting canvas appears")

        Genesis.tapToolbarButton("note.done", in: app)
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
