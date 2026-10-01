import AVFoundation
import Foundation

/// Reads a chapter aloud verse by verse and reports which verse it's on, so
/// the reader can follow along.
@MainActor
protocol VerseNarrator: AnyObject {
    /// Called as each verse starts.
    var onVerse: ((VerseID) -> Void)? { get set }
    /// Called when the last verse has been read (not when stopped).
    var onFinish: (() -> Void)? { get set }

    func read(_ chapter: Chapter, from verse: VerseID?, speed: Double, voiceIdentifier: String?)
    func pause()
    func resume()
    func stop()
}

/// Reads with the device's built-in voices (AVSpeechSynthesizer). Works
/// offline in every translation. The words come straight from the Bible
/// database; nothing is rewritten.
@MainActor
final class SpeechNarrator: NSObject, VerseNarrator {
    var onVerse: ((VerseID) -> Void)?
    var onFinish: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    /// Which verse each queued utterance reads (nil for the chapter title).
    private var verseByUtterance: [ObjectIdentifier: VerseID] = [:]
    private var lastUtterance: ObjectIdentifier?
    /// Every utterance of this and recent chapters, kept alive so a late
    /// callback from a stopped one can never match a new one at the same address.
    private var queued: [AVSpeechUtterance] = []

    override init() {
        super.init()
        synthesizer.delegate = self
        // Play through our own audio session (set up by AudioPlayerService),
        // so reading continues in the background and on the lock screen.
        synthesizer.usesApplicationAudioSession = true
    }

    func read(_ chapter: Chapter, from verse: VerseID?, speed: Double, voiceIdentifier: String?) {
        stop()
        let voice = voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? AVSpeechSynthesisVoice(language: "en-US")
        let rate = Self.rate(forSpeed: speed)

        func enqueue(_ text: String, verse: VerseID?, pauseAfter: TimeInterval) {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = rate
            utterance.postUtteranceDelay = pauseAfter / max(speed, 0.5)
            if let verse { verseByUtterance[ObjectIdentifier(utterance)] = verse }
            lastUtterance = ObjectIdentifier(utterance)
            queued.append(utterance)
            synthesizer.speak(utterance)
        }

        let start = verse.flatMap { wanted in chapter.verses.first { $0.id >= wanted } }?.id ?? chapter.verses.first?.id
        if start == chapter.verses.first?.id {
            enqueue("\(chapter.id.bibleBook.name), chapter \(chapter.id.chapter).", verse: nil, pauseAfter: 0.6)
        }
        for item in chapter.verses where start.map({ item.id >= $0 }) ?? true {
            enqueue(item.plainText, verse: item.id, pauseAfter: item.startsParagraph ? 0.35 : 0.15)
        }
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    func stop() {
        verseByUtterance.removeAll()
        lastUtterance = nil
        // Keep the last chapter or two alive; drop older ones.
        if queued.count > 600 { queued.removeFirst(queued.count - 600) }
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// Maps 0.5×–2× onto AVSpeech's rate range around its natural default.
    nonisolated static func rate(forSpeed speed: Double) -> Float {
        let base = Double(AVSpeechUtteranceDefaultSpeechRate)
        let value = speed >= 1
            ? base + (Double(AVSpeechUtteranceMaximumSpeechRate) - base) * (speed - 1) * 0.35
            : base - (base - Double(AVSpeechUtteranceMinimumSpeechRate)) * (1 - speed)
        return Float(min(max(value, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
    }

    fileprivate func didStart(_ id: ObjectIdentifier) {
        if let verse = verseByUtterance[id] { onVerse?(verse) }
    }

    fileprivate func didFinish(_ id: ObjectIdentifier) {
        verseByUtterance[id] = nil
        if id == lastUtterance {
            lastUtterance = nil
            onFinish?()
        }
    }
}

extension SpeechNarrator: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.didStart(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.didFinish(id) }
    }
}

/// UI tests: moves through the verses on a quick timer without making a
/// sound, so tests are fast, silent and repeatable.
@MainActor
final class StubNarrator: VerseNarrator {
    var onVerse: ((VerseID) -> Void)?
    var onFinish: (() -> Void)?

    private var queue: [VerseID] = []
    private var task: Task<Void, Never>?
    private var isPaused = false
    private let interval: Duration

    init(interval: Duration = .milliseconds(700)) {
        self.interval = interval
    }

    func read(_ chapter: Chapter, from verse: VerseID?, speed: Double, voiceIdentifier: String?) {
        stop()
        queue = chapter.verses.map(\.id).filter { id in verse.map { id >= $0 } ?? true }
        isPaused = false
        advance()
    }

    func pause() {
        isPaused = true
        task?.cancel()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        advance()
    }

    func stop() {
        task?.cancel()
        task = nil
        queue = []
    }

    private func advance() {
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                guard !self.queue.isEmpty else {
                    self.onFinish?()
                    return
                }
                self.onVerse?(self.queue.removeFirst())
                try? await Task.sleep(for: self.interval)
            }
        }
    }
}
