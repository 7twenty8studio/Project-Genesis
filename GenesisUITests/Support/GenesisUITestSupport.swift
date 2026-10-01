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
    /// Only checked on the Duo itself; other simulators in the same pass ignore it.
    static var expectedPosture: String? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SIMULATOR_DEVICE_NAME"]?.contains("Duo") == true else { return nil }
        return environment["GENESIS_POSTURE"].flatMap { $0.isEmpty ? nil : $0 }
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
        // The Duo's two screens have almost the same shape (outer 466 × 678 pt,
        // inner 669 × 951 pt), so tell them apart by size, not proportions.
        let shortSide = min(size.width, size.height)
        if isLandscapePass {
            XCTAssertGreaterThan(size.width, size.height, "This pass runs in landscape")
        }
        switch expectedPosture {
        case "open":
            XCTAssertGreaterThan(shortSide, 600, "The iPhone Duo should be unfolded for this pass (window \(size))")
        case "folded":
            XCTAssertLessThan(shortSide, 600, "The iPhone Duo should be folded for this pass (window \(size))")
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
    ///
    /// Scrolls in short drags (a swipe can fling right past the element on a
    /// short landscape screen) and in whichever direction the element lies,
    /// until it sits clear of the edges where floating bars may cover it.
    static func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication, container: XCUIElement? = nil, maxSwipes: Int = 8) {
        let list: XCUIElement = {
            if let container, container.exists { return container }
            if app.collectionViews.firstMatch.exists { return app.collectionViews.firstMatch }
            if app.scrollViews.firstMatch.exists { return app.scrollViews.firstMatch }
            return app.windows.firstMatch
        }()
        let attempts = maxSwipes * 3
        for attempt in 0..<attempts {
            let visible = list.frame.intersection(app.windows.firstMatch.frame)
            let margin = min(60, visible.height / 6)
            if element.exists {
                let frame = element.frame
                if frame.minY >= visible.minY && frame.maxY <= visible.maxY - margin && element.isHittable { return }
                if frame.maxY <= visible.minY + margin {
                    drag(list, from: 0.3, to: 0.7)   // it's above: scroll back up
                    continue
                }
                drag(list, from: 0.7, to: 0.3)       // it's below
                continue
            }
            // Not loaded: look further down first, then back up (a lazy list
            // drops rows that scrolled away, so an overshoot hides the element).
            if attempt < attempts / 2 {
                drag(list, from: 0.7, to: 0.3)
            } else {
                drag(list, from: 0.3, to: 0.7)
            }
        }
    }

    /// Scrolls a sideways row (theme picker, era strip) until the element is
    /// fully on screen.
    static func scrollHorizontallyIntoView(_ element: XCUIElement, in row: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        let window = app.windows.firstMatch.frame
        for _ in 0..<maxSwipes {
            if element.exists {
                let frame = element.frame
                // Check the position first: asking an off-screen element if it's
                // hittable is itself an error.
                let onScreen = frame.minX >= window.minX && frame.maxX <= window.maxX
                if onScreen && element.isHittable { return }
                let toLeft = frame.maxX <= window.minX + 20
                // Drag at the element's own height: the row's reported frame can
                // include bars above it (the Duo reports the whole top area).
                let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                let y = frame.midY
                let from = origin.withOffset(CGVector(dx: window.width * (toLeft ? 0.25 : 0.75), dy: y))
                let to = origin.withOffset(CGVector(dx: window.width * (toLeft ? 0.75 : 0.25), dy: y))
                settle(from, to)
            } else {
                row.swipeLeft()
            }
        }
    }

    /// A slow drag (no fling) between two heights of an element, as fractions.
    private static func drag(_ element: XCUIElement, from start: CGFloat, to end: CGFloat) {
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
        let to = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end))
        settle(from, to)
    }

    /// Drags slowly and holds at the end so the list doesn't keep coasting
    /// (momentum can carry a found row away, or unload it, before the tap),
    /// then gives it a moment to come to rest.
    private static func settle(_ from: XCUICoordinate, _ to: XCUICoordinate) {
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    /// The reading settings sheet's scrolling list.
    static func settingsList(_ app: XCUIApplication) -> XCUIElement {
        app.collectionViews["settings.list"]
    }

    /// A button whose label starts with the text, e.g. "Romans" for a "Romans, 16" row.
    static func button(startingWith text: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    // MARK: Navigation

    /// Taps a tab. Works for the bottom tab bar and the iPad/Duo top tab bar.
    /// The tab bar hides while reading, so bring the reader controls back first.
    static func openTab(_ name: String, in app: XCUIApplication) {
        // On iPhone Search is a button on Home (and Library), not a tab.
        if name == "Search", !app.tabBars.buttons["Search"].exists {
            let search = app.buttons["home.search"]
            if !search.exists { openTab("Home", in: app) }
            if search.waitForExistence(timeout: 3) {
                search.tap()
                return
            }
            // iPad: Search is a tab in the top bar; fall through.
        }
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
