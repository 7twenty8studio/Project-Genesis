import AVFoundation
import Synchronization
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
    ///
    /// Slow: asking iOS for its voices can take seconds (longer in the
    /// Simulator), so this runs off the main thread and is remembered by
    /// `VoiceList`.
    static func candidates(language: String = "en") -> [AVSpeechSynthesisVoice] {
        VoiceList.identifiers(language: language).compactMap(AVSpeechSynthesisVoice.init(identifier:))
    }

    /// What "Automatic" uses: the most natural voice installed, so a
    /// downloaded Premium or Enhanced voice is used without choosing it.
    /// Never waits for the voice list: until it has loaded (in the
    /// background), the language's standard voice reads.
    static func bestInstalled(language: String = "en") -> AVSpeechSynthesisVoice? {
        if let best = VoiceList.cachedIdentifiers(language: language)?.first.flatMap(AVSpeechSynthesisVoice.init(identifier:)) {
            return best
        }
        VoiceList.preload(language)
        return AVSpeechSynthesisVoice(language: language == "es" ? "es-MX" : "en-US")
    }

    /// Voices in a language on this device, best first (loaded off the main thread).
    static func available(language: String = "en") async -> [NarrationVoice] {
        await Task.detached(priority: .userInitiated) { list(language: language) }.value
    }

    private static func list(language: String) -> [NarrationVoice] {
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

/// The device's voices for each language, best first, looked up once.
/// iOS's voice list is slow to read, so it's read in the background and
/// remembered until voices are added or removed.
enum VoiceList {
    private static let cache = Mutex<[String: [String]]>([:])

    /// Already loaded, or nil.
    static func cachedIdentifiers(language: String) -> [String]? {
        cache.withLock { $0[language] }
    }

    /// Loads in the background if it isn't loaded yet.
    static func preload(_ languages: String...) {
        let missing = languages.filter { cachedIdentifiers(language: $0) == nil }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) {
            for language in missing { _ = identifiers(language: language) }
        }
    }

    /// Voice identifiers in a language, best first. Slow the first time:
    /// call off the main thread.
    static func identifiers(language: String) -> [String] {
        if let cached = cachedIdentifiers(language: language) { return cached }
        let region = Locale.current.region?.identifier
        let sorted = AVSpeechSynthesisVoice.speechVoices()
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
            .map(\.identifier)
        cache.withLock { $0[language] = sorted }
        return sorted
    }

    /// Voices were downloaded or removed in Settings.
    static func reset() {
        cache.withLock { $0.removeAll() }
    }
}
