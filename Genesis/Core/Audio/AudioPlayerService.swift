import AVFoundation
import Foundation

/// Listening to the Bible: device voices (verse by verse, with the reader
/// following along) or a recorded narration, chapter after chapter, with lock
/// screen controls and a sleep timer. Free for everyone.
@MainActor
@Observable
final class AudioPlayerService {
    enum State: Equatable {
        case idle, loading, playing, paused
    }

    enum SleepTimer: Equatable, Hashable {
        case minutes(Int)
        case endOfChapter

        var title: String {
            switch self {
            case let .minutes(minutes): String(localized: "\(minutes) minutes")
            case .endOfChapter: String(localized: "End of chapter")
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var chapter: ChapterID?
    /// The verse being read (device voices only).
    private(set) var verse: VerseID?
    private(set) var source: AudioSource = .deviceVoice
    private(set) var translation: Translation = .kjv
    /// Recorded narration progress, in seconds.
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var errorMessage: String?
    private(set) var sleepTimer: SleepTimer?
    private(set) var sleepEndsAt: Date?

    var isActive: Bool { state != .idle }
    var isPlaying: Bool { state == .playing }

    @ObservationIgnored let settings: AudioSettings
    @ObservationIgnored let catalog: AudioRecordingCatalog
    @ObservationIgnored private let library: BibleLibrary
    @ObservationIgnored private let narrator: VerseNarrator
    @ObservationIgnored private let recordingPlayer = RecordingPlayer()
    @ObservationIgnored private let nowPlaying = NowPlayingController()
    /// The Lock Screen Live Activity (Premium; the app sets `isAllowed`).
    @ObservationIgnored let liveActivity = ListeningActivityController()
    /// Verses per chapter, by translation (numbering differs between Bibles).
    @ObservationIgnored private var verseCounts: [String: Int] = [:]
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Told about each chapter and verse so the reader can follow along;
    /// (nil, nil) when listening stops.
    @ObservationIgnored var onPosition: ((ChapterID?, VerseID?) -> Void)?
    @ObservationIgnored private var pausedByInterruption = false
    /// Set when what's queued no longer matches (the chapter ended, or speed
    /// or position changed while paused); resuming starts afresh.
    @ObservationIgnored private var restartOnResume = false

    init(library: BibleLibrary, settings: AudioSettings, catalog: AudioRecordingCatalog, narrator: VerseNarrator) {
        self.library = library
        self.settings = settings
        self.catalog = catalog
        self.narrator = narrator

        narrator.onVerse = { [weak self] verse in self?.narratorReached(verse) }
        narrator.onFinish = { [weak self] in self?.chapterFinished() }
        recordingPlayer.onFinish = { [weak self] in self?.chapterFinished() }
        recordingPlayer.onFailure = { [weak self] message in self?.fail(message) }
        recordingPlayer.onProgress = { [weak self] elapsed, duration in
            guard let self else { return }
            self.elapsed = elapsed
            self.duration = duration
        }

        // Buttons on the Live Activity.
        ListeningControl.toggle = { [weak self] in
            guard let self, self.isActive else { return }
            self.togglePlayback()
        }
        ListeningControl.next = { [weak self] in self?.nextChapter() }
        liveActivity.endStale()

        // Read the device's voice list in the background now, so starting to
        // listen never waits for it; read it again when voices change.
        VoiceList.preload("en", AppLanguage.code)
        _ = NotificationCenter.default.addObserver(forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: nil) { _ in
            VoiceList.reset()
        }
    }

    // MARK: Playing

    /// Starts reading a chapter, from a verse when the device voice reads.
    func play(_ chapter: ChapterID, from verse: VerseID? = nil) {
        configureRemoteControls()
        loadTask?.cancel()
        narrator.stop()
        recordingPlayer.stop()
        errorMessage = nil
        restartOnResume = false
        translation = library.currentTranslation
        source = resolvedSource()
        self.chapter = chapter
        self.verse = nil
        elapsed = 0
        duration = 0
        nowPlaying.activateSession()

        switch source {
        case .deviceVoice:
            guard let text = try? library.current.chapter(chapter) else {
                fail(String(localized: "This chapter couldn't be loaded."))
                return
            }
            state = .playing
            onPosition?(chapter, nil)
            narrator.read(text, from: verse, speed: settings.speed, voiceIdentifier: settings.voiceIdentifier, language: translation.language)
        case let .recording(id):
            guard let recording = catalog.recording(id: id) else {
                // The recording was withdrawn: fall back to the device voice.
                settings.setSource(.deviceVoice, for: translation)
                play(chapter, from: verse)
                return
            }
            state = .loading
            onPosition?(chapter, nil)
            loadTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let url = try await self.catalog.url(for: chapter, in: recording)
                    guard !Task.isCancelled, self.chapter == chapter else { return }
                    self.recordingPlayer.play(url: url, speed: self.settings.speed)
                    // Paused while it was loading: stay paused, ready to go.
                    if self.state == .paused {
                        self.recordingPlayer.pause()
                    } else {
                        self.state = .playing
                    }
                    self.updateNowPlaying()
                } catch {
                    guard !Task.isCancelled else { return }
                    self.fail(error.localizedDescription)
                }
            }
        }
        updateNowPlaying()
    }

