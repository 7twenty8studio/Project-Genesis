import XCTest

/// Shared launch and lookup helpers for the Genesis UI tests.
///
/// Every launch passes `-uiTesting`, so the app starts from a clean slate with
/// an in-memory store. Extra launch arguments can come from the environment
/// variable `GENESIS_UI_ARGS` (set by `Scripts/build.sh --ui-full` via
/// `TEST_RUNNER_GENESIS_UI_ARGS`), which is how the same suite runs again with
/// large text, a dark theme or scroll mode.
@MainActor
enum Genesis {
    static let timeout: TimeInterval = 10
    /// The first launch on a freshly booted simulator can be slow, especially
    /// with several simulators running at once.
    static let launchTimeout: TimeInterval = 45

    /// Extra arguments for this test pass, e.g. "-uiTestingReadingMode scroll".
    static var passArguments: [String] {
        let raw = ProcessInfo.processInfo.environment["GENESIS_UI_ARGS"] ?? ""
        return raw.split(separator: " ").map(String.init)
    }

    static var isScrollPass: Bool { passArguments.contains("scroll") }

    /// "landscape" when this pass runs with the device turned sideways
    /// (`TEST_RUNNER_GENESIS_ORIENTATION`); portrait otherwise.
    static var isLandscapePass: Bool {
        ProcessInfo.processInfo.environment["GENESIS_ORIENTATION"] == "landscape"
    }

    /// "open" or "folded" when build.sh has set the iPhone Duo's hinge for
    /// this pass (`TEST_RUNNER_GENESIS_POSTURE`).
    static var expectedPosture: String? {
        ProcessInfo.processInfo.environment["GENESIS_POSTURE"]
    }

    /// Launches the app. By default onboarding is skipped and the reader opens
    /// at `verse` (a VerseID raw value, e.g. 43003016 for John 3:16).
    @discardableResult
    static func launch(onboarding: Bool = false, verse: Int? = nil, extra: [String] = []) -> XCUIApplication {
        // Every launch sets the orientation, so one pass never leaks into the next.
        XCUIDevice.shared.orientation = isLandscapePass ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        var arguments = ["-uiTesting"]
        if !onboarding { arguments.append("-skipOnboarding") }
        if let verse { arguments += ["-uiTestingStart", String(verse)] }
        arguments += extra
        arguments += passArguments
        app.launchArguments = arguments
        app.launch()
        XCUIDevice.shared.orientation = isLandscapePass ? .landscapeLeft : .portrait
        checkScreenShape(app)
        if verse != nil { ensureReaderTab(app) }
        return app
    }

    /// Fails fast if the device isn't in the orientation or posture this pass
    /// is meant to test, so a pass never silently tests the wrong thing.
    private static func checkScreenShape(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        guard window.waitForExistence(timeout: launchTimeout) else { return }
        let size = window.frame.size
        guard size.width > 0, size.height > 0 else { return }
        let ratio = min(size.width, size.height) / max(size.width, size.height)
        if isLandscapePass {
            XCTAssertGreaterThan(size.width, size.height, "This pass runs in landscape")
        }
        switch expectedPosture {
        case "open":
            // The unfolded Duo's inner screen is close to square; a folded phone is tall and narrow.
            XCTAssertGreaterThan(ratio, 0.6, "The iPhone Duo should be unfolded for this pass (window \(size))")
        case "folded":
            XCTAssertLessThan(ratio, 0.6, "The iPhone Duo should be folded for this pass (window \(size))")
        default:
            break
        }
    }

