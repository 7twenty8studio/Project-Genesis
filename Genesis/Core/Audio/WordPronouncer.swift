import AVFoundation
import Foundation

/// Says a Hebrew or Greek word aloud with the device's Hebrew or Greek voice
/// (modern Israeli and modern Greek pronunciation), a little slowly, so
/// readers can hear how it sounds. Only the spoken copy is simplified
/// (`PronunciationText`); the word shown is never changed. Free, offline.
/// UI tests use a silent one (`isSilent`).
@MainActor
@Observable
final class WordPronouncer {
    /// The word being said (as passed to `say`), or nil.
    private(set) var speaking: String?
    /// Set when the device has no voice for the language asked for.
    private(set) var missingVoice: OriginalLanguage?

    @ObservationIgnored private let isSilent: Bool
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let delegate = Delegate()
    @ObservationIgnored private var current: ObjectIdentifier?
    @ObservationIgnored private var silentTask: Task<Void, Never>?

    init(isSilent: Bool = false) {
        self.isSilent = isSilent
        synthesizer.usesApplicationAudioSession = true
        synthesizer.delegate = delegate
        delegate.onEnd = { [weak self] id in self?.finished(id) }
    }

    func isSpeaking(_ word: String) -> Bool {
        speaking == word
    }

    /// Says the word, stopping any word already being said.
    func say(_ word: String, language: OriginalLanguage) {
        stop()
        let text = PronunciationText.spoken(word, language: language)
        guard !text.isEmpty else { return }
        if isSilent {
            speaking = word
            silentTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                self?.speaking = nil
            }
            return
        }
        guard let voice = Self.voice(for: language) else {
            missingVoice = language
            return
        }
        missingVoice = nil
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.8
        AudioSession.begin(.pronunciation)
        current = ObjectIdentifier(utterance)
        speaking = word
        synthesizer.speak(utterance)
    }

    func stop() {
        silentTask?.cancel()
        silentTask = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if current != nil {
            current = nil
            AudioSession.end(.pronunciation)
        }
        speaking = nil
    }

    /// Loads the device's Hebrew and Greek voices in the background, so the
    /// best one is used from the first word.
    static func preloadVoices() {
        VoiceList.preload(OriginalLanguage.hebrew.speechLanguage, OriginalLanguage.greek.speechLanguage)
    }

    /// The best voice installed for the language, or its standard voice;
    /// nil when the device has neither.
    static func voice(for language: OriginalLanguage) -> AVSpeechSynthesisVoice? {
        let code = language.speechLanguage
        if let best = VoiceList.cachedIdentifiers(language: code)?.first.flatMap(AVSpeechSynthesisVoice.init(identifier:)) {
            return best
        }
        VoiceList.preload(code)
        return AVSpeechSynthesisVoice(language: language == .hebrew ? "he-IL" : "el-GR")
    }

    private func finished(_ id: ObjectIdentifier) {
        guard id == current else { return }
        current = nil
        speaking = nil
        AudioSession.end(.pronunciation)
    }

    @MainActor
    private final class Delegate: NSObject, AVSpeechSynthesizerDelegate {
        var onEnd: ((ObjectIdentifier) -> Void)?

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            let id = ObjectIdentifier(utterance)
            Task { @MainActor [weak self] in self?.onEnd?(id) }
        }

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            let id = ObjectIdentifier(utterance)
            Task { @MainActor [weak self] in self?.onEnd?(id) }
        }
    }
}

extension OriginalLanguage {
    /// The language code of the device voices that read it.
    var speechLanguage: String {
        switch self {
        case .hebrew: "he"
        case .greek: "el"
        }
    }
}

/// The copy of a Hebrew or Greek word handed to the speech voice. The word
/// on screen stays exactly as the source writes it; the voice gets it
/// without the marks a modern voice can't read:
/// - Hebrew keeps its letters and vowel points, and drops the cantillation
///   accents, meteg and punctuation (a maqaf becomes a space).
/// - Greek becomes monotonic: breathings and iota subscripts dropped, grave
///   and circumflex written as the acute, punctuation dropped.
enum PronunciationText {
    static func spoken(_ word: String, language: OriginalLanguage) -> String {
        let text = switch language {
        case .hebrew: hebrew(word)
        case .greek: greek(word)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func hebrew(_ word: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in word.unicodeScalars {
            switch scalar.value {
            case 0x0591...0x05AF, 0x05BD: continue // cantillation, meteg
            case 0x05BE: scalars.append(" ") // maqaf
            default:
                if scalar.properties.generalCategory.isPunctuation { continue }
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private static func greek(_ word: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in word.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.value {
            case 0x0313, 0x0314, 0x0345, 0x0304, 0x0306: continue // breathings, iota subscript, macron, breve
            case 0x0300, 0x0342: scalars.append("\u{0301}") // grave, circumflex → acute
            default:
                if scalar.properties.generalCategory.isPunctuation { continue }
                scalars.append(scalar)
            }
        }
        return String(scalars).precomposedStringWithCanonicalMapping
    }
}

private extension Unicode.GeneralCategory {
    var isPunctuation: Bool {
        switch self {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            true
        default:
            false
        }
    }
}
