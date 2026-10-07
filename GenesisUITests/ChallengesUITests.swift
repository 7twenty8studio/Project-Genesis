import XCTest

/// Group challenges against the in-memory server. The sample group ("Grace
/// Fellowship", joined with its invite code) has a reading streak its leader
/// started two days ago, and a passage to learn this week.
final class ChallengesUITests: GenesisUITestCase {
    @MainActor
    private func openTogether(_ app: XCUIApplication, name: String = "Sam") {
        XCTAssertTrue(app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout))
        Genesis.openTab("Together", in: app)
        let field = app.textFields["together.displayName"]
        XCTAssertTrue(field.waitForExistence(timeout: Genesis.timeout), "People choose a display name first")
        field.tap()
        field.typeText(name)
        app.buttons["together.saveName"].tap()
        XCTAssertTrue(app.segmentedControls["together.section"].waitForExistence(timeout: Genesis.timeout), "Then they see Together")
        Genesis.scrollIntoView(app.buttons["groups.create"], in: app)
        XCTAssertTrue(app.buttons["groups.create"].waitForExistence(timeout: Genesis.timeout), "Then they see their groups")
    }

    @MainActor
    private func challengeRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "challenges.row").matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    @MainActor
    func testMembersTickTheGroupStreak() {
        let app = Genesis.launch()
        openTogether(app, name: "Jo")
        app.buttons["groups.join"].tap()
        let code = app.textFields["joinGroup.code"]
        XCTAssertTrue(code.waitForExistence(timeout: Genesis.timeout))
        code.typeText("grace-12345")
        Genesis.tapToolbarButton("joinGroup.join", in: app)

        let row = challengeRow("Read every day", in: app)
        Genesis.scrollIntoView(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: Genesis.timeout), "The group's challenges are on its page")
        XCTAssertFalse(app.buttons["challenges.new"].exists, "Members can't start challenges")
        row.tap()

        let stillGoing = app.staticTexts["challenge.stillGoing"]
        XCTAssertTrue(stillGoing.waitForExistence(timeout: Genesis.timeout))
        XCTAssertTrue(Genesis.wait { stillGoing.label.hasPrefix("1 of 2") }, "Only the leader has read every day so far")
        XCTAssertFalse(app.buttons["challenge.end"].exists, "Members can't end challenges")

        app.buttons["challenge.today"].tap()
        XCTAssertTrue(Genesis.wait { stillGoing.label.hasPrefix("2 of 2") }, "Reading today starts a streak")
    }

    @MainActor
    func testLeaderStartsAndEndsAChallenge() {
        let app = Genesis.launch()
        openTogether(app)
        app.buttons["groups.create"].tap()
        let name = app.textFields["groupForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Genesis.timeout))
        name.tap()
        name.typeText("Home Group")
        Genesis.tapToolbarButton("groupForm.save", in: app)

        let new = app.buttons["challenges.new"]
        Genesis.scrollIntoView(new, in: app)
        XCTAssertTrue(new.waitForExistence(timeout: Genesis.timeout), "Leaders can start challenges")
        new.tap()

        let streak = app.buttons["newChallenge.kind.streak"]
        XCTAssertTrue(streak.waitForExistence(timeout: Genesis.timeout))
        streak.tap()
        let title = app.textFields["newChallenge.title"]
        XCTAssertTrue(Genesis.wait { (title.value as? String)?.contains("21 days") == true }, "The title is suggested")
        Genesis.tapToolbarButton("newChallenge.start", in: app)

        let row = challengeRow("21 days", in: app)
        Genesis.scrollIntoView(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: Genesis.timeout), "The challenge is on the group's page")
        row.tap()

        Genesis.tapToolbarButton("challenge.end", in: app)
        // An action sheet on iPhone, a popover on iPad: the dialog's button is
        // the last "End Challenge" (the toolbar's comes first).
        let sheetButton = app.sheets.buttons["End Challenge"]
        let byIdentifier = app.buttons.matching(identifier: "challenge.endConfirm").firstMatch
        let byLabel = app.buttons.matching(NSPredicate(format: "label == %@", "End Challenge"))
        XCTAssertTrue(Genesis.wait { sheetButton.exists || byIdentifier.exists || byLabel.count > 1 }, "Ending asks first")
        if sheetButton.exists {
            sheetButton.tap()
        } else if byIdentifier.exists {
            byIdentifier.tap()
        } else {
            byLabel.element(boundBy: byLabel.count - 1).tap()
        }
        // It stays, finished, with a summary; and moves to Finished on the group's page.
        XCTAssertTrue(app.staticTexts["challenge.summary"].waitForExistence(timeout: Genesis.timeout), "An ended challenge shows its summary")
        XCTAssertFalse(app.buttons["challenge.end"].exists, "A finished challenge can't be ended again")
        app.navigationBars.buttons.firstMatch.tap()
        let finished = app.buttons["challenges.finished"]
        Genesis.scrollIntoView(finished, in: app)
        XCTAssertTrue(finished.waitForExistence(timeout: Genesis.timeout), "It moves to Finished")
    }
}