    /// A sheet's search field. iOS tucks the search bar away once a list has
    /// scrolled, so pull the list down to reveal it if needed.
    static func searchField(in app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: timeout) { return field }
        for list in [app.collectionViews.firstMatch, app.tables.firstMatch] where list.exists {
            list.swipeDown()
            if field.waitForExistence(timeout: 2) { break }
        }
        return field
    }

    /// Taps a toolbar button such as "settings.done", waiting for it first:
    /// a sheet's bar can take a moment to settle after the content changes.
    static func tapToolbarButton(_ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons.matching(identifier: identifier).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "\(identifier) is showing", file: file, line: line)
        button.tap()
    }

    /// iPadOS restores the last selected tab when an app relaunches, which can
    /// override where the test asked to start. Make sure the reader is showing.
    static func ensureReaderTab(_ app: XCUIApplication) {
        let chapterButton = app.buttons["reader.chapterButton"]
        if chapterButton.waitForExistence(timeout: launchTimeout) { return }
        openTab("Read", in: app)
        _ = chapterButton.waitForExistence(timeout: timeout)
    }

    /// Opens a menu button. On iPad a menu can surface as a pop-up button that
    /// ignores an element tap, so fall back to tapping its centre point.
    static func openMenu(_ button: XCUIElement, expecting item: XCUIElement) {
        button.tap()
        if item.waitForExistence(timeout: 2) { return }
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        _ = item.waitForExistence(timeout: timeout)
    }

    /// Any element (button or menu item) whose label starts with the text.
    static func anyElement(startingWith text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    // MARK: Reader

    /// The reader's text view in page or scroll mode (the one on screen).
    static func readerText(_ app: XCUIApplication) -> XCUIElement {
        let pages = app.textViews.matching(identifier: "reader.page")
        let scroll = app.textViews["reader.scroll"]
        if scroll.waitForExistence(timeout: 1) { return scroll }
        return onScreen(pages, in: app) ?? pages.firstMatch
    }

    /// A label describing the visible page, e.g. "PSALMS 119|12 pages left in chapter".
    static func visiblePageSignature(_ app: XCUIApplication) -> String? {
        let header = onScreen(app.staticTexts.matching(identifier: "reader.header"), in: app)?.label
        let footer = onScreen(app.staticTexts.matching(identifier: "reader.footer"), in: app)?.label
        guard let header, let footer else { return nil }
        return header + "|" + footer
    }

    /// The chapter title in the reader controls, e.g. "John 3".
    static func chapterTitle(_ app: XCUIApplication) -> String? {
        let button = app.buttons["reader.chapterButton"]
        return button.waitForExistence(timeout: timeout) ? button.label : nil
    }

    /// Makes sure the floating reader controls are showing.
    static func showControls(_ app: XCUIApplication) {
        guard !app.buttons["reader.chapterButton"].exists else { return }
        tapCenter(of: readerText(app))
        _ = app.buttons["reader.chapterButton"].waitForExistence(timeout: timeout)
    }

    static func tapCenter(of element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
    }

    /// Long-presses a verse to start selection. A press can land in the gap
    /// between lines or paragraphs, so a few spots are tried.
    @discardableResult
    static func selectVerse(_ app: XCUIApplication) -> Bool {
        let reference = app.staticTexts["selection.reference"]
        let spots: [CGVector] = [.init(dx: 0.3, dy: 0.45), .init(dx: 0.4, dy: 0.6), .init(dx: 0.3, dy: 0.35), .init(dx: 0.5, dy: 0.7)]
        for spot in spots {
            readerText(app).coordinate(withNormalizedOffset: spot).press(forDuration: 0.8)
            if reference.waitForExistence(timeout: 2) { return true }
        }
        return false
    }

    /// Swipes up inside a sheet or list until the element is on screen.
    /// `container` should be the scrolling list that holds the element; on
    /// iPad other lists (like the study panel) are on screen behind a sheet.
    static func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication, container: XCUIElement? = nil, maxSwipes: Int = 8) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            let list = container ?? app.collectionViews.firstMatch
            if list.exists { list.swipeUp() } else { app.swipeUp() }
            swipes += 1
        }
    }

    /// The reading settings sheet's scrolling list.
    static func settingsList(_ app: XCUIApplication) -> XCUIElement {
        app.collectionViews.containing(.button, identifier: "settings.theme.automatic").firstMatch
    }

    /// A button whose label starts with the text, e.g. "Romans" for a "Romans, 16" row.
    static func button(startingWith text: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    // MARK: Navigation

    /// Taps a tab. Works for the bottom tab bar and the iPad/Duo top tab bar.
    /// The tab bar hides while reading, so bring the reader controls back first.
    static func openTab(_ name: String, in app: XCUIApplication) {
        let tabBarButton = app.tabBars.buttons[name]
        let anyButton = app.buttons[name].firstMatch
        if !tabBarButton.exists && !anyButton.exists && app.textViews.firstMatch.exists {
            showControls(app)
        }
        if tabBarButton.waitForExistence(timeout: 2) {
            tabBarButton.tap()
        } else {
            XCTAssertTrue(anyButton.waitForExistence(timeout: timeout), "The \(name) tab should be reachable")
            anyButton.tap()
        }
    }

    /// Waits until the predicate holds, polling the UI.
    static func wait(timeout: TimeInterval = timeout, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    /// Any element whose label contains the text.
    static func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The first element fully inside the window. Page view controllers keep
    /// neighbouring pages loaded just off screen, so position is what counts.
    private static func onScreen(_ query: XCUIElementQuery, in app: XCUIApplication) -> XCUIElement? {
        let window = app.windows.firstMatch.frame
        return query.allElementsBoundByIndex.first { element in
            guard element.exists else { return false }
            let frame = element.frame
            return !frame.isEmpty && frame.minX >= window.minX - 1 && frame.maxX <= window.maxX + 1
        }
    }
}
