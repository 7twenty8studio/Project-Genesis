import XCTest

/// Launch-day demo recordings (not tests): each one is about ten seconds of
/// someone really using a feature, recorded by Scripts/record_demos.sh from
/// the simulator's screen. Setting up (signing in, creating a group, getting
/// to the screen) happens before `Demo.start`, off camera; the films are cut
/// at the start and end marks. Skipped in normal test runs; record_demos.sh
/// sets GENESIS_DEMO=1. Every step only waits for elements (no assertions
/// beyond that), so a slow simulator makes a slower film rather than a failure.
final class DemoReelUITests: GenesisUITestCase {
    private let premium = ["-uiTestingPremium", "-uiTestingDemo"]

    override func setUpWithError() throws {
        try XCTSkipUnless(Demo.isRecording, "Only for Scripts/record_demos.sh")
        try super.setUpWithError()
        continueAfterFailure = true
    }

    // MARK: 1. Themes: four short films (Autumn, Winter, Forest, Starlight), joined afterwards

    @MainActor func testDemo01aAutumn() { themeFilm("autumn") }
    @MainActor func testDemo01bWinter() { themeFilm("winter") }
    @MainActor func testDemo01cForest() { themeFilm("forest") }
    @MainActor func testDemo01dStarlight() { themeFilm("starlight") }

    /// Psalm 23 in the theme: a moment on the page, two page curls, one back.
    @MainActor
    private func themeFilm(_ theme: String) {
        let app = Genesis.launch(verse: 19_023_001, extra: premium + ["-uiTestingTheme", theme, "-uiTestingPageTurn", "curl"])
        _ = Genesis.readerText(app).waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.tapPageTop(app) // controls away: just the page
        Demo.pause(2.5)         // the scene settles in
        Demo.start("themes-\(theme)")
        Demo.pause(1.6)
        Demo.swipe(Genesis.readerText(app), from: 0.85, to: 0.15, in: app)
        Demo.pause(1.6)
        Demo.swipe(Genesis.readerText(app), from: 0.85, to: 0.15, in: app)
        Demo.pause(1.4)
        Demo.swipe(Genesis.readerText(app), from: 0.15, to: 0.85, in: app)
        Demo.pause(1.4)
        Demo.finish()
    }

    // MARK: 2. Ambient sounds

    @MainActor
    func testDemo02Ambient() {
        let app = Genesis.launch(verse: 19_023_001, extra: premium + ["-uiTestingTheme", "autumn", "-uiTestingPageTurn", "curl"])
        _ = Genesis.readerText(app).waitForExistence(timeout: Genesis.launchTimeout)
        _ = app.buttons["reader.settings"].waitForExistence(timeout: Genesis.timeout)
        Demo.pause(1.5)
        Demo.start("ambient")
        Demo.pause(0.6)
        Demo.tap(app.buttons["reader.settings"], in: app)
        Demo.pause(0.8)
        Demo.tap(app.buttons["settings.ambient"], in: app)
        Demo.pause(0.8)
        Demo.tap(app.buttons["ambient.sound.rain"], in: app, mark: "sound:rain")
        Demo.pause(1.8)
        Demo.tap(app.buttons["ambient.sound.fireplace"], in: app, mark: "sound:fireplace")
        Demo.pause(1.8)
        // Back to the page: the sounds keep playing while you read.
        if app.navigationBars.buttons.firstMatch.exists { Demo.tap(app.navigationBars.buttons.firstMatch, in: app) }
        Demo.pause(0.5)
        Demo.tap(app.buttons["settings.done"], in: app)
        Demo.pause(1)
        Demo.swipe(Genesis.readerText(app), from: 0.85, to: 0.15, in: app)
        Demo.pause(2.5)
        Demo.finish()
    }

    // MARK: 3. Page curl, then scrolling: two short films joined afterwards

    @MainActor
    func testDemo03aCurl() {
        let app = Genesis.launch(verse: 43_001_001, extra: premium + ["-uiTestingTheme", "paper", "-uiTestingPageTurn", "curl"])
        _ = Genesis.readerText(app).waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.tapPageTop(app)
        Demo.pause(1.5)
        Demo.start("pages-curl")
        Demo.pause(0.8)
        for _ in 0..<3 {
            Demo.swipe(Genesis.readerText(app), from: 0.85, to: 0.15, in: app)
            Demo.pause(1.1)
        }
        Demo.swipe(Genesis.readerText(app), from: 0.15, to: 0.85, in: app)
        Demo.pause(1.3)
        Demo.finish()
    }

