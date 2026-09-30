import XCTest

/// Reading settings and app launch performance.
final class SettingsUITests: GenesisUITestCase {
    @MainActor
    func testSwitchToScrollModeAndDarkTheme() {
        let app = Genesis.launch(verse: 1_001_001, extra: ["-uiTestingReadingMode", "page"])
        let settings = app.buttons["reader.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: Genesis.timeout))
        settings.tap()

        let slate = app.buttons["settings.theme.slate"]
        XCTAssertTrue(slate.waitForExistence(timeout: Genesis.timeout))
        slate.tap()
        XCTAssertTrue(slate.isSelected, "Slate should be marked as the chosen theme")

        // Layout options sit lower in the sheet.
        let scroll = app.buttons["Scroll"].firstMatch
        Genesis.scrollIntoView(scroll, in: app, container: Genesis.settingsList(app))
        XCTAssertTrue(scroll.exists, "The Scroll option is reachable")
        scroll.tap()
        Genesis.tapToolbarButton("settings.done", in: app)

        XCTAssertTrue(app.textViews["reader.scroll"].waitForExistence(timeout: Genesis.timeout), "Reader switches to scroll mode")
    }

    @MainActor
    func testTextSizeChangeIsRemembered() {
        let app = Genesis.launch(verse: 1_001_001)
        let settings = app.buttons["reader.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: Genesis.timeout))
        settings.tap()

        let larger = app.buttons["Larger text"]
        XCTAssertTrue(app.buttons["settings.theme.automatic"].waitForExistence(timeout: Genesis.timeout))
        // With large accessibility text the size controls may be below the fold.
        Genesis.scrollIntoView(larger, in: app, container: Genesis.settingsList(app))
        XCTAssertTrue(app.staticTexts["19 pt"].waitForExistence(timeout: Genesis.timeout), "Default size is 19 pt")
        larger.tap()
        larger.tap()
        XCTAssertTrue(app.staticTexts["21 pt"].waitForExistence(timeout: Genesis.timeout))
        Genesis.tapToolbarButton("settings.done", in: app)

        Genesis.showControls(app)
        app.buttons["reader.settings"].tap()
        XCTAssertTrue(app.buttons["settings.theme.automatic"].waitForExistence(timeout: Genesis.timeout))
        Genesis.scrollIntoView(app.staticTexts["21 pt"], in: app, container: Genesis.settingsList(app))
        XCTAssertTrue(app.staticTexts["21 pt"].waitForExistence(timeout: Genesis.timeout), "The new size is kept")
    }
}

/// Launch time against the PRD target of under one second. Runs five launches,
/// so it only runs when requested (`./Scripts/build.sh --ui-full`).
final class LaunchPerformanceUITests: GenesisUITestCase {
    @MainActor
    func testLaunchTime() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GENESIS_PERF"] == "1", "Runs with --ui-full")
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding"]
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
}
