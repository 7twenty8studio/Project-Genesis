import XCTest

/// Launch-day demo recordings (not tests): each one walks through a feature at
/// a person's pace while Scripts/record_demos.sh records the simulator's screen.
/// Skipped in normal test runs; record_demos.sh sets GENESIS_DEMO=1.
/// Every step only waits for elements (no assertions beyond that), so a slow
/// simulator makes a slower film rather than a failure.
final class DemoReelUITests: GenesisUITestCase {
    private let premium = ["-uiTestingPremium", "-uiTestingDemo"]

    override func setUpWithError() throws {
        try XCTSkipUnless(Demo.isRecording, "Only for Scripts/record_demos.sh")
        try super.setUpWithError()
        continueAfterFailure = true
    }

    // MARK: 1. Themes

    @MainActor
    func testDemo01Themes() {
        let app = Genesis.launch(verse: 19_023_001, extra: premium + ["-uiTestingTheme", "autumn"])
        _ = Genesis.readerText(app).waitForExistence(timeout: Genesis.launchTimeout)
        Demo.start("themes")
        Demo.pause(4)
        for theme in ["starlight", "winter", "spring"] {
            chooseTheme(theme, in: app)
            Demo.pause(4.5)
        }
        Demo.finish()
    }

    // MARK: 2. Ambient sounds

    @MainActor
    func testDemo02Ambient() {
        let app = Genesis.launch(verse: 19_023_001, extra: premium + ["-uiTestingTheme", "autumn"])
        _ = Genesis.readerText(app).waitForExistence(timeout: Genesis.launchTimeout)
        Demo.start("ambient")
        Demo.pause(2)
        Demo.tap(app.buttons["reader.settings"], in: app)
        let ambient = app.buttons["settings.ambient"]
        Demo.pause(1)
        Demo.tap(ambient, in: app)
        Demo.pause(1.5)
        Demo.tap(app.buttons["ambient.sound.rain"], in: app, mark: "sound:rain")
        Demo.pause(3.5)
        Demo.tap(app.buttons["ambient.sound.fireplace"], in: app, mark: "sound:fireplace")
        Demo.pause(3.5)
        Demo.tap(app.buttons["ambient.sound.birdsong"], in: app, mark: "sound:birdsong")
        Demo.pause(3)
        // Back to the page: the sounds keep playing in the reader's bar.
        if app.navigationBars.buttons.firstMatch.exists { Demo.tap(app.navigationBars.buttons.firstMatch, in: app) }
        Demo.pause(0.8)
        Demo.tap(app.buttons["settings.done"], in: app)
        Demo.pause(5)
        Demo.finish()
    }

    // MARK: 3. Page curl, then scrolling

    @MainActor
    func testDemo03Pages() {
        let app = Genesis.launch(verse: 43_001_001, extra: premium + ["-uiTestingTheme", "paper", "-uiTestingPageTurn", "curl"])
        let text = Genesis.readerText(app)
        _ = text.waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.tapPageTop(app) // hide the controls: just the page
        Demo.start("pages")
        Demo.pause(2.5)
        for _ in 0..<3 {
            Demo.swipe(Genesis.readerText(app), from: 0.85, to: 0.15, in: app)
            Demo.pause(2.2)
        }
        // Scroll mode.
        Demo.revealControls(app)
        Demo.tap(app.buttons["reader.settings"], in: app)
        let scroll = app.segmentedControls.buttons["Scroll"]
        Genesis.scrollIntoView(scroll, in: app, container: Genesis.settingsList(app))
        Demo.pause(0.8)
        Demo.tap(scroll, in: app)
        Demo.pause(1)
        Demo.tap(app.buttons["settings.done"], in: app)
        Demo.pause(1.2)
        Genesis.tapPageTop(app)
        Demo.pause(1)
        for _ in 0..<3 {
            Demo.drag(Genesis.readerText(app), from: 0.75, to: 0.3, in: app)
            Demo.pause(1.4)
        }
        Demo.finish()
    }

    // MARK: 4. Highlights