    @MainActor
    func testDemo03bScroll() {
        let app = Genesis.launch(verse: 43_001_001, extra: premium + ["-uiTestingTheme", "paper", "-uiTestingReadingMode", "scroll"])
        _ = Genesis.readerText(app).waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.tapPageTop(app)
        Demo.pause(1.5)
        Demo.start("pages-scroll")
        Demo.pause(0.6)
        Demo.drag(Genesis.readerText(app), from: 0.8, to: 0.35, in: app, fast: true)
        Demo.pause(1)
        Demo.drag(Genesis.readerText(app), from: 0.8, to: 0.3, in: app, fast: true)
        Demo.pause(1)
        Demo.drag(Genesis.readerText(app), from: 0.75, to: 0.4, in: app)
        Demo.pause(0.8)
        Demo.drag(Genesis.readerText(app), from: 0.35, to: 0.75, in: app, fast: true)
        Demo.pause(1.2)
        Demo.finish()
    }

    // MARK: 4. Highlights

    @MainActor
    func testDemo04Highlights() {
        let app = Genesis.launch(verse: 43_003_014, extra: premium + ["-uiTestingTheme", "paper"])
        _ = Genesis.readerText(app).waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.tapPageTop(app)
        Demo.pause(1.5)
        Demo.start("highlights")
        Demo.pause(0.6)
        let colors = ["yellow", "green", "blue"]
        let spots: [CGVector] = [.init(dx: 0.45, dy: 0.35), .init(dx: 0.45, dy: 0.55), .init(dx: 0.45, dy: 0.75)]
        for (spot, color) in zip(spots, colors) {
            Demo.tap(at: spot, of: Genesis.readerText(app), in: app)
            Demo.pause(0.9)
            let swatch = app.buttons["selection.highlight.\(color)"]
            Demo.tap(swatch.exists ? swatch : app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'selection.highlight.'")).firstMatch, in: app)
            Demo.pause(1.1)
        }
        Demo.pause(1.2)
        Demo.finish()
    }

    // MARK: 5–7. Explore

    @MainActor
    func testDemo05Timeline() {
        let app = Genesis.launch(extra: premium)
        _ = app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.openTab("Explore", in: app)
        openSection("Timeline", in: app)
        let strip = app.scrollViews.containing(.button, identifier: "timeline.era.creation").firstMatch
        let jesus = app.buttons["timeline.era.jesus"]
        Genesis.scrollHorizontallyIntoView(jesus, in: strip, in: app)
        Demo.pause(1.5)
        Demo.start("timeline")
        Demo.pause(0.6)
        Demo.tap(jesus, in: app)
        Demo.pause(1)
        Demo.drag(app.windows.firstMatch, from: 0.75, to: 0.45, in: app, fast: true)
        Demo.pause(0.8)
        let birth = Genesis.button(startingWith: "Birth of Jesus", in: app)
        Genesis.scrollIntoView(birth, in: app)
        Demo.tap(birth, in: app)
        Demo.pause(1.6)
        if app.buttons["Luke 2"].waitForExistence(timeout: 3) {
            Demo.tap(app.buttons["Luke 2"], in: app)
            Demo.pause(1.4)
            Demo.drag(app.windows.firstMatch, from: 0.75, to: 0.4, in: app, fast: true)
            Demo.pause(1.4)
        }
        Demo.finish()
    }

    @MainActor
    func testDemo06Map() {
        let app = Genesis.launch(extra: premium)
        _ = app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.openTab("Explore", in: app)
        openSection("Map", in: app)
        Demo.pause(6) // the map's tiles load off camera
        Demo.start("map")
        Demo.pause(0.6)
        let journeys = app.buttons["map.journeys"]
        let paul = app.buttons["Paul's First Journey"]
        Demo.tap(journeys, in: app)
        if !paul.waitForExistence(timeout: 2) { Genesis.openMenu(journeys, expecting: paul) }
        Demo.pause(0.7)
        Demo.tap(paul, in: app)
        Demo.pause(2.5)
        let map = app.descendants(matching: .any)["map.view"]
        let area = map.exists ? map : app.windows.firstMatch
        Demo.pan(area, from: CGVector(dx: 0.6, dy: 0.55), to: CGVector(dx: 0.4, dy: 0.45), in: app)
        Demo.pause(0.8)
        Demo.mark("pinch")
        area.pinch(withScale: 1.8, velocity: 1.2)
        Demo.pause(1.5)
        if let place = [app.buttons["Antioch"], app.buttons["Lystra"], app.buttons["Derbe"]].first(where: { $0.exists && $0.isHittable }) {
            Demo.tap(place, in: app)
            Demo.pause(2)
        }
        Demo.finish()
    }

    @MainActor
    func testDemo07People() {
        let app = Genesis.launch(extra: premium)
        _ = app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.openTab("Explore", in: app)
        openSection("People", in: app)
        Demo.pause(1.5)
        Demo.start("people")
        Demo.pause(0.6)
        let search = Genesis.searchField(in: app)
        Demo.tap(search, in: app)
        Demo.type("David", into: search)
        Demo.pause(0.7)
        Demo.tap(Genesis.button(startingWith: "David", in: app), in: app)
        Demo.pause(1.6)
        let solomon = app.buttons["Solomon"]
        for _ in 0..<5 where !(solomon.exists && solomon.isHittable) {
            Demo.drag(app.windows.firstMatch, from: 0.7, to: 0.45, in: app, fast: true)
            Demo.pause(0.6)
        }
        Demo.pause(0.6)
        Demo.tap(solomon, in: app)
        Demo.pause(1.5)
        Demo.drag(app.windows.firstMatch, from: 0.7, to: 0.45, in: app, fast: true)
        Demo.pause(1.2)
        Demo.finish()
    }

    // MARK: 8. Hebrew and Greek

    @MainActor
    func testDemo08Original() {
        // Opens straight into the Greek beside the KJV, word by word.
        let app = Genesis.launch(verse: 43_001_001, extra: premium + ["-uiTestingTheme", "paper",
            "-reader.parallel", "original", "-reader.original.interlinear", "YES"])
        _ = app.buttons["reader.translation"].waitForExistence(timeout: Genesis.launchTimeout)
        if !app.buttons.matching(identifier: "original.word").firstMatch.waitForExistence(timeout: 4) {
            openParallelMenu(in: app)
            menuItem("reader.parallel.original", label: "Original", in: app).tap()
        }
        Demo.pause(1.5)
        Demo.start("original")
        Demo.pause(0.8)
        // "logos", the Word: Game 1's answer.
        let logos = app.buttons.matching(identifier: "original.word").matching(NSPredicate(format: "label CONTAINS[c] 'λόγος' OR label CONTAINS[c] 'Word'")).firstMatch
        Demo.tap(logos.exists ? logos : app.buttons.matching(identifier: "original.word").firstMatch, in: app)
        Demo.pause(2.2)
        if app.descendants(matching: .any)["originalWord.text"].exists {
            Demo.drag(app.windows.firstMatch, from: 0.8, to: 0.5, in: app, fast: true)
            Demo.pause(1.4)
            if app.buttons["Done"].exists { Demo.tap(app.buttons["Done"], in: app) } else { app.swipeDown() }
            Demo.pause(0.8)
        }
        Demo.drag(app.windows.firstMatch, from: 0.75, to: 0.4, in: app, fast: true)
        Demo.pause(1)
        Demo.drag(app.windows.firstMatch, from: 0.75, to: 0.4, in: app)
        Demo.pause(1.2)
        Demo.finish()
    }

    // MARK: 9. Parallel reading

    @MainActor
    func testDemo09Parallel() {
        // Opens with the WEB beside the KJV, then reads on through the chapter.
        let app = Genesis.launch(verse: 43_003_001, extra: premium + ["-uiTestingTheme", "paper", "-reader.parallel", "WEB"])
        _ = app.buttons["reader.translation"].waitForExistence(timeout: Genesis.launchTimeout)
        if !app.descendants(matching: .any)["reader.parallel"].waitForExistence(timeout: 4) {
            openParallelMenu(in: app)
            menuItem("reader.parallel.WEB", label: "WEB", in: app).tap()
        }
        Demo.pause(1.5)
        Demo.start("parallel")
        Demo.pause(0.8)
        Demo.drag(app.windows.firstMatch, from: 0.75, to: 0.4, in: app)
        Demo.pause(0.9)
        Demo.drag(app.windows.firstMatch, from: 0.8, to: 0.35, in: app, fast: true)
        Demo.pause(1)
        Demo.drag(app.windows.firstMatch, from: 0.75, to: 0.4, in: app)
        Demo.pause(0.9)
        Demo.drag(app.windows.firstMatch, from: 0.35, to: 0.7, in: app, fast: true)
        Demo.pause(1.4)
        Demo.finish()
    }

    // MARK: 10. Memorize

    @MainActor
    func testDemo10Memorize() {
        // Starts on Home with nothing saved, opens Memorize and adds John 3:16
        // from the suggestions on camera. (Adding it in the reader first and
        // then switching to Home crashed the app on the iOS 27.2 simulator.)
        let app = Genesis.launch(extra: premium + ["-uiTestingTheme", "paper"])
        let card = app.buttons["home.memorise"]
        _ = card.waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.scrollIntoView(card, in: app)
        card.tap()
        let john316 = app.buttons["memorise.suggestion.43003016"]
        _ = john316.waitForExistence(timeout: Genesis.timeout)
        Demo.pause(1)
        Demo.start("memorize")
        Demo.pause(0.6)
        Demo.tap(john316, in: app)
        _ = app.staticTexts["memorise.level"].waitForExistence(timeout: Genesis.timeout)
        Demo.pause(0.8)
        let wordOrder = app.buttons["memorise.game.wordOrder"]
        Genesis.scrollIntoView(wordOrder, in: app)
        Demo.tap(wordOrder, in: app)
        Demo.pause(1)
        // Build the verse word by word.
        let words = "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.".split(separator: " ").map(String.init)
        var index = 0
        var taps = 0
        while index < words.count && taps < 60 {
            taps += 1
            if app.buttons["memorise.game.next"].exists { Demo.tap(app.buttons["memorise.game.next"], in: app); Demo.pause(0.6); continue }
            if app.descendants(matching: .any)["memorise.game.solved"].exists { break }
            let word = words[index]
            let bare = word.trimmingCharacters(in: .punctuationCharacters)
            let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memorise.chip.' AND (label == %@ OR label == %@)", word, bare))
            guard chips.firstMatch.waitForExistence(timeout: 2) else { index += 1; continue }
            Demo.tap(chips.firstMatch, in: app)
            index += 1
            Demo.pause(0.2)
        }
        Demo.pause(2)
        Demo.finish()
    }

    // MARK: 11. Groups and community

    @MainActor
    func testDemo11Groups() {
        // Off camera: a name, and the group made.
        let app = Genesis.launch(extra: premium)
        _ = app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout)
        Genesis.openTab("Together", in: app)
        let field = app.textFields["together.displayName"]
        if field.waitForExistence(timeout: Genesis.timeout) {
            field.tap(); field.typeText("Sam"); app.buttons["together.saveName"].tap()
        }
        _ = app.segmentedControls["together.section"].waitForExistence(timeout: Genesis.timeout)
        let create = app.buttons["groups.create"]
        Genesis.scrollIntoView(create, in: app)
        create.tap()
        if app.buttons["community.acceptGuidelines"].waitForExistence(timeout: 3) { app.buttons["community.acceptGuidelines"].tap() }
        let name = app.textFields["groupForm.name"]
        if name.waitForExistence(timeout: Genesis.timeout) { name.tap(); name.typeText("Thursday Bible Study") }
        app.buttons["groupForm.save"].tap()
        _ = app.buttons["group.markRead"].waitForExistence(timeout: Genesis.timeout)
        Demo.pause(1.5)
        Demo.start("groups")
        Demo.pause(0.6)
        Demo.tap(app.buttons["group.markRead"], in: app)
        Demo.pause(1.4)
        Demo.tap(app.segmentedControls.buttons["Prayer"], in: app)
        Demo.pause(0.8)
        let prayer = app.descendants(matching: .any).matching(identifier: "group.prayerField").firstMatch
        Genesis.scrollIntoView(prayer, in: app)
        Demo.tap(prayer, in: app)
        Demo.type("Please pray for my mom's surgery on Monday", into: prayer)
        Demo.pause(0.5)
        Demo.tap(app.buttons["group.sharePrayer"], in: app)
        Demo.pause(1.2)
        Demo.tap(app.buttons["group.prayed"].firstMatch, in: app)
        Demo.pause(2)
        Demo.finish()
    }

