import XCTest

/// Ambient sounds (Premium). UI tests play nothing: the app uses a silent output.
final class AmbientUITests: GenesisUITestCase {
    private let john316 = 43_003_016

    @MainActor
    private func openAmbient(_ app: XCUIApplication) {
        let settings = app.buttons["reader.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: Genesis.launchTimeout))
        settings.tap()
        let ambient = app.buttons["settings.ambient"]
        XCTAssertTrue(ambient.waitForExistence(timeout: Genesis.timeout), "Ambient Sounds is in the reading settings")
        ambient.tap()
    }

    @MainActor
    func testAmbientSoundsAreLockedForFreeAccounts() {
        let app = Genesis.launch(verse: john316)
        openAmbient(app)
        XCTAssertTrue(app.buttons["premium.subscribe"].waitForExistence(timeout: Genesis.timeout), "Free accounts are offered Premium")
    }

    @MainActor
    func testMixAmbientSounds() {
        let app = Genesis.launch(verse: john316, extra: ["-uiTestingPremium"])
        openAmbient(app)

        let rain = app.buttons["ambient.sound.rain"]
        XCTAssertTrue(rain.waitForExistence(timeout: Genesis.timeout), "The sounds are listed")
        rain.tap()
        let status = app.staticTexts["ambient.status"]
        XCTAssertTrue(Genesis.wait { status.label == "Playing" }, "Choosing a sound plays it")
        XCTAssertTrue(app.sliders["ambient.volume.rain"].waitForExistence(timeout: Genesis.timeout), "A chosen sound has a volume")

        let fireside = app.buttons["ambient.mix.fireside"]
        for _ in 0..<4 where !(fireside.exists && fireside.isHittable) {
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(fireside.waitForExistence(timeout: Genesis.timeout), "Ready-made mixes are offered")
        fireside.tap()
        XCTAssertTrue(Genesis.wait { app.buttons["ambient.sound.fireplace"].isSelected }, "A mix chooses its sounds")

        let playPause = app.buttons["ambient.playPause"]
        for _ in 0..<4 where !(playPause.exists && playPause.isHittable) {
            app.collectionViews.firstMatch.swipeDown()
        }
        playPause.tap()
        XCTAssertTrue(Genesis.wait { status.label == "Paused" }, "Sounds can be paused")
        playPause.tap()
        XCTAssertTrue(Genesis.wait { status.label == "Playing" })

        // Back in the reader, a small bar keeps the sounds within reach.
        app.navigationBars.buttons.firstMatch.tap() // back to Reading
        Genesis.tapToolbarButton("settings.done", in: app)
        Genesis.showControls(app)
        let bar = app.buttons["ambient.bar"]
        XCTAssertTrue(bar.waitForExistence(timeout: Genesis.timeout), "The reader shows what's playing")
        app.buttons["ambient.bar.close"].tap()
        XCTAssertTrue(Genesis.wait { !bar.exists }, "Closing stops the sounds and the bar")
    }
}