    func pause() {
        guard state == .playing || state == .loading else { return }
        pausedByInterruption = false
        switch source {
        case .deviceVoice: narrator.pause()
        case .recording: recordingPlayer.pause()
        }
        state = .paused
        updateNowPlaying()
    }

    func resume() {
        guard state == .paused, let chapter else { return }
        // After an error, or with a different translation or source since
        // pausing, start the chapter afresh.
        if restartOnResume || errorMessage != nil || library.currentTranslation != translation || resolvedSource() != source {
            play(chapter, from: verse)
            return
        }
        nowPlaying.activateSession()
        switch source {
        case .deviceVoice: narrator.resume()
        case .recording: recordingPlayer.resume()
        }
        state = .playing
        updateNowPlaying()
    }

    func togglePlayback() {
        state == .playing ? pause() : resume()
    }

    func stop() {
        loadTask?.cancel()
        narrator.stop()
        recordingPlayer.stop()
        cancelSleepTimer()
        state = .idle
        chapter = nil
        verse = nil
        errorMessage = nil
        nowPlaying.clear()
        nowPlaying.deactivateSession()
        liveActivity.end()
        onPosition?(nil, nil)
    }

    func nextChapter() {
        guard let next = chapter?.next else { return }
        play(next)
    }

    func previousChapter() {
        guard let chapter else { return }
        // Like a music player: back to the start, or the previous chapter if
        // we've barely begun.
        let barelyStarted = source == .deviceVoice
            ? (verse.map { $0.verse <= 2 } ?? true)
            : elapsed < 5
        if barelyStarted, let previous = chapter.previous {
            play(previous)
        } else {
            play(chapter)
        }
    }

    /// Skips within a recording (seconds), or by verses with the device voice.
    func skip(forward: Bool) {
        switch source {
        case .recording:
            recordingPlayer.skip(by: forward ? 15 : -15)
        case .deviceVoice:
            guard let chapter, let current = verse,
                  let verses = try? library.current.chapter(chapter).verses.map(\.id),
                  let index = verses.firstIndex(of: current) else { return }
            let target = verses[min(max(index + (forward ? 1 : -1), 0), verses.count - 1)]
            if state == .paused {
                // Move without speaking; Play picks up from here.
                verse = target
                restartOnResume = true
                onPosition?(chapter, target)
                updateNowPlaying()
            } else {
                play(chapter, from: target)
            }
        }
    }

    func seek(to seconds: Double) {
        guard case .recording = source else { return }
        recordingPlayer.seek(to: seconds)
    }

    func setSpeed(_ speed: Double) {
        settings.speed = speed
        switch source {
        case .recording:
            recordingPlayer.setSpeed(speed)
        case .deviceVoice:
            // Speech can't change speed mid-sentence; pick up from this verse.
            if state == .playing, let chapter {
                play(chapter, from: verse)
            } else if state == .paused {
                restartOnResume = true
            }
        }
        updateNowPlaying()
    }

    /// Applies a new voice or source right away if something is playing.
    func settingsChanged() {
        guard state == .playing || state == .paused, let chapter else { return }
        if state == .paused {
            restartOnResume = true
        } else {
            play(chapter, from: verse)
        }
    }

