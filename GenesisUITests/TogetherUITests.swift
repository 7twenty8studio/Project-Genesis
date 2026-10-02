import XCTest

/// Church groups and the community, against an in-memory server (no network,
/// no account). The test person is signed in unless -uiTestingSignedOut.
final class TogetherUITests: GenesisUITestCase {
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
    private func type(_ text: String, into identifier: String, in app: XCUIApplication) {
        let field = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        Genesis.scrollIntoView(field, in: app)
        XCTAssertTrue(field.waitForExistence(timeout: Genesis.timeout), "\(identifier) is showing")
        field.tap()
        field.typeText(text)
    }

    @MainActor
    private func showGroupTab(_ name: String, in app: XCUIApplication) {
        let segment = app.segmentedControls.buttons[name]
        XCTAssertTrue(segment.waitForExistence(timeout: Genesis.timeout), "The \(name) section is offered")
        segment.tap()
    }

    @MainActor
    func testSignedOutPeopleAreAskedToSignIn() {
        let app = Genesis.launch(extra: ["-uiTestingSignedOut"])
        XCTAssertTrue(app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout))
        Genesis.openTab("Together", in: app)
        XCTAssertTrue(app.buttons["together.signIn"].waitForExistence(timeout: Genesis.timeout), "Groups need an account")
    }

    @MainActor
    func testStartAGroupReadPrayAndAnnounce() {
        let app = Genesis.launch()
        openTogether(app)
        app.buttons["groups.create"].tap()
        let name = app.textFields["groupForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Genesis.timeout))
        name.tap()
        name.typeText("Home Group")
        Genesis.tapToolbarButton("groupForm.save", in: app)

        // Today: the plan's first day, marked as read.
        XCTAssertTrue(app.staticTexts["group.reading"].waitForExistence(timeout: Genesis.timeout), "Today's reading is shown")
        let markRead = app.buttons["group.markRead"]
        markRead.tap()
        let count = app.staticTexts["group.readCount"]
        XCTAssertTrue(Genesis.wait { count.label.hasPrefix("1 of 1") }, "Reading is counted")

        // Prayer.
        showGroupTab("Prayer", in: app)
        type("Please pray for our new building", into: "group.prayerField", in: app)
        app.buttons["group.sharePrayer"].tap()
        XCTAssertTrue(Genesis.element(containing: "new building", in: app).waitForExistence(timeout: Genesis.timeout), "The request is shared")
        app.buttons["group.prayed"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["group.prayedCount"].waitForExistence(timeout: Genesis.timeout), "\"I prayed\" is counted")

        // Announcements (the creator leads the group).
        showGroupTab("News", in: app)
        app.buttons["group.announce"].tap()
        let title = app.textFields["announcement.title"]
        XCTAssertTrue(title.waitForExistence(timeout: Genesis.timeout))
        title.tap()
        title.typeText("Picnic on Saturday")
        Genesis.tapToolbarButton("announcement.post", in: app)
        XCTAssertTrue(Genesis.element(containing: "Picnic on Saturday", in: app).waitForExistence(timeout: Genesis.timeout), "The announcement is posted")

        // Members: the invite code to share.
        showGroupTab("Members", in: app)
        XCTAssertTrue(app.staticTexts["group.inviteCode"].waitForExistence(timeout: Genesis.timeout), "The invite code is shown")
    }

    @MainActor
    func testJoinWithACodeAndDiscuss() {
        let app = Genesis.launch()
        openTogether(app, name: "Jo")
        app.buttons["groups.join"].tap()
        let code = app.textFields["joinGroup.code"]
        XCTAssertTrue(code.waitForExistence(timeout: Genesis.timeout))
        code.typeText("grace-12345")
        Genesis.tapToolbarButton("joinGroup.join", in: app)

        XCTAssertTrue(app.navigationBars["Grace Fellowship"].waitForExistence(timeout: Genesis.timeout) || Genesis.element(containing: "Grace Fellowship", in: app).exists, "The group opens")
        type("Loved the Beatitudes today", into: "group.postField", in: app)
        app.buttons["group.send"].tap()
        XCTAssertTrue(Genesis.element(containing: "Beatitudes", in: app).waitForExistence(timeout: Genesis.timeout), "The message is posted")

        showGroupTab("News", in: app)
        XCTAssertTrue(Genesis.element(containing: "Welcome!", in: app).waitForExistence(timeout: Genesis.timeout), "The leader's announcement is there")
        XCTAssertFalse(app.buttons["group.announce"].exists, "Members can't post announcements")
    }

    @MainActor
    func testPrayerWallGuidelinesPostingAndReporting() {
        let app = Genesis.launch()
        openTogether(app)
        showGroupTab("Prayer Wall", in: app)
        let existing = Genesis.element(containing: "father's surgery", in: app)
        XCTAssertTrue(existing.waitForExistence(timeout: Genesis.timeout), "Others' requests are shown")

        app.buttons["community.compose"].tap()
        let agree = app.buttons["community.acceptGuidelines"]
        XCTAssertTrue(agree.waitForExistence(timeout: Genesis.timeout), "The guidelines come first")
        agree.tap()
        let text = app.textViews["community.text"].exists ? app.textViews["community.text"] : app.textFields["community.text"]
        XCTAssertTrue(text.waitForExistence(timeout: Genesis.timeout), "Then the request can be written")
        text.tap()
        text.typeText("Pray for my exams next week")
        Genesis.tapToolbarButton("community.post.send", in: app)
        XCTAssertTrue(Genesis.element(containing: "exams next week", in: app).waitForExistence(timeout: Genesis.timeout), "The request is posted")

        // Report someone else's post: it disappears for the reporter.
        let more = app.buttons.matching(identifier: "content.more")
        let theirs = more.allElementsBoundByIndex.first { button in
            button.frame.midY > existing.frame.minY - 80 && button.frame.midY < existing.frame.maxY + 80
        } ?? more.element(boundBy: more.count - 1)
        Genesis.openMenu(theirs, expecting: app.buttons["Report"])
        app.buttons["Report"].tap()
        let reason = app.buttons["Spam or advertising"]
        XCTAssertTrue(reason.waitForExistence(timeout: Genesis.timeout), "Reasons are offered")
        reason.tap()
        let ok = app.alerts.buttons["OK"]
        XCTAssertTrue(ok.waitForExistence(timeout: Genesis.timeout), "Thanks for reporting")
        ok.tap()
        XCTAssertTrue(Genesis.wait { !existing.exists }, "The reported post is hidden")
    }
}