    @MainActor
    func testDemo04Highlights() {
        let app = Genesis.launch(verse: 43_003_014, extra: premium + ["-uiTestingTheme", "paper"])
        _ = Genesis.readerText(app).waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.tapPageTop(app)
        Demo.start("highlights")
        Demo.pause(2.5)
        let colors = ["yellow", "green", "blue"]
        let spots: [CGVector] = [.init(dx: 0.45, dy: 0.35), .init(dx: 0.45, dy: 0.55), .init(dx: 0.45, dy: 0.75)]
        for (spot, color) in zip(spots, colors) {
            Demo.tap(at: spot, of: Genesis.readerText(app), in: app)
            Demo.pause(1.4)
            let swatch = app.buttons["selection.highlight.\(color)"]
            Demo.tap(swatch.exists ? swatch : app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'selection.highlight.'")).firstMatch, in: app)
            Demo.pause(2)
        }
        Demo.pause(2)
        Demo.finish()
    }

    // MARK: 5–7. Explore

    @MainActor
    func testDemo05Timeline() {
        let app = Genesis.launch(extra: premium)
        _ = app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.openTab("Explore", in: app)
        openSection("Timeline", in: app)
        Demo.start("timeline")
        Demo.pause(3)
        let strip = app.scrollViews.containing(.button, identifier: "timeline.era.creation").firstMatch
        let jesus = app.buttons["timeline.era.jesus"]
        Genesis.scrollHorizontallyIntoView(jesus, in: strip, in: app)
        Demo.pause(1)
        Demo.tap(jesus, in: app)
        Demo.pause(2)
        let birth = Genesis.button(startingWith: "Birth of Jesus", in: app)
        Genesis.scrollIntoView(birth, in: app)
        Demo.pause(1)
        Demo.tap(birth, in: app)
        Demo.pause(4)
        if app.buttons["Luke 2"].waitForExistence(timeout: 3) {
            Demo.tap(app.buttons["Luke 2"], in: app)
            Demo.pause(3.5)
        }
        Demo.finish()
    }

    @MainActor
    func testDemo06Map() {
        let app = Genesis.launch(extra: premium)
        _ = app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.openTab("Explore", in: app)
        openSection("Map", in: app)
        Demo.start("map")
        Demo.pause(3)
        let journeys = app.buttons["map.journeys"]
        let paul = app.buttons["Paul's First Journey"]
        Demo.tap(journeys, in: app)
        if !paul.waitForExistence(timeout: 2) { Genesis.openMenu(journeys, expecting: paul) }
        Demo.pause(1)
        Demo.tap(paul, in: app)
        Demo.pause(6)
        let map = app.descendants(matching: .any)["map.view"]
        if map.exists {
            map.pinch(withScale: 1.6, velocity: 0.6)
            Demo.pause(3)
        }
        Demo.finish()
    }

    @MainActor
    func testDemo07People() {
        let app = Genesis.launch(extra: premium)
        _ = app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.openTab("Explore", in: app)
        openSection("People", in: app)
        Demo.start("people")
        Demo.pause(2.5)
        let search = Genesis.searchField(in: app)
        Demo.tap(search, in: app)
        Demo.type("David", into: search)
        Demo.pause(1.2)
        Demo.tap(Genesis.button(startingWith: "David", in: app), in: app)
        Demo.pause(3)
        let solomon = app.buttons["Solomon"]
        for _ in 0..<6 where !(solomon.exists && solomon.isHittable) {
            Demo.drag(app.windows.firstMatch, from: 0.7, to: 0.4, in: app)
            Demo.pause(1)
        }
        Demo.pause(1.5)
        Demo.tap(solomon, in: app)
        Demo.pause(4)
        Demo.finish()
    }

    // MARK: 8. Hebrew and Greek

    @MainActor
    func testDemo08Original() {
        let app = Genesis.launch(verse: 43_001_001, extra: premium + ["-uiTestingTheme", "paper"])
        let translation = app.buttons["reader.translation"]
        _ = translation.waitForExistence(timeout: Genesis.launchTimeout)
        Demo.start("original")
        Demo.pause(2)
        openParallelMenu(in: app)
        Demo.tap(menuItem("reader.parallel.original", label: "Original", in: app), in: app)
        Demo.pause(4)
        Demo.tap(app.buttons["original.interlinear"], in: app)
        Demo.pause(3.5)
        // "logos", the Word: Game 1's answer.
        let logos = app.buttons.matching(identifier: "original.word").matching(NSPredicate(format: "label CONTAINS[c] 'λόγος' OR label CONTAINS[c] 'Word'")).firstMatch
        Demo.tap(logos.exists ? logos : app.buttons.matching(identifier: "original.word").firstMatch, in: app)
        Demo.pause(5)
        let sheet = app.descendants(matching: .any)["originalWord.text"]
        if sheet.exists { Demo.drag(app.windows.firstMatch, from: 0.75, to: 0.45, in: app); Demo.pause(3) }
        Demo.finish()
    }

    // MARK: 9. Parallel reading

    @MainActor
    func testDemo09Parallel() {
        let app = Genesis.launch(verse: 43_003_016, extra: premium + ["-uiTestingTheme", "paper"])
        _ = app.buttons["reader.translation"].waitForExistence(timeout: Genesis.launchTimeout)
        Demo.start("parallel")
        Demo.pause(2)
        openParallelMenu(in: app)
        Demo.tap(menuItem("reader.parallel.WEB", label: "WEB", in: app), in: app)
        Demo.pause(4)
        for _ in 0..<2 {
            Demo.drag(app.windows.firstMatch, from: 0.7, to: 0.4, in: app)
            Demo.pause(2)
        }
        Demo.finish()
    }

    // MARK: 10. Memorize

    @MainActor
    func testDemo10Memorize() {
        // Starts on Home with nothing saved, opens Memorize and adds John 3:16 from
        // the suggestions on camera. (Adding it in the reader first and then
        // switching to Home crashed the app on the iOS 27.2 simulator.)
        let app = Genesis.launch(extra: premium + ["-uiTestingTheme", "paper"])
        let card = app.buttons["home.memorise"]
        _ = card.waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.scrollIntoView(card, in: app)
        card.tap()
        let john316 = app.buttons["memorise.suggestion.43003016"]
        _ = john316.waitForExistence(timeout: Genesis.timeout)
        Demo.pause(1)
        Demo.start("memorize")
        Demo.pause(2)
        Demo.tap(john316, in: app)
        _ = app.staticTexts["memorise.level"].waitForExistence(timeout: Genesis.timeout)
        Demo.pause(2)
        let wordOrder = app.buttons["memorise.game.wordOrder"]
        Genesis.scrollIntoView(wordOrder, in: app)
        Demo.pause(1)
        Demo.tap(wordOrder, in: app)
        Demo.pause(2)
        // Build the verse word by word.
        let words = "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.".split(separator: " ").map(String.init)
        var index = 0
        var taps = 0
        while index < words.count && taps < 60 {
            taps += 1
            if app.buttons["memorise.game.next"].exists { Demo.tap(app.buttons["memorise.game.next"], in: app); Demo.pause(1); continue }
            if app.descendants(matching: .any)["memorise.game.solved"].exists { break }
            let word = words[index]
            let bare = word.trimmingCharacters(in: .punctuationCharacters)
            let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memorise.chip.' AND (label == %@ OR label == %@)", word, bare))
            guard chips.firstMatch.waitForExistence(timeout: 2) else { index += 1; continue }
            Demo.tap(chips.firstMatch, in: app)
            index += 1
            Demo.pause(0.35)
        }
        Demo.pause(4)
        Demo.finish()
    }

    // MARK: 11. Groups and community

    @MainActor
    func testDemo11Groups() {
        let app = Genesis.launch(extra: premium)
        _ = app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.openTab("Together", in: app)
        let field = app.textFields["together.displayName"]
        if field.waitForExistence(timeout: Genesis.timeout) {
            field.tap(); field.typeText("Sam"); app.buttons["together.saveName"].tap()
        }
        _ = app.segmentedControls["together.section"].waitForExistence(timeout: Genesis.timeout)
        Demo.start("groups")
        Demo.pause(2.5)
        let create = app.buttons["groups.create"]
        Genesis.scrollIntoView(create, in: app)
        Demo.tap(create, in: app)
        if app.buttons["community.acceptGuidelines"].waitForExistence(timeout: 3) {
            Demo.pause(1.5)
            Demo.tap(app.buttons["community.acceptGuidelines"], in: app)
        }
        let name = app.textFields["groupForm.name"]
        Demo.tap(name, in: app)
        Demo.type("Thursday Bible Study", into: name)
        Demo.pause(1)
        Demo.tap(app.buttons["groupForm.save"], in: app)
        Demo.pause(3)
        Demo.tap(app.buttons["group.markRead"], in: app)
        Demo.pause(2.5)
        app.segmentedControls.buttons["Prayer"].tap()
        Demo.pause(1.5)
        let prayer = app.descendants(matching: .any).matching(identifier: "group.prayerField").firstMatch
        Genesis.scrollIntoView(prayer, in: app)
        Demo.tap(prayer, in: app)
        Demo.type("Please pray for my mom's surgery on Monday", into: prayer)
        Demo.pause(0.8)
        Demo.tap(app.buttons["group.sharePrayer"], in: app)
        Demo.pause(2)
        Demo.tap(app.buttons["group.prayed"].firstMatch, in: app)
        Demo.pause(3.5)
        Demo.finish()
    }

    // MARK: 14–15. A church's sermon in Versely (12 and 13 are filmed in Church Studio on the web)

    @MainActor
    func testDemo14SermonOpens() {
        let app = Genesis.launch(extra: premium)
        _ = app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout)
        Demo.start("sermon-open")
        Demo.pause(2.5)
        Demo.mark("link")
        app.open(URL(string: "versely://sermon/launchday1")!)
        _ = app.staticTexts["churchSermon.title"].waitForExistence(timeout: Genesis.timeout)
        Demo.pause(4)
        Demo.drag(app.windows.firstMatch, from: 0.75, to: 0.4, in: app)
        Demo.pause(3)
        Demo.finish()
    }

