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

    /// Launches the app. By default onboarding is skipped and the reader opens
    /// at `verse` (a VerseID raw value, e.g. 43003016 for John 3:16).
    @discardableResult
    static func launch(onboarding: Bool = false, verse: Int? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-uiTesting"]
        if !onboarding { arguments.append("-skipOnboarding") }
        if let verse { arguments += ["-uiTestingStart", String(verse)] }
        arguments += extra
        arguments += passArguments
        app.launchArguments = arguments
        app.launch()
        if verse != nil { ensureReaderTab(app) }
        return app
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
    static func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            let list = app.collectionViews.firstMatch
            if list.exists { list.swipeUp() } else { app.swipeUp() }
            swipes += 1
        }
    }

    /// A button whose label starts with the text, e.g. "Romans" for a "Romans, 16" row.
    static func button(startingWith text: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    // MARK: Navigation

    /// Taps a tab. Works for the bottom tab bar and the iPad/Duo top tab bar.
    static func openTab(_ name: String, in app: XCUIApplication) {
        let tabBarButton = app.tabBars.buttons[name]
        if tabBarButton.exists {
            tabBarButton.tap()
        } else {
            app.buttons[name].firstMatch.tap()
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
