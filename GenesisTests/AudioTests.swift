import Foundation
import Testing
@testable import Genesis

@Suite("Audio Bible")
@MainActor
struct AudioTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AudioTests-\(UUID())")!
    }

    private func makeService(narrator: StubNarrator, defaults: UserDefaults? = nil) -> (AudioPlayerService, AudioSettings) {
        let defaults = defaults ?? freshDefaults()
        let settings = AudioSettings(defaults: defaults)
        let catalog = AudioRecordingCatalog(client: nil, directory: URL.temporaryDirectory.appending(path: "audio-\(UUID())"))
        let service = AudioPlayerService(library: BibleLibrary(defaults: defaults), settings: settings, catalog: catalog, narrator: narrator)
        return (service, settings)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private let john3 = ChapterID(book: 43, chapter: 3)

    @Test func settingsAreRememberedPerTranslation() {
        let defaults = freshDefaults()
        let settings = AudioSettings(defaults: defaults)
        #expect(settings.source(for: .kjv) == .deviceVoice, "Device voice by default")
        settings.setSource(.recording("web-basil-sands"), for: .web)
        settings.speed = 1.5
        let reloaded = AudioSettings(defaults: defaults)
        #expect(reloaded.source(for: .web) == .recording("web-basil-sands"))
        #expect(reloaded.source(for: .kjv) == .deviceVoice)
        #expect(reloaded.speed == 1.5)
        #expect(reloaded.followsAlong)
    }

    @Test func speechRateRisesWithSpeed() {
        let slow = SpeechNarrator.rate(forSpeed: 0.75)
        let normal = SpeechNarrator.rate(forSpeed: 1)
        let fast = SpeechNarrator.rate(forSpeed: 2)
        #expect(slow < normal)
        #expect(normal < fast)
    }

    @Test func readsVersesInOrderAndReportsThem() async {
        let (service, _) = makeService(narrator: StubNarrator(interval: .milliseconds(5)))
        var reported: [VerseID] = []
        service.onPosition = { _, verse in if let verse { reported.append(verse) } }
        service.play(john3, from: VerseID(book: 43, chapter: 3, verse: 34))
        #expect(service.state == .playing)
        await waitUntil { reported.count >= 3 }
        #expect(Array(reported.prefix(3)).map(\.verse) == [34, 35, 36], "Starts at the verse asked for")
    }

    @Test func continuesIntoTheNextChapter() async {
        let (service, _) = makeService(narrator: StubNarrator(interval: .milliseconds(5)))
        service.play(john3, from: VerseID(book: 43, chapter: 3, verse: 35))
        await waitUntil { service.chapter == ChapterID(book: 43, chapter: 4) }
        #expect(service.chapter == ChapterID(book: 43, chapter: 4))
        #expect(service.state == .playing)
        service.stop()
    }

    @Test func endOfChapterTimerPauses() async {
        let (service, _) = makeService(narrator: StubNarrator(interval: .milliseconds(5)))
        service.play(john3, from: VerseID(book: 43, chapter: 3, verse: 35))
        service.setSleepTimer(.endOfChapter)
        await waitUntil { service.state == .paused }
        #expect(service.state == .paused)
        #expect(service.chapter == john3, "Stays on the chapter it finished")
        #expect(service.sleepTimer == nil)
    }

    @Test func pauseResumeAndStop() {
        let (service, _) = makeService(narrator: StubNarrator())
        service.play(john3)
        service.pause()
        #expect(service.state == .paused)
        service.resume()
        #expect(service.state == .playing)
        service.stop()
        #expect(service.state == .idle)
        #expect(service.chapter == nil)
    }

    @Test func withdrawnRecordingFallsBackToTheDeviceVoice() {
        let defaults = freshDefaults()
        let (service, settings) = makeService(narrator: StubNarrator(), defaults: defaults)
        settings.setSource(.recording("gone"), for: .kjv)
        service.play(john3)
        #expect(service.source == .deviceVoice)
        #expect(service.state == .playing)
    }

    @Test func chapterKeys() {
        #expect(AudioRecordingCatalog.key(john3) == "43.3")
    }

    @Test func readerFollowsAndMarksTheVerse() {
        let defaults = freshDefaults()
        let reader = ReaderViewModel(library: BibleLibrary(defaults: defaults), progress: ReadingProgress(defaults: defaults))
        reader.open(ChapterID(book: 1, chapter: 1))
        let verse = VerseID(book: 43, chapter: 3, verse: 16)
        reader.audioMoved(chapter: john3, verse: verse, follow: true)
        #expect(reader.chapterID == john3, "Opens the chapter being read")
        #expect(reader.playingVerse == verse)
        #expect(reader.decorations(for: john3).playing == verse)
        reader.audioMoved(chapter: john3, verse: verse, follow: false)
        #expect(reader.playingVerse == nil, "Nothing is marked without follow-along")
        reader.audioMoved(chapter: nil, verse: nil, follow: true)
        #expect(reader.playingVerse == nil)
    }
}