    // MARK: Sleep timer

    func setSleepTimer(_ timer: SleepTimer?) {
        cancelSleepTimer()
        sleepTimer = timer
        guard case let .minutes(minutes) = timer else { return }
        let end = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
        sleepEndsAt = end
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled, let self else { return }
            self.pause()
            self.sleepTimer = nil
            self.sleepEndsAt = nil
        }
    }

    private func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimer = nil
        sleepEndsAt = nil
    }

    // MARK: Events

    private func narratorReached(_ verse: VerseID) {
        guard state != .idle, verse.chapterID == chapter else { return }
        self.verse = verse
        onPosition?(verse.chapterID, verse)
        updateNowPlaying()
    }

    private func chapterFinished() {
        guard state == .playing, let chapter else { return }
        if sleepTimer == .endOfChapter {
            cancelSleepTimer()
            verse = nil
            state = .paused
            restartOnResume = true
            updateNowPlaying()
            return
        }
        guard settings.continuesToNextChapter, let next = chapter.next else {
            verse = nil
            state = .paused
            restartOnResume = true
            updateNowPlaying()
            return
        }
        play(next)
    }

    private func fail(_ message: String) {
        narrator.stop()
        recordingPlayer.stop()
        errorMessage = message
        state = .paused
        updateNowPlaying()
    }

    // MARK: Helpers

    private func resolvedSource() -> AudioSource {
        let chosen = settings.source(for: library.currentTranslation)
        if case let .recording(id) = chosen, catalog.recording(id: id) == nil { return .deviceVoice }
        return chosen
    }

    var isRecording: Bool {
        if case .recording = source { return true }
        return false
    }

    var sourceTitle: String {
        switch source {
        case .deviceVoice: return String(localized: "\(translation.abbreviation) · Device voice")
        case let .recording(id):
            let title = catalog.recording(id: id)?.title ?? String(localized: "Recording", comment: "Fallback name for a recorded narration")
            return "\(translation.abbreviation) · \(title)"
        }
    }

    private func updateNowPlaying() {
        guard let chapter else { return }
        let title = verse.map { "\(chapter.description(in: translation.language)):\($0.verse)" } ?? chapter.description(in: translation.language)
        let recording = isRecording
        nowPlaying.update(
            title: title,
            subtitle: sourceTitle,
            isPlaying: state == .playing,
            speed: settings.speed,
            elapsed: recording ? elapsed : nil,
            duration: recording ? duration : nil
        )
        updateLiveActivity(title: title)
    }

    /// The verse being read, verbatim, on the Lock Screen.
    private func updateLiveActivity(title: String) {
        guard let chapter else { return }
        let repository = library.repository(for: translation)
        var text: String?
        var progress: Double?
        if let verse {
            text = (try? repository.verse(verse))?.plainText
            let key = "\(translation.id)-\(chapter.book)-\(chapter.chapter)"
            let count = verseCounts[key] ?? (try? repository.verseCount(in: chapter)) ?? 0
            verseCounts[key] = count
            if count > 0 { progress = Double(verse.verse) / Double(count) }
        } else if isRecording, duration > 0 {
            progress = elapsed / duration
        }
        liveActivity.show(
            .init(reference: title, verseText: text, isPlaying: state == .playing || state == .loading, progress: progress),
            translation: translation.abbreviation
        )
    }

    private func configureRemoteControls() {
        nowPlaying.configure(
            NowPlayingController.Actions(
                play: { [weak self] in Task { @MainActor in self?.resume() } },
                pause: { [weak self] in Task { @MainActor in self?.pause() } },
                toggle: { [weak self] in Task { @MainActor in self?.togglePlayback() } },
                next: { [weak self] in Task { @MainActor in self?.nextChapter() } },
                previous: { [weak self] in Task { @MainActor in self?.previousChapter() } }
            ),
            onInterruption: { [weak self] began, shouldResume in
                guard let self else { return }
                if began {
                    if self.state == .playing {
                        self.pause()
                        self.pausedByInterruption = true
                    }
                } else {
                    // Only pick up again if the interruption paused us, not the person.
                    if shouldResume, self.pausedByInterruption, self.state == .paused { self.resume() }
                    self.pausedByInterruption = false
                }
            }
        )
    }
}
