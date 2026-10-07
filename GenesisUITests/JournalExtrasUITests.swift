import XCTest

/// Premium extras in the prayer journal: a template fills the prayer, the
/// attachments section offers its menu, and the prayer exports as a PDF to
/// share. Attachments use the in-memory storage in UI tests (no network).
final class JournalExtrasUITests: GenesisUITestCase {
    @MainActor
    private func openNewPrayer(_ app: XCUIApplication) {
        let journal = app.buttons["home.prayer"]
        XCTAssertTrue(journal.waitForExistence(timeout: Genesis.launchTimeout))
        Genesis.scrollIntoView(journal, in: app, container: app.scrollViews.firstMatch)
        journal.tap()
        let add = app.buttons["prayer.new"]
        XCTAssertTrue(add.waitForExistence(timeout: Genesis.timeout), "The prayer journal opens")
        add.tap()
    }

    @MainActor
    func testTemplateFillsAPrayerAndItExportsAsAPDF() {
        let app = Genesis.launch(extra: ["-uiTestingPremium"])
        openNewPrayer(app)

        let title = app.descendants(matching: .any).matching(identifier: "prayer.title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: Genesis.timeout), "A new prayer opens for editing")
        title.tap()
        title.typeText("Morning prayer")

        // Templates, from the editor's extras menu.
        let extras = app.buttons["prayer.extras"]
        let templates = app.buttons["journal.templates"]
        XCTAssertTrue(extras.waitForExistence(timeout: Genesis.timeout), "The editor has an extras menu")
        Genesis.openMenu(extras, expecting: templates)
        XCTAssertTrue(templates.exists, "Templates are offered")
        let acts = app.buttons["template.acts"]
        Genesis.openMenu(templates, expecting: acts)
        XCTAssertTrue(acts.exists, "The ACTS template is offered")
        acts.tap()

        let body = app.descendants(matching: .any).matching(identifier: "prayer.body").firstMatch
        XCTAssertTrue(Genesis.wait { (body.value as? String)?.contains("Adoration") == true }, "The template fills the prayer: \(String(describing: body.value))")

        // Attachments: the Add menu (Premium).
        let addAttachment = app.buttons["attachments.add"]
        Genesis.scrollIntoView(addAttachment, in: app)
        XCTAssertTrue(addAttachment.exists, "Attachments can be added with Premium")

        // Export as a PDF, then share it.
        let export = app.buttons["journal.exportPDF"]
        Genesis.openMenu(extras, expecting: export)
        XCTAssertTrue(export.exists, "Export PDF is offered")
        export.tap()
        let share = app.buttons["journalExport.share"]
        XCTAssertTrue(share.waitForExistence(timeout: Genesis.timeout * 2), "The PDF is created")
        share.tap()
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(
            Genesis.wait(timeout: Genesis.timeout) { shareSheet.exists || app.navigationBars["UIActivityContentView"].exists },
            "The share sheet opens with the PDF"
        )
    }

    @MainActor
    func testFreeAccountsSeeATeaser() {
        let app = Genesis.launch()
        openNewPrayer(app)
        let title = app.descendants(matching: .any).matching(identifier: "prayer.title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: Genesis.timeout), "A new prayer opens for editing")
        let unlock = app.buttons["teaser.unlock"]
        Genesis.scrollIntoView(unlock, in: app)
        XCTAssertTrue(unlock.exists, "Attachments show a Premium teaser")
        XCTAssertFalse(app.buttons["attachments.add"].exists, "No Add menu without Premium")
    }
}
