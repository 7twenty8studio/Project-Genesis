import XCTest

/// Church sermons (VRS-18) against the in-memory server. The sample group
/// ("Grace Fellowship", joined with its invite code) is a church with two
/// sermons in a series: "Rest for the Weary" for anyone with the link and
/// "The Good Shepherd" for members. "Riverside Church" is listed in search
/// with one link sermon and one for its members.
final class ChurchSermonsUITests: GenesisUITestCase {
    @MainActor
    private func openTogether(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout))
        Genesis.openTab("Together", in: app)
        let field = app.textFields["together.displayName"]
        XCTAssertTrue(field.waitForExistence(timeout: Genesis.timeout))
        field.tap()
        field.typeText("Jo")
        app.buttons["together.saveName"].tap()
        XCTAssertTrue(app.segmentedControls["together.section"].waitForExistence(timeout: Genesis.timeout))
    }

    @MainActor
    private func joinGrace(_ app: XCUIApplication) {
        openTogether(app)
        let join = app.buttons["groups.join"]
        Genesis.scrollIntoView(join, in: app)
        XCTAssertTrue(join.waitForExistence(timeout: Genesis.timeout))
        join.tap()
        Genesis.agreeToGuidelines(in: app)
        let code = app.textFields["joinGroup.code"]
        XCTAssertTrue(code.waitForExistence(timeout: Genesis.timeout))
        code.typeText("grace-12345")
        Genesis.tapToolbarButton("joinGroup.join", in: app)
    }

    @MainActor
    private func sermonRow(_ title: String, in app: XCUIApplication, identifier: String = "groupSermons.row") -> XCUIElement {
        app.buttons.matching(identifier: identifier).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    @MainActor
    func testMembersReadTheirChurchsSermonsAndTakeNotes() {
        let app = Genesis.launch()
        joinGrace(app)

        let row = sermonRow("Rest for the Weary", in: app)
        Genesis.scrollIntoView(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: Genesis.timeout), "The church's sermons are on its group page")
        XCTAssertTrue(sermonRow("The Good Shepherd", in: app).exists, "Members see the members-only sermon too")
        row.tap()

        let title = app.staticTexts["churchSermon.title"]
        XCTAssertTrue(title.waitForExistence(timeout: Genesis.timeout))
        XCTAssertEqual(title.label, "Rest for the Weary")

        // A passage opens over the outline, verbatim from the person's Bible.
        let passage = app.buttons.matching(identifier: "churchSermon.passage").firstMatch
        XCTAssertTrue(passage.waitForExistence(timeout: Genesis.timeout))
        passage.tap()
        XCTAssertTrue(Genesis.element(containing: "Come unto me", in: app).waitForExistence(timeout: Genesis.timeout), "Matthew 11:28 in the KJV")
        app.buttons["churchPassage.done"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: Genesis.timeout), "Back to the outline")

        // The person's own notes start with the sermon's details.
        app.buttons["churchSermon.notes"].tap()
        let notesTitle = app.descendants(matching: .any)["sermon.title"]
        XCTAssertTrue(notesTitle.waitForExistence(timeout: Genesis.timeout))
        XCTAssertEqual(notesTitle.value as? String, "Rest for the Weary")
        Genesis.tapToolbarButton("sermon.done", in: app)
        XCTAssertTrue(Genesis.wait { app.buttons["churchSermon.notes"].label.contains("Open My Notes") }, "The same notes open next time")

        // Locations and Times: where and when the church meets, with directions.
        let locations = app.buttons["churchSermon.locationsButton"]
        XCTAssertTrue(locations.waitForExistence(timeout: Genesis.timeout))
        locations.tap()
        // Times are formatted for the device (iOS puts a narrow space before "PM").
        let wednesdays = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Wednesdays · 7:00")).firstMatch
        XCTAssertTrue(wednesdays.waitForExistence(timeout: Genesis.timeout), "The church's times show")
        XCTAssertTrue(wednesdays.label.hasSuffix("(Bible study)"), "With the church's note")
        XCTAssertTrue(app.links["1 Hill Road, Austin, TX 78701, United States"].exists, "The address opens directions")

        // The series goes on to the members-only sermon: "Join us for …".
        let next = app.buttons["churchSermon.next"]
        Genesis.scrollIntoView(next, in: app)
        XCTAssertTrue(next.waitForExistence(timeout: Genesis.timeout))
        next.tap()
        XCTAssertTrue(Genesis.wait { title.label == "The Good Shepherd" })
    }

    @MainActor
    func testALinkOpensTheSermonOverAnyTab() {
        let app = Genesis.launch()
        XCTAssertTrue(app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout))
        app.open(URL(string: "versely://sermon/riverlink1")!)
        let title = app.staticTexts["churchSermon.title"]
        XCTAssertTrue(title.waitForExistence(timeout: Genesis.timeout), "Anyone with the link reads it")
        XCTAssertEqual(title.label, "Living Water")
        app.buttons["churchSermon.close"].tap()
        XCTAssertFalse(title.waitForExistence(timeout: 2))

        // Another church's members-only sermon says only that it's for members.
        app.open(URL(string: "versely://sermon/rivermemb1")!)
        XCTAssertTrue(app.descendants(matching: .any)["churchSermon.membersOnly"].waitForExistence(timeout: Genesis.timeout))
        XCTAssertFalse(Genesis.element(containing: "Members Night", in: app).exists, "Not even its title")
        app.buttons["churchSermon.close"].tap()

        app.open(URL(string: "versely://sermon/zzzzzzzzzz")!)
        XCTAssertTrue(app.descendants(matching: .any)["churchSermon.notFound"].waitForExistence(timeout: Genesis.timeout))
    }

    @MainActor
    func testFindAChurchByName() {
        let app = Genesis.launch()
        openTogether(app)
        let find = app.buttons["groups.findChurch"]
        Genesis.scrollIntoView(find, in: app)
        XCTAssertTrue(find.waitForExistence(timeout: Genesis.timeout))
        find.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Genesis.timeout))
        search.tap()
        search.typeText("river")
        let sermon = sermonRow("Living Water", in: app, identifier: "churchSearch.sermon")
        XCTAssertTrue(sermon.waitForExistence(timeout: Genesis.timeout), "Listed churches show their link sermons")
        XCTAssertFalse(sermonRow("Members Night", in: app, identifier: "churchSearch.sermon").exists, "Never their members-only ones")
        sermon.tap()
        XCTAssertTrue(app.staticTexts["churchSermon.title"].waitForExistence(timeout: Genesis.timeout))
    }
}