    @MainActor
    func testDemo15SermonFollow() {
        let app = Genesis.launch(extra: premium)
        _ = app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout)
        app.open(URL(string: "versely://sermon/launchday1")!)
        _ = app.staticTexts["churchSermon.title"].waitForExistence(timeout: Genesis.timeout)
        Demo.start("sermon-follow")
        Demo.pause(2)
        // The passage, verbatim from the person's own Bible.
        let passage = app.buttons.matching(identifier: "churchSermon.passage").firstMatch
        Genesis.scrollIntoView(passage, in: app)
        Demo.pause(0.8)
        Demo.tap(passage, in: app)
        Demo.pause(5)
        Demo.tap(app.buttons["churchPassage.done"], in: app)
        Demo.pause(1.5)
        // Their own notes, started with the sermon's details.
        let notes = app.buttons["churchSermon.notes"]
        Genesis.scrollIntoView(notes, in: app)
        Demo.tap(notes, in: app)
        Demo.pause(2)
        let body = app.descendants(matching: .any).matching(identifier: "sermon.body").firstMatch
        if body.waitForExistence(timeout: 3) {
            Demo.tap(body, in: app)
            Demo.type("Come as I am. He gives rest.", into: body)
        }
        Demo.pause(3)
        Demo.finish()
    }

    // MARK: Helpers

    @MainActor
    private func chooseTheme(_ theme: String, in app: XCUIApplication) {
        Genesis.showControls(app)
        Demo.tap(app.buttons["reader.settings"], in: app)
        let button = app.buttons["settings.theme.\(theme)"]
        let row = app.scrollViews.containing(.button, identifier: "settings.theme.automatic").firstMatch
        _ = app.buttons["settings.theme.automatic"].waitForExistence(timeout: Genesis.timeout)
        Genesis.scrollHorizontallyIntoView(button, in: row, in: app)
        Demo.pause(0.6)
        Demo.tap(button, in: app)
        Demo.pause(1.2)
        Demo.tap(app.buttons["settings.done"], in: app)
        Demo.pause(0.6)
        Genesis.tapPageTop(app) // controls away: just the page
    }

    @MainActor
    private func openSection(_ name: String, in app: XCUIApplication) {
        let segment = app.segmentedControls.buttons[name]
        if segment.waitForExistence(timeout: Genesis.timeout) { segment.tap() }
    }

    @MainActor
    /// A menu item by its identifier, or by the start of its label: on the
    /// iOS 27.2 simulator a submenu's items lose their identifiers.
    private func menuItem(_ id: String, label: String, in app: XCUIApplication) -> XCUIElement {
        let byID = app.buttons[id]
        if byID.waitForExistence(timeout: 1.5) { return byID }
        return Genesis.anyElement(startingWith: label, in: app)
    }

    private func openParallelMenu(in app: XCUIApplication) {
        let translation = app.buttons["reader.translation"]
        Demo.tap(translation, in: app)
        let menu = app.buttons["reader.parallelMenu"]
        if !menu.waitForExistence(timeout: 2) { Genesis.openMenu(translation, expecting: menu) }
        Demo.pause(0.8)
        Demo.tap(menu, in: app)
        Demo.pause(0.8)
    }
}

