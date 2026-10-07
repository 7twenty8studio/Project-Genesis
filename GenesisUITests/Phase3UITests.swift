import XCTest

/// Premium, the study assistant (with canned answers), timeline, maps, people
/// and insights.
final class Phase3UITests: GenesisUITestCase {
    private let john316 = 43_003_016

    @MainActor
    private func launchPremium(verse: Int? = nil) -> XCUIApplication {
        Genesis.launch(verse: verse, extra: ["-uiTestingPremium"])
    }

    /// The study assistant is switched off in release builds for now
    /// (Supabase feature_flags); its tests turn it on.
    @MainActor
    private func launchWithAI(verse: Int, premium: Bool = false) -> XCUIApplication {
        Genesis.launch(verse: verse, extra: ["-uiTestingAI"] + (premium ? ["-uiTestingPremium"] : []))
    }

    @MainActor
    private func openExplore(_ app: XCUIApplication, section: String? = nil) {
        Genesis.openTab("Explore", in: app)
        guard let section else { return }
        let segment = app.segmentedControls.buttons[section]
        XCTAssertTrue(segment.waitForExistence(timeout: Genesis.timeout), "The \(section) section is offered")
        segment.tap()
    }

    // MARK: Premium gates

    @MainActor
    func testExploreIsFreeExceptMaps() {
        let app = Genesis.launch()
        XCTAssertTrue(app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout))
        openExplore(app, section: "Timeline")
        XCTAssertTrue(app.buttons["timeline.era.creation"].waitForExistence(timeout: Genesis.timeout), "Free accounts browse the timeline")
        openExplore(app, section: "Map")
        let unlock = app.buttons["explore.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: Genesis.timeout), "The map is a Premium preview")
        unlock.tap()
        XCTAssertTrue(app.buttons["premium.subscribe"].waitForExistence(timeout: Genesis.timeout), "Unlock opens Premium")
        XCTAssertTrue(app.buttons["premium.restore"].exists, "Restore Purchases is offered")
        // Individual or Family.
        let family = app.segmentedControls.buttons["Family"]
        Genesis.scrollIntoView(family, in: app)
        XCTAssertTrue(family.waitForExistence(timeout: Genesis.timeout), "A Family plan is offered")
        family.tap()
        XCTAssertTrue(Genesis.element(containing: "12.99", in: app).waitForExistence(timeout: Genesis.timeout) || Genesis.element(containing: "99.99", in: app).exists, "…at the Family price")
        Genesis.tapToolbarButton("premium.close", in: app)
        XCTAssertTrue(Genesis.wait { !app.buttons["premium.subscribe"].exists })
    }

