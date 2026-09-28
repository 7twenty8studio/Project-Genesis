import XCTest

/// Reading settings and app launch performance.
final class SettingsUITests: XCTestCase {
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

        app.buttons["Scroll"].firstMatch.tap()
        app.buttons["settings.done"].tap()

        XCTAssertTrue(app.textViews["reader.scroll"].waitForExistence(timeout: Genesis.timeout), "Reader switches to scroll mode")
    }

    @MainActor
    func testTextSizeChangeIsRemembered() {
        let app = Genesis.launch(verse: 1_001_001)
        let settings = app.buttons["reader.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: Genesis.timeout))
        settings.tap()

        XCTAssertTrue(app.staticTexts["19 pt"].waitForExistence(timeout: Genesis.timeout), "Default size is 19 pt")
        app.buttons["Larger text"].tap()
        app.buttons["Larger text"].tap()
        XCTAssertTrue(app.staticTexts["21 pt"].waitForExistence(timeout: Genesis.timeout))
        app.buttons["settings.done"].tap()

        Genesis.showControls(app)
        app.buttons["reader.settings"].tap()
        XCTAssertTrue(app.staticTexts["21 pt"].waitForExistence(timeout: Genesis.timeout), "The new size is kept")
    }
}

/// Launch time against the PRD target of under one second. Runs five launches,
/// so it only runs when requested (`./Scripts/build.sh --ui-full`).
final class LaunchPerformanceUITests: XCTestCase {
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
