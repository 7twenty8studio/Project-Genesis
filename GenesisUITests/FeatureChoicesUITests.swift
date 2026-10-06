import XCTest

/// Choosing features, topic search, the Bibles screen and side panels.
final class FeatureChoicesUITests: GenesisUITestCase {
    @MainActor
    func testTurningListenOffHidesItInTheReader() {
        let app = Genesis.launch(verse: 43_003_016)
        XCTAssertTrue(app.buttons["reader.listen"].waitForExistence(timeout: Genesis.launchTimeout), "Listen starts on")

        Genesis.openTab("Home", in: app)
        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: Genesis.timeout))
        settings.tap()
        let features = app.buttons["settings.features"]
        XCTAssertTrue(features.waitForExistence(timeout: Genesis.timeout))
        features.tap()
        let listen = app.switches["features.toggle.listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: Genesis.timeout), "Each feature has a switch")
        listen.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(Genesis.wait { (listen.value as? String) == "0" }, "Listen is switched off")
        // Back to Settings, whose Done button closes the sheet.
        let back = app.buttons["BackButton"].firstMatch
        if back.exists { back.tap() } else { app.navigationBars.buttons.firstMatch.tap() }
        Genesis.tapToolbarButton("appSettings.done", in: app)

        Genesis.openTab("Read", in: app)
        Genesis.showControls(app)
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: Genesis.timeout))
        XCTAssertFalse(app.buttons["reader.listen"].exists, "The headphones are gone")
    }

    @MainActor
    func testSimpleModeShowsJustTheEssentials() {
        let app = Genesis.launch(extra: ["-uiTestingSimple"])
        XCTAssertTrue(app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout))
        XCTAssertFalse(app.tabBars.buttons["Explore"].exists, "No Explore tab")
        XCTAssertFalse(app.tabBars.buttons["Together"].exists, "No Together tab")
        XCTAssertFalse(Genesis.element(containing: "Prayer Journal", in: app).exists, "No prayer journal on Home")
    }

    @MainActor
    func testSearchByTopic() {
        // Topic search is part of Premium's advanced search.
        let app = Genesis.launch(extra: ["-uiTestingPremium"])
        XCTAssertTrue(app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout))
        Genesis.openTab("Search", in: app)
        let field = Genesis.searchField(in: app)
        XCTAssertTrue(field.exists)
        field.tap()
        field.typeText("forgiveness")
        let topic = app.buttons.matching(identifier: "search.topic").firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: Genesis.timeout), "Topics are found")
        topic.tap()
        let passage = app.buttons.matching(identifier: "topic.passage").firstMatch
        XCTAssertTrue(passage.waitForExistence(timeout: Genesis.timeout), "The topic lists passages")
        // The first heading ("Of enemies"); later ones are further down the list.
        XCTAssertTrue(Genesis.wait { Genesis.element(containing: "Of Enemies", in: app).exists || Genesis.element(containing: "OF ENEMIES", in: app).exists }, "…under headings")
    }

    @MainActor
    func testBiblesScreenListsBundledTranslations() {
        let app = Genesis.launch(verse: 43_003_016)
        let translation = app.buttons["reader.translation"]
        XCTAssertTrue(translation.waitForExistence(timeout: Genesis.launchTimeout))
        Genesis.openMenu(translation, expecting: app.buttons["reader.moreBibles"])
        app.buttons["reader.moreBibles"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bibles.installed.KJV").firstMatch.waitForExistence(timeout: Genesis.timeout), "Bundled Bibles are listed")
        // Each Bible says what it's like.
        let facts = app.descendants(matching: .any).matching(identifier: "bibles.facts.KJV").firstMatch
        XCTAssertTrue(facts.waitForExistence(timeout: Genesis.timeout), "The KJV's details are shown")
        XCTAssertTrue(facts.label.contains("Word for word") && facts.label.contains("Traditional language"), "How it's translated and how it reads: \(facts.label)")

        // The guide places them and suggests one for each way of reading.
        app.buttons["bibles.guide"].tap()
        let suggestion = app.descendants(matching: .any).matching(identifier: "guide.suggestion.KJV").firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: Genesis.timeout), "The KJV for reading aloud")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "guide.suggestion.WEB").firstMatch.exists, "The WEB for study and everyday reading")
        let spectrum = app.descendants(matching: .any).matching(identifier: "guide.spectrum").firstMatch
        Genesis.scrollIntoView(spectrum, in: app)
        XCTAssertTrue(spectrum.exists, "The guide shows where each Bible sits")
        Genesis.tapToolbarButton("guide.done", in: app)

        // Reading another Bible from its card.
        let readWEB = app.buttons["bibles.read.WEB"]
        Genesis.scrollIntoView(readWEB, in: app)
        XCTAssertTrue(readWEB.waitForExistence(timeout: Genesis.timeout), "Another Bible on the device can be opened")
        readWEB.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bibles.current.WEB").firstMatch.waitForExistence(timeout: Genesis.timeout), "The WEB is now the one being read")

        let offline = Genesis.element(containing: "Connect to the internet", in: app)
        Genesis.scrollIntoView(offline, in: app)
        XCTAssertTrue(offline.waitForExistence(timeout: Genesis.timeout), "No catalog without a server")
        Genesis.tapToolbarButton("bibles.done", in: app)
    }
}

/// Parallel Bibles and verse images.
final class ReadAndShareUITests: GenesisUITestCase {
    @MainActor
    func testReadTwoBiblesInParallel() {
        let app = Genesis.launch(verse: 43_003_016)
        let translation = app.buttons["reader.translation"]
        XCTAssertTrue(translation.waitForExistence(timeout: Genesis.launchTimeout))
        Genesis.openMenu(translation, expecting: app.buttons["reader.parallelMenu"])
        app.buttons["reader.parallelMenu"].tap()
        let web = app.buttons["reader.parallel.WEB"]
        XCTAssertTrue(web.waitForExistence(timeout: Genesis.timeout), "The other Bibles are offered")
        web.tap()
        let header = app.descendants(matching: .any)["reader.parallel"]
        XCTAssertTrue(header.waitForExistence(timeout: Genesis.timeout), "Two Bibles are shown side by side")
        XCTAssertTrue(Genesis.element(containing: "There was a man of the Pharisees", in: app).waitForExistence(timeout: Genesis.timeout), "The KJV is there")

        // Turning it off again.
        Genesis.showControls(app)
        Genesis.openMenu(app.buttons["reader.translation"], expecting: app.buttons["reader.parallelMenu"])
        app.buttons["reader.parallelMenu"].tap()
        let off = app.buttons["reader.parallel.off"]
        XCTAssertTrue(off.waitForExistence(timeout: Genesis.timeout))
        off.tap()
        XCTAssertTrue(Genesis.wait { !header.exists }, "Back to one Bible")
    }

    @MainActor
    func testMakeAVerseImage() {
        let app = Genesis.launch(verse: 43_003_016)
        XCTAssertTrue(Genesis.readerText(app).waitForExistence(timeout: Genesis.launchTimeout))
        XCTAssertTrue(Genesis.selectVerse(app), "A verse can be selected")
        let image = app.buttons["selection.image"]
        XCTAssertTrue(image.waitForExistence(timeout: Genesis.timeout))
        image.tap()
        XCTAssertTrue(app.buttons["verseImage.style.autumn"].waitForExistence(timeout: Genesis.timeout), "Backgrounds are offered")
        app.buttons["verseImage.style.autumn"].tap()
        XCTAssertTrue(app.buttons["verseImage.share"].waitForExistence(timeout: Genesis.timeout), "The image can be shared")
    }
}