    // MARK: 14–15. A church's sermon in Versely (12 and 13 are filmed in Church Studio on the web)

    @MainActor
    func testDemo14SermonOpens() {
        let app = Genesis.launch(extra: premium)
        _ = app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout)
        Demo.pause(1)
        Demo.start("sermon-open")
        Demo.pause(1)
        Demo.mark("link")
        app.open(URL(string: "versely://sermon/launchday1")!)
        _ = app.staticTexts["churchSermon.title"].waitForExistence(timeout: Genesis.timeout)
        Demo.pause(2)
        Demo.drag(app.windows.firstMatch, from: 0.75, to: 0.4, in: app)
        Demo.pause(1)
        Demo.drag(app.windows.firstMatch, from: 0.75, to: 0.4, in: app, fast: true)
        Demo.pause(1.5)
        Demo.finish()
    }

    @MainActor
    func testDemo15SermonFollow() {
        let app = Genesis.launch(extra: premium)
        _ = app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout)
        app.open(URL(string: "versely://sermon/launchday1")!)
        _ = app.staticTexts["churchSermon.title"].waitForExistence(timeout: Genesis.timeout)
        let passage = app.buttons.matching(identifier: "churchSermon.passage").firstMatch
        Genesis.scrollIntoView(passage, in: app)
        Demo.pause(1.5)
        Demo.start("sermon-follow")
        Demo.pause(0.6)
        // The passage, verbatim from the person's own Bible.
        Demo.tap(passage, in: app)
        Demo.pause(2.4)
        Demo.tap(app.buttons["churchPassage.done"], in: app)
        Demo.pause(0.8)
        // Their own notes, started with the sermon's details.
        let notes = app.buttons["churchSermon.notes"]
        Genesis.scrollIntoView(notes, in: app)
        Demo.tap(notes, in: app)
        Demo.pause(1.2)
        let body = app.descendants(matching: .any).matching(identifier: "sermon.body").firstMatch
        if body.waitForExistence(timeout: 3) {
            Demo.tap(body, in: app)
            Demo.type("Come as I am. He gives rest.", into: body)
        }
        Demo.pause(1.8)
        Demo.finish()
    }

    // MARK: Helpers

    @MainActor
    private func openSection(_ name: String, in app: XCUIApplication) {
        let segment = app.segmentedControls.buttons[name]
        if segment.waitForExistence(timeout: Genesis.timeout) { segment.tap() }
    }

    /// A menu item by its identifier, or by the start of its label: on the
    /// iOS 27.2 simulator a submenu's items lose their identifiers.
    @MainActor
    private func menuItem(_ id: String, label: String, in app: XCUIApplication) -> XCUIElement {
        let byID = app.buttons[id]
        if byID.waitForExistence(timeout: 1.5) { return byID }
        return Genesis.anyElement(startingWith: label, in: app)
    }

    @MainActor
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

    /// A drag up or down the middle of the element (scrolling): slow, or a quicker flick.
    static func drag(_ element: XCUIElement, from start: CGFloat, to end: CGFloat, in app: XCUIApplication, fast: Bool = false) {
        let f = element.frame
        let (x, y) = point(of: CGRect(x: f.midX, y: f.minY + f.height * start, width: 0, height: 0), in: app)
        let (_, y2) = point(of: CGRect(x: f.midX, y: f.minY + f.height * end, width: 0, height: 0), in: app)
        events.append(Event(t: Date().timeIntervalSince1970, kind: "drag", x: x, y: y, x2: x, y2: y2))
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
        let to = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: fast ? .fast : .slow, thenHoldForDuration: fast ? 0 : 0.1)
    }

    /// A drag in any direction across the element (moving a map).
    static func pan(_ element: XCUIElement, from start: CGVector, to end: CGVector, in app: XCUIApplication) {
        let f = element.frame
        let (x, y) = point(of: CGRect(x: f.minX + f.width * start.dx, y: f.minY + f.height * start.dy, width: 0, height: 0), in: app)
        let (x2, y2) = point(of: CGRect(x: f.minX + f.width * end.dx, y: f.minY + f.height * end.dy, width: 0, height: 0), in: app)
        events.append(Event(t: Date().timeIntervalSince1970, kind: "drag", x: x, y: y, x2: x2, y2: y2))
        element.coordinate(withNormalizedOffset: start).press(forDuration: 0.05, thenDragTo: element.coordinate(withNormalizedOffset: end), withVelocity: .slow, thenHoldForDuration: 0.1)
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
