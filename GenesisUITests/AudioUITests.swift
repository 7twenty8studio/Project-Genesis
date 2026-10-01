import XCTest

/// Listening (the UI tests use a silent narrator that moves through verses
/// on a timer).
final class AudioUITests: GenesisUITestCase {
    @MainActor
    func testListenFollowsAlongIntoTheNextChapter() {
        // John 3:33, four verses before the end of the chapter.
        let app = Genesis.launch(verse: 43_003_033)
        let listen = app.buttons["reader.listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: Genesis.launchTimeout), "The reader offers Listen")
        listen.tap()

        let player = app.descendants(matching: .any).matching(identifier: "audio.player").firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: Genesis.timeout), "The listening bar appears")
        let title = app.staticTexts["audio.title"]
        XCTAssertTrue(Genesis.wait { title.label.hasPrefix("John 3:3") }, "It reads from the page being shown")

        // With follow-along and continue on (the defaults) the reader moves on.
        XCTAssertTrue(Genesis.wait(timeout: 20) { title.label.hasPrefix("John 4") }, "It carries on into John 4")
        XCTAssertTrue(Genesis.wait { Genesis.chapterTitle(app) == "John 4" }, "The reader follows along")

        let playPause = app.buttons["audio.playPause"]
        playPause.tap()
        XCTAssertTrue(Genesis.wait { playPause.value as? String == "Paused" }, "Pause works")
        let paused = title.label
        RunLoop.current.run(until: Date().addingTimeInterval(1.6))
        XCTAssertEqual(title.label, paused, "Nothing moves while paused")

        app.buttons["audio.close"].tap()
        XCTAssertTrue(Genesis.wait { !player.exists }, "Stop closes the listening bar")
    }

    @MainActor
    func testAudioSettingsOfferTheDeviceVoice() {
        let app = Genesis.launch(verse: 43_003_016)
        let listen = app.buttons["reader.listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: Genesis.launchTimeout))
        listen.tap()
        let options = app.buttons["audio.options"]
        XCTAssertTrue(options.waitForExistence(timeout: Genesis.timeout))
        Genesis.openMenu(options, expecting: app.buttons["audio.settings"])
        app.buttons["audio.settings"].tap()
        let done = app.buttons["audio.settings.done"]
        if !done.waitForExistence(timeout: 3) {
            // A menu item tap can be missed while the menu is still opening.
            app.buttons["audio.settings"].firstMatch.tap()
        }
        XCTAssertTrue(done.waitForExistence(timeout: Genesis.timeout), "Audio settings open")
        let deviceVoice = Genesis.element(containing: "Device voice", in: app)
        XCTAssertTrue(deviceVoice.waitForExistence(timeout: Genesis.timeout), "Device voice is offered")
        // Further down the form, which only builds rows as they scroll into view.
        let follow = app.switches["audio.follow"]
        Genesis.scrollIntoView(follow, in: app)
        XCTAssertTrue(follow.exists, "Follow Along can be turned off")
        Genesis.tapToolbarButton("audio.settings.done", in: app)
    }
}
