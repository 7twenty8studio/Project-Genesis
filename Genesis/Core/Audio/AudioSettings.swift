import AVFoundation
import Foundation

/// Where narration comes from.
enum AudioSource: Hashable, Sendable {
    /// The device's built-in voices read the text, verse by verse.
    case deviceVoice
    /// A recorded human narration (an `AudioRecording` id).
    case recording(String)
}

/// Listening preferences, kept on this device.
@MainActor
@Observable
final class AudioSettings {
    /// Playback speed, 0.5× to 2×.
    var speed: Double {
        didSet { defaults.set(speed, forKey: Keys.speed) }
    }
    /// The device voice to use, or nil for the system's default English voice.
    var voiceIdentifier: String? {
        didSet { defaults.set(voiceIdentifier, forKey: Keys.voice) }
    }
    /// Turn pages and highlight the verse being read.
    var followsAlong: Bool {
        didSet { defaults.set(followsAlong, forKey: Keys.follow) }
    }
    /// Carry on into the next chapter.
    var continuesToNextChapter: Bool {
        didSet { defaults.set(continuesToNextChapter, forKey: Keys.continues) }
    }
    /// The chosen recording per translation id; device voice when absent.
    private var recordingByTranslation: [String: String] {
        didSet { defaults.set(recordingByTranslation, forKey: Keys.recordings) }
    }

    static let speeds: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let speed = "audio.speed"
        static let voice = "audio.voice"
        static let follow = "audio.followsAlong"
        static let continues = "audio.continues"
        static let recordings = "audio.recordings"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedSpeed = defaults.double(forKey: Keys.speed)
        speed = savedSpeed > 0 ? min(max(savedSpeed, 0.5), 2) : 1
        voiceIdentifier = defaults.string(forKey: Keys.voice)
        followsAlong = defaults.object(forKey: Keys.follow) as? Bool ?? true
        continuesToNextChapter = defaults.object(forKey: Keys.continues) as? Bool ?? true
        recordingByTranslation = defaults.dictionary(forKey: Keys.recordings) as? [String: String] ?? [:]
    }

    func source(for translation: Translation) -> AudioSource {
        recordingByTranslation[translation.id].map(AudioSource.recording) ?? .deviceVoice
    }

    func setSource(_ source: AudioSource, for translation: Translation) {
        switch source {
        case .deviceVoice: recordingByTranslation[translation.id] = nil
        case let .recording(id): recordingByTranslation[translation.id] = id
        }
    }
}

/// A device voice the person can choose.
struct NarrationVoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let language: String
    /// "Enhanced" and "Premium" voices sound much more natural; people can
    /// download them in Settings › Accessibility › Spoken Content › Voices.
    let qualityLabel: String?

    /// Voices in a language suited to reading Scripture, best first. Leaves out the
    /// novelty voices and the older Eloquence voices (Eddy, Flo, Reed, Grandma
    /// and the rest), which sound robotic.
    static func candidates(language: String = "en") -> [AVSpeechSynthesisVoice] {
        let region = Locale.current.region?.identifier
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                voice.language.hasPrefix(language)
                    && !voice.voiceTraits.contains(.isNoveltyVoice)
                    && !voice.identifier.contains(".eloquence.")
            }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                // Then the person's own accent (en-GB in the UK, say).
                let lhsLocal = region.map { lhs.language.hasSuffix($0) } ?? false
                let rhsLocal = region.map { rhs.language.hasSuffix($0) } ?? false
                if lhsLocal != rhsLocal { return lhsLocal }
                return lhs.name < rhs.name
            }
    }

    /// What "Automatic" uses: the most natural voice installed, so a
    /// downloaded Premium or Enhanced voice is used without choosing it.
    static func bestInstalled(language: String = "en") -> AVSpeechSynthesisVoice? {
        candidates(language: language).first
            ?? AVSpeechSynthesisVoice(language: language == "es" ? "es-MX" : "en-US")
    }

    /// Voices in a language on this device, best first.
    static func available(language: String = "en") -> [NarrationVoice] {
        candidates(language: language)
            .map { voice in
                let quality: String? = switch voice.quality {
                case .premium: String(localized: "Premium", comment: "Voice quality")
                case .enhanced: String(localized: "Enhanced", comment: "Voice quality")
                default: nil
                }
                return NarrationVoice(
                    id: voice.identifier,
                    name: voice.name,
                    language: Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language,
                    qualityLabel: quality
                )
            }
    }
}