    @MainActor
    func testPremiumThemeIsLockedForFreeAccounts() {
        let app = Genesis.launch(verse: john316)
        let settings = app.buttons["reader.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: Genesis.timeout))
        settings.tap()
        // The themes are a sideways row at the top of the sheet.
        XCTAssertTrue(app.buttons["settings.theme.automatic"].waitForExistence(timeout: Genesis.timeout))
        let midnight = app.buttons["settings.theme.midnight"]
        let themes = app.scrollViews.containing(.button, identifier: "settings.theme.automatic").firstMatch
        Genesis.scrollHorizontallyIntoView(midnight, in: themes, in: app)
        XCTAssertTrue(midnight.exists, "Premium themes are shown")
        XCTAssertTrue(midnight.label.contains("Premium"), "…and marked as Premium")
        midnight.tap()
        XCTAssertTrue(app.buttons["premium.subscribe"].waitForExistence(timeout: Genesis.timeout), "Choosing one opens Premium")
    }

    // MARK: Study assistant

    @MainActor
    func testStudyAssistantIsHiddenWhileSwitchedOff() {
        let app = Genesis.launch(verse: john316)
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: Genesis.timeout))
        XCTAssertFalse(app.buttons["reader.study"].exists, "No Study button without the assistant")
        XCTAssertTrue(Genesis.selectVerse(app), "A verse can be selected")
        XCTAssertTrue(app.buttons["selection.done"].waitForExistence(timeout: Genesis.timeout))
        XCTAssertFalse(app.buttons["selection.explain"].exists, "No Explain button without the assistant")
    }

    @MainActor
    func testExplainSelectionShowsScriptureAndLabelledNotes() {
        let app = launchWithAI(verse: john316)
        XCTAssertTrue(Genesis.selectVerse(app), "A verse can be selected")
        let explain = app.buttons["selection.explain"]
        XCTAssertTrue(explain.waitForExistence(timeout: Genesis.timeout), "Explain is offered for a selection")
        explain.tap()

        XCTAssertTrue(app.staticTexts["study.scripture"].waitForExistence(timeout: Genesis.timeout), "The passage is shown from the Bible")
        let label = app.descendants(matching: .any).matching(identifier: "study.aiLabel").firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: Genesis.timeout), "AI notes are labelled")
        XCTAssertTrue(label.label.contains("not Scripture"))
        let answer = app.staticTexts["study.answer"]
        XCTAssertTrue(answer.waitForExistence(timeout: Genesis.timeout), "An answer appears")
        XCTAssertTrue(answer.label.contains("sample"), "The UI tests use canned answers")
    }

    @MainActor
    func testPremiumStudyToolsAreLockedForFreeAccounts() {
        let app = launchWithAI(verse: john316)
        let study = app.buttons["reader.study"]
        XCTAssertTrue(study.waitForExistence(timeout: Genesis.timeout), "The reader offers Study")
        study.tap()
        let questions = app.buttons["study.action.questions"]
        XCTAssertTrue(questions.waitForExistence(timeout: Genesis.timeout))
        XCTAssertTrue(questions.label.contains("Premium"))
        questions.tap()
        XCTAssertTrue(app.buttons["premium.subscribe"].waitForExistence(timeout: Genesis.timeout), "A Premium tool opens Premium")
    }

    @MainActor
    func testPremiumCanUseEveryStudyTool() {
        let app = launchWithAI(verse: john316, premium: true)
        let study = app.buttons["reader.study"]
        XCTAssertTrue(study.waitForExistence(timeout: Genesis.timeout))
        study.tap()
        let questions = app.buttons["study.action.questions"]
        XCTAssertTrue(questions.waitForExistence(timeout: Genesis.timeout))
        questions.tap()
        let answer = app.staticTexts["study.answer"]
        XCTAssertTrue(Genesis.wait { answer.exists && answer.label.contains("discussion") }, "Discussion questions load")
    }

    // MARK: Word study

    @MainActor
    func testWordStudyShowsGreekAndCommentary() {
        let app = launchPremium(verse: john316)
        XCTAssertTrue(Genesis.selectVerse(app), "A verse can be selected")
        let study = app.buttons["selection.wordStudy"]
        XCTAssertTrue(study.waitForExistence(timeout: Genesis.timeout), "Word Study is offered for a selection")
        study.tap()
        let word = app.descendants(matching: .any).matching(identifier: "wordStudy.word").firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: Genesis.timeout), "The original words are listed")
        word.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "lexicon.header").firstMatch.waitForExistence(timeout: Genesis.timeout), "A word opens its Strong's entry")
        app.navigationBars.buttons.firstMatch.tap()
        let commentary = app.segmentedControls.buttons["Commentary"]
        XCTAssertTrue(commentary.waitForExistence(timeout: Genesis.timeout))
        commentary.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wordStudy.commentary").firstMatch.waitForExistence(timeout: Genesis.timeout), "Matthew Henry's commentary on the passage")
    }

    @MainActor
    func testWordStudyPreviewsForFreeAccounts() {
        let app = Genesis.launch(verse: john316)
        XCTAssertTrue(Genesis.selectVerse(app), "A verse can be selected")
        let study = app.buttons["selection.wordStudy"]
        XCTAssertTrue(study.waitForExistence(timeout: Genesis.timeout))
        study.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wordStudy.word").firstMatch.waitForExistence(timeout: Genesis.timeout), "A few words are shown")
        XCTAssertTrue(app.buttons["teaser.unlock"].waitForExistence(timeout: Genesis.timeout), "…and the way to unlock the rest")
    }

    @MainActor
    func testOriginalWordOpensFromOneVerse() {
        let app = launchPremium(verse: john316)
        XCTAssertTrue(Genesis.selectVerse(app), "A verse can be selected")
        let original = app.buttons["selection.originalWord"]
        XCTAssertTrue(original.waitForExistence(timeout: Genesis.timeout), "Original Word is offered for one verse of an English Bible")
        original.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "originalWord.verse").firstMatch.waitForExistence(timeout: Genesis.timeout), "The verse is shown to pick words from")
        let allWords = app.descendants(matching: .any).matching(identifier: "originalWord.allWords").firstMatch
        Genesis.scrollIntoView(allWords, in: app)
        XCTAssertTrue(allWords.waitForExistence(timeout: Genesis.timeout), "Every word of the verse is a tap away")
        allWords.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wordStudy.word").firstMatch.waitForExistence(timeout: Genesis.timeout), "The verse's original words are listed")
    }

    // MARK: Timeline, people, maps

    @MainActor
    func testTimelineEventOpensTheReader() {
        let app = launchPremium()
        XCTAssertTrue(app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout))
        openExplore(app, section: "Timeline")
        let jesus = app.buttons["timeline.era.jesus"]
        XCTAssertTrue(jesus.waitForExistence(timeout: Genesis.timeout), "Eras are listed")
        // The era strip scrolls sideways; later eras start off screen.
        let strip = app.scrollViews.containing(.button, identifier: "timeline.era.creation").firstMatch
        Genesis.scrollHorizontallyIntoView(jesus, in: strip, in: app)
        jesus.tap()
        XCTAssertTrue(Genesis.wait { jesus.isSelected }, "The era is shown on its own")

        let birth = Genesis.button(startingWith: "Birth of Jesus", in: app)
        Genesis.scrollIntoView(birth, in: app)
        XCTAssertTrue(birth.waitForExistence(timeout: Genesis.timeout), "The birth of Jesus is on the timeline")
        birth.tap()
        let title = app.staticTexts["event.title"]
        XCTAssertTrue(title.waitForExistence(timeout: Genesis.timeout))
        XCTAssertEqual(title.label, "Birth of Jesus")

        let luke2 = app.buttons["Luke 2"]
        XCTAssertTrue(luke2.waitForExistence(timeout: Genesis.timeout), "The chapter that tells it is offered")
        luke2.tap()
        XCTAssertTrue(Genesis.wait { Genesis.chapterTitle(app) == "Luke 2" }, "The reader opens at Luke 2")
    }

    @MainActor
    func testPeopleSearchAndFamilyTree() {
        let app = launchPremium()
        XCTAssertTrue(app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout))
        openExplore(app, section: "People")
        let search = Genesis.searchField(in: app)
        XCTAssertTrue(search.exists, "People can be searched")
        search.tap()
        search.typeText("David")
        let david = Genesis.button(startingWith: "David", in: app)
        XCTAssertTrue(david.waitForExistence(timeout: Genesis.timeout))
        david.tap()

        let name = app.staticTexts["person.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Genesis.timeout))
        XCTAssertEqual(name.label, "David")
        let solomon = app.buttons["Solomon"]
        Genesis.scrollIntoView(solomon, in: app)
        XCTAssertTrue(solomon.exists, "The family tree lists Solomon")
        solomon.tap()
        // David's page stays underneath in the navigation stack, so look for Solomon's.
        let solomonPage = app.staticTexts.matching(identifier: "person.name").matching(NSPredicate(format: "label == %@", "Solomon")).firstMatch
        XCTAssertTrue(solomonPage.waitForExistence(timeout: Genesis.timeout), "Relatives open their own page")
    }

    @MainActor
    func testMapShowsPaulsFirstJourney() {
        let app = launchPremium()
        XCTAssertTrue(app.buttons["home.account"].waitForExistence(timeout: Genesis.launchTimeout))
        openExplore(app, section: "Map")
        let journeys = app.buttons["map.journeys"]
        XCTAssertTrue(journeys.waitForExistence(timeout: Genesis.timeout), "Journeys are offered")
        Genesis.openMenu(journeys, expecting: app.buttons["Paul's First Journey"])
        app.buttons["Paul's First Journey"].tap()
        let read = app.buttons["map.readRoute"]
        XCTAssertTrue(read.waitForExistence(timeout: Genesis.timeout), "The journey's passage is offered")
        read.tap()
        XCTAssertTrue(Genesis.wait { Genesis.chapterTitle(app) == "Acts 13" }, "The reader opens at Acts 13")
    }

    // MARK: Insights

    @MainActor
    func testInsightsFromHome() {
        let app = launchPremium(verse: john316)
        XCTAssertTrue(app.buttons["reader.chapterButton"].waitForExistence(timeout: Genesis.launchTimeout))
        Genesis.openTab("Home", in: app)
        let insights = app.buttons["Insights"]
        Genesis.scrollIntoView(insights, in: app, container: app.scrollViews.firstMatch)
        XCTAssertTrue(insights.waitForExistence(timeout: Genesis.timeout), "Progress links to Insights")
        insights.tap()
        let stats = app.descendants(matching: .any).matching(identifier: "insights.stats").firstMatch
        XCTAssertTrue(stats.waitForExistence(timeout: Genesis.timeout))
        XCTAssertTrue(Genesis.element(containing: "longest streak", in: app).exists, "Premium insights are shown")
    }
}
