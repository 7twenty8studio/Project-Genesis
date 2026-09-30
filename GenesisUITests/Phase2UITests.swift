import XCTest

/// Reading plans, the prayer journal and the account screen.
final class Phase2UITests: GenesisUITestCase {
    @MainActor
    private func scrollHome(to element: XCUIElement, in app: XCUIApplication) {
        Genesis.scrollIntoView(element, in: app, container: app.scrollViews.firstMatch)
    }

    @MainActor
    func testStartPlanAndMarkTodayRead() {
        let app = Genesis.launch()
        let plansCard = app.buttons["home.plans"]
        XCTAssertTrue(plansCard.waitForExistence(timeout: Genesis.launchTimeout), "Home shows the plans card")
        scrollHome(to: plansCard, in: app)
        plansCard.tap()

        let gospels = app.buttons["plans.start.gospels-30"]
        XCTAssertTrue(app.buttons["plans.start.one-year"].waitForExistence(timeout: Genesis.timeout), "The plans list opens")
        // The list is lazy and landscape screens are short: scroll the plan into view first.
        Genesis.scrollIntoView(gospels, in: app)
        XCTAssertTrue(gospels.waitForExistence(timeout: Genesis.timeout), "The Gospels plan is listed")
        gospels.tap()
        let start = app.buttons["plans.confirmStart"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: Genesis.timeout), "Start Today is offered")
        start.tap()

        let today = app.staticTexts["plan.todayTitle"]
        XCTAssertTrue(today.waitForExistence(timeout: Genesis.timeout), "The plan opens on today's reading")
        XCTAssertEqual(today.label, "Matthew 1\u{2013}2")

        let markRead = app.buttons["plan.markRead"]
        XCTAssertTrue(markRead.waitForExistence(timeout: Genesis.timeout), "Mark as Read is showing")
        markRead.tap()
        XCTAssertTrue(Genesis.wait { today.label == "Matthew 3\u{2013}5" }, "The next day's reading is offered")
        XCTAssertTrue(Genesis.element(containing: "3% complete", in: app).exists, "Progress shows 3%")
    }

    @MainActor
    func testPlanReadButtonOpensReader() {
        let app = Genesis.launch()
        let plansCard = app.buttons["home.plans"]
        XCTAssertTrue(plansCard.waitForExistence(timeout: Genesis.launchTimeout), "Home shows the plans card")
        scrollHome(to: plansCard, in: app)
        plansCard.tap()
        let psalms = app.buttons["plans.start.psalms-30"]
        XCTAssertTrue(app.buttons["plans.start.one-year"].waitForExistence(timeout: Genesis.timeout), "The plans list opens")
        Genesis.scrollIntoView(psalms, in: app)
        XCTAssertTrue(psalms.waitForExistence(timeout: Genesis.timeout), "The Psalms plan is listed")
        psalms.tap()
        let start = app.buttons["plans.confirmStart"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: Genesis.timeout), "Start Today is offered")
        start.tap()

        let read = app.buttons["plan.read"]
        XCTAssertTrue(read.waitForExistence(timeout: Genesis.timeout), "The plan's Read button is showing")
        read.tap()
        XCTAssertTrue(Genesis.wait { Genesis.chapterTitle(app) == "Psalms 1" }, "The reader opens at Psalms 1 (showing \(Genesis.chapterTitle(app) ?? "no reader controls"))")
    }

    @MainActor
    func testAddPrayerAndMarkAnswered() {
        let app = Genesis.launch()
        let journal = app.buttons["home.prayer"]
        XCTAssertTrue(journal.waitForExistence(timeout: Genesis.launchTimeout))
        scrollHome(to: journal, in: app)
        journal.tap()

        let add = app.buttons["prayer.new"]
        XCTAssertTrue(add.waitForExistence(timeout: Genesis.timeout))
        add.tap()

        let title = app.descendants(matching: .any).matching(identifier: "prayer.title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: Genesis.timeout))
        title.tap()
        title.typeText("Healing for Grandma")
        Genesis.tapToolbarButton("prayer.done", in: app)

        let row = Genesis.element(containing: "Healing for Grandma", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: Genesis.timeout), "The prayer is listed")
        row.tap()

        let answered = app.buttons["prayer.markAnswered"]
        XCTAssertTrue(answered.waitForExistence(timeout: Genesis.timeout))
        answered.tap()
        Genesis.tapToolbarButton("prayer.done", in: app)

        XCTAssertTrue(Genesis.wait { !row.exists }, "It leaves the Praying list")
        app.buttons["Answered"].firstMatch.tap()
        XCTAssertTrue(Genesis.element(containing: "Healing for Grandma", in: app).waitForExistence(timeout: Genesis.timeout))
    }

    @MainActor
    func testEmptyPrayerIsDiscarded() {
        let app = Genesis.launch()
        let journal = app.buttons["home.prayer"]
        XCTAssertTrue(journal.waitForExistence(timeout: Genesis.launchTimeout))
        scrollHome(to: journal, in: app)
        journal.tap()
        app.buttons["prayer.new"].tap()
        XCTAssertTrue(app.buttons["prayer.done"].waitForExistence(timeout: Genesis.timeout))
        Genesis.tapToolbarButton("prayer.done", in: app)
        XCTAssertTrue(Genesis.element(containing: "No prayer requests", in: app).waitForExistence(timeout: Genesis.timeout))
    }

    @MainActor
    func testAccountOffersGuestMode() {
        let app = Genesis.launch()
        let account = app.buttons["home.account"]
        XCTAssertTrue(account.waitForExistence(timeout: Genesis.launchTimeout), "Home shows the account button")
        account.tap()

        XCTAssertTrue(app.buttons["account.apple"].waitForExistence(timeout: Genesis.timeout), "Sign in with Apple is offered")
        let email = app.textFields["account.email"]
        Genesis.scrollIntoView(email, in: app)
        XCTAssertTrue(email.exists, "Email sign-in is offered")
        let guest = app.buttons["account.guest"]
        Genesis.scrollIntoView(guest, in: app)
        guest.tap()
        XCTAssertTrue(Genesis.wait { !app.buttons["account.apple"].exists }, "Continuing as a guest closes the sheet")
    }
}
