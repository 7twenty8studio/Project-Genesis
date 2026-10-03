import Foundation
import Observation

/// Ambient sounds to read and pray with (Premium): a mix of rain, waves,
/// wind, fire, birdsong and a worship pad, each at its own volume, with a
/// timer that fades them out. The mix is remembered. Sounds keep playing
/// with the screen locked and sit quieter while the Bible is read aloud.
@MainActor
@Observable
final class AmbientSoundService {
    /// The sounds in the mix and their volumes (0...1), playing or not.
    private(set) var mix: [AmbientSound: Float]
    private(set) var isPlaying = false
    private(set) var timerEndsAt: Date?
    private(set) var timerMinutes: Int?
    private(set) var errorMessage: String?
    /// Lowered while the Bible is being read aloud.
    private(set) var isDucked = false

    /// True from pressing play until the sounds are closed, so the reader
    /// keeps a small bar to pause and resume.
    private(set) var showsControls = false

    /// The ready-made mix that matches what's chosen, if any.
    var currentMix: AmbientMix? {
        AmbientMix.all.first { $0.volumes == mix }
    }

    /// "Rain, Fireplace" for the mini bar.
    var summary: String {
        AmbientSound.allCases.filter { mix[$0] != nil }.map(\.title).formatted(.list(type: .and, width: .narrow))
    }

    static let timerChoices = [15, 30, 45, 60, 90]
    static let duckFactor: Float = 0.45

    @ObservationIgnored private let output: AmbientOutput
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var pausedByInterruption = false

    private static let mixKey = "ambient.mix"

    init(output: AmbientOutput, defaults: UserDefaults = .standard) {
        self.output = output
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: Self.mixKey) as? [String: Double] ?? [:]
        mix = Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in
            AmbientSound(rawValue: key).map { ($0, Float(min(max(value, 0), 1))) }
        })
        output.onInterruption = { [weak self] began, shouldResume in
            guard let self else { return }
            if began {
                guard self.isPlaying else { return }
                self.pause()
                self.pausedByInterruption = true
            } else {
                if shouldResume, self.pausedByInterruption { self.play() }
                self.pausedByInterruption = false
            }
        }
    }

    // MARK: Choosing sounds

    func contains(_ sound: AmbientSound) -> Bool { mix[sound] != nil }

    func volume(of sound: AmbientSound) -> Float { mix[sound] ?? sound.defaultVolume }

    /// Adds a sound to the mix (and starts playing), or takes it out.
    func toggle(_ sound: AmbientSound) {
        if mix[sound] != nil {
            mix[sound] = nil
            output.stop(sound)
            if mix.isEmpty {
                // The output fades this last sound out and lets the session go.
                isPlaying = false
                showsControls = false
                setTimer(minutes: nil)
            }
        } else {
            mix[sound] = sound.defaultVolume
            if isPlaying {
                start(sound)
            } else {
                play()
            }
        }
        save()
    }

    func setVolume(_ volume: Float, for sound: AmbientSound) {
        guard mix[sound] != nil else { return }
        let clamped = min(max(volume, 0), 1)
        mix[sound] = clamped
        if isPlaying { output.setVolume(effective(clamped), for: sound) }
        save()
    }

    /// Replaces the mix with a ready-made one and plays it.
    func choose(_ preset: AmbientMix) {
        for sound in mix.keys where preset.volumes[sound] == nil {
            output.stop(sound)
        }
        mix = preset.volumes
        save()
        if isPlaying {
            for sound in mix.keys { start(sound) }
        } else {
            play()
        }
    }

    // MARK: Playing

    func play() {
        guard !mix.isEmpty else { return }
        errorMessage = nil
        isPlaying = true
        showsControls = true
        for sound in mix.keys { start(sound) }
    }

    func pause() {
        guard isPlaying else { return }
        pausedByInterruption = false
        stopPlaying()
    }

    /// Stops the sounds and puts the reader's bar away.
    func close() {
        pause()
        showsControls = false
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    /// Bible narration started or stopped: sit quieter beneath it.
    func setDucked(_ ducked: Bool) {
        guard ducked != isDucked else { return }
        isDucked = ducked
        guard isPlaying else { return }
        for (sound, volume) in mix { output.setVolume(effective(volume), for: sound) }
    }

    // MARK: Timer

    /// Fades the sounds out after this many minutes (nil: no timer).
    func setTimer(minutes: Int?) {
        timerTask?.cancel()
        timerTask = nil
        // A timer only makes sense while something plays.
        let minutes = isPlaying ? minutes : nil
        timerMinutes = minutes
        guard let minutes else {
            timerEndsAt = nil
            return
        }
        timerEndsAt = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled, let self else { return }
            self.timerMinutes = nil
            self.timerEndsAt = nil
            self.pause()
        }
    }

    // MARK: Helpers

    private func start(_ sound: AmbientSound) {
        guard let volume = mix[sound] else { return }
        do {
            try output.play(sound, volume: effective(volume))
        } catch {
            errorMessage = error.localizedDescription
            CrashReporter.record(error, context: "Ambient.play \(sound.rawValue)")
        }
    }

    private func stopPlaying() {
        isPlaying = false
        output.stopAll()
        setTimer(minutes: nil)
    }

    private func effective(_ volume: Float) -> Float {
        isDucked ? volume * Self.duckFactor : volume
    }

    private func save() {
        defaults.set(Dictionary(uniqueKeysWithValues: mix.map { ($0.key.rawValue, Double($0.value)) }), forKey: Self.mixKey)
    }
}