/// Paces the demo recordings and notes when each one starts and ends, and
/// where each tap lands, in GENESIS_DEMO_MARKS/<name>.json (seconds since 1970;
/// positions as fractions of the screen), so the films can be trimmed and
/// given touch marks afterwards.
@MainActor
enum Demo {
    private struct Event: Codable {
        let t: Double
        let kind: String
        var x: Double?
        var y: Double?
        var x2: Double?
        var y2: Double?
    }

    private static var name = ""
    private static var events: [Event] = []

    nonisolated static var isRecording: Bool { ProcessInfo.processInfo.environment["GENESIS_DEMO"] == "1" }

    static func start(_ demo: String) {
        name = demo
        events = []
        mark("start")
    }

    static func mark(_ kind: String) {
        events.append(Event(t: Date().timeIntervalSince1970, kind: kind))
    }

    static func finish() {
        mark("end")
        guard let folder = ProcessInfo.processInfo.environment["GENESIS_DEMO_MARKS"], !folder.isEmpty,
              let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).json"))
    }

    static func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Where an element's centre sits, as fractions of the window.
    private static func point(of frame: CGRect, in app: XCUIApplication) -> (Double, Double) {
        let window = app.windows.firstMatch.frame
        guard window.width > 0, window.height > 0 else { return (0.5, 0.5) }
        return (Double((frame.midX - window.minX) / window.width), Double((frame.midY - window.minY) / window.height))
    }

    static func tap(_ element: XCUIElement, in app: XCUIApplication, mark kind: String? = nil) {
        guard element.waitForExistence(timeout: Genesis.timeout) else { return }
        let (x, y) = point(of: element.frame, in: app)
        events.append(Event(t: Date().timeIntervalSince1970, kind: "tap", x: x, y: y))
        if let kind { mark(kind) }
        element.tap()
    }

    static func tap(at offset: CGVector, of element: XCUIElement, in app: XCUIApplication) {
        guard element.waitForExistence(timeout: Genesis.timeout) else { return }
        let f = element.frame
        let spot = CGRect(x: f.minX + f.width * offset.dx, y: f.minY + f.height * offset.dy, width: 0, height: 0)
        let (x, y) = point(of: spot, in: app)
        events.append(Event(t: Date().timeIntervalSince1970, kind: "tap", x: x, y: y))
        element.coordinate(withNormalizedOffset: offset).tap()
    }

    /// Shows the reader's controls. Right after a page curl the first tap on
    /// the running head can be missed, so it tries the running head again and
    /// then the page number at the bottom (both toggle the controls).
    static func revealControls(_ app: XCUIApplication) {
        let chapter = app.buttons["reader.chapterButton"]
        for spot in [0.05, 0.04, 0.975, 0.98] {
            if chapter.exists { return }
            pause(0.6)
            Genesis.readerText(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: spot)).tap()
            if chapter.waitForExistence(timeout: 2) { return }
        }
    }

    /// A quick sideways swipe across the element (a page turn).
    static func swipe(_ element: XCUIElement, from start: CGFloat, to end: CGFloat, in app: XCUIApplication) {
        let f = element.frame
        let (x, y) = point(of: CGRect(x: f.minX + f.width * start, y: f.midY, width: 0, height: 0), in: app)
        let (x2, _) = point(of: CGRect(x: f.minX + f.width * end, y: f.midY, width: 0, height: 0), in: app)
        events.append(Event(t: Date().timeIntervalSince1970, kind: "swipe", x: x, y: y, x2: x2, y2: y))
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.5))
        let to = element.coordinate(withNormalizedOffset: CGVector(dx: end, dy: 0.5))
        from.press(forDuration: 0.02, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0)
    }

    /// A slow upward drag (scrolling).
    static func drag(_ element: XCUIElement, from start: CGFloat, to end: CGFloat, in app: XCUIApplication) {
        let f = element.frame
        let (x, y) = point(of: CGRect(x: f.midX, y: f.minY + f.height * start, width: 0, height: 0), in: app)
        let (_, y2) = point(of: CGRect(x: f.midX, y: f.minY + f.height * end, width: 0, height: 0), in: app)
        events.append(Event(t: Date().timeIntervalSince1970, kind: "drag", x: x, y: y, x2: x, y2: y2))
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
        let to = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    /// Types a word at a time, like a person.
    static func type(_ text: String, into element: XCUIElement) {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        for (index, word) in words.enumerated() {
            element.typeText(String(word) + (index < words.count - 1 ? " " : ""))
            pause(0.12)
        }
    }
}
