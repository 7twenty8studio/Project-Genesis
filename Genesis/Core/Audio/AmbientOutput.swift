import AVFoundation
import Synchronization

/// Plays ambient loops. `AmbientSoundService` decides what plays and how
/// loud; this makes the sound (or, in UI tests, doesn't).
@MainActor
protocol AmbientOutput: AnyObject {
    /// Starts (or keeps playing) a sound, fading to `volume`.
    func play(_ sound: AmbientSound, volume: Float) throws
    func setVolume(_ volume: Float, for sound: AmbientSound)
    /// Fades a sound out and stops it.
    func stop(_ sound: AmbientSound)
    /// Fades everything out and lets the audio session go.
    func stopAll()
    /// Called when the system stopped the audio (a call, an alarm) or the
    /// route changed; the service says what should be playing again.
    var onInterruption: ((_ began: Bool, _ shouldResume: Bool) -> Void)? { get set }
}

/// Silent output for UI tests and unit tests: remembers what would play.
@MainActor
final class SilentAmbientOutput: AmbientOutput {
    private(set) var playing: [AmbientSound: Float] = [:]
    var onInterruption: ((Bool, Bool) -> Void)?

    func play(_ sound: AmbientSound, volume: Float) throws { playing[sound] = volume }
    func setVolume(_ volume: Float, for sound: AmbientSound) {
        if playing[sound] != nil { playing[sound] = volume }
    }
    func stop(_ sound: AmbientSound) { playing[sound] = nil }
    func stopAll() { playing = [:] }
}

/// Mixes loops with AVAudioEngine: one player node per sound, each looping
/// its file from disk (nothing large is held in memory) with gentle fades.
@MainActor
final class EngineAmbientOutput: AmbientOutput {
    var onInterruption: ((Bool, Bool) -> Void)?

    private let engine = AVAudioEngine()
    private var loops: [AmbientSound: AmbientLoop] = [:]
    private var targets: [AmbientSound: Float] = [:]
    private var fades: [AmbientSound: Task<Void, Never>] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            let info = notification.userInfo
            let type = (info?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (info?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            MainActor.assumeIsolated {
                self?.onInterruption?(type == .began, options.contains(.shouldResume))
            }
        })
        // Headphones unplugged, a new speaker: the engine stops and has to be
        // started again with the loops rescheduled.
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restart()
            }
        })
    }

    func play(_ sound: AmbientSound, volume: Float) throws {
        fades[sound]?.cancel()
        let loop: AmbientLoop
        if let existing = loops[sound] {
            loop = existing
        } else {
            guard let url = sound.url else { throw AmbientError.missing(sound) }
            loop = try AmbientLoop(url: url, seconds: sound.loopSeconds)
            engine.attach(loop.node)
            engine.connect(loop.node, to: engine.mainMixerNode, format: loop.format)
            loops[sound] = loop
        }
        AudioSession.begin(.ambient)
        let wasRunning = engine.isRunning
        if !wasRunning {
            engine.prepare()
            try engine.start()
        }
        if !wasRunning || !loop.isPlaying {
            loop.node.volume = 0
            loop.start()
        }
        targets[sound] = volume
        fade(sound, to: volume, over: 1.5)
    }

    func setVolume(_ volume: Float, for sound: AmbientSound) {
        guard targets[sound] != nil else { return }
        targets[sound] = volume
        fades[sound]?.cancel()
        loops[sound]?.node.volume = volume
    }

    func stop(_ sound: AmbientSound) {
        targets[sound] = nil
        fade(sound, to: 0, over: 1.2) { [weak self] in
            guard let self else { return }
            self.loops[sound]?.stop()
            if self.targets.isEmpty { self.shutDown() }
        }
    }

    func stopAll() {
        let sounds = Array(targets.keys)
        targets = [:]
        for sound in sounds {
            fade(sound, to: 0, over: 1.2) { [weak self] in
                guard let self else { return }
                self.loops[sound]?.stop()
                if self.targets.isEmpty { self.shutDown() }
            }
        }
        if sounds.isEmpty { shutDown() }
    }

    // MARK: Helpers

    private func shutDown() {
        guard targets.isEmpty else { return }
        engine.pause()
        AudioSession.end(.ambient)
    }

    /// Steps the node's volume to `target`; a little curve keeps it soft.
    private func fade(_ sound: AmbientSound, to target: Float, over seconds: Double, then done: (@MainActor () -> Void)? = nil) {
        fades[sound]?.cancel()
        guard let node = loops[sound]?.node else {
            done?()
            return
        }
        let start = node.volume
        fades[sound] = Task { @MainActor in
            let steps = max(1, Int(seconds * 30))
            for step in 1...steps {
                try? await Task.sleep(for: .seconds(seconds / Double(steps)))
                if Task.isCancelled { return }
                let progress = Float(step) / Float(steps)
                let eased = progress * progress * (3 - 2 * progress)
                node.volume = start + (target - start) * eased
            }
            done?()
        }
    }

    private func restart() {
        guard !targets.isEmpty else { return }
        do {
            engine.prepare()
            try engine.start()
            for (sound, volume) in targets {
                guard let loop = loops[sound] else { continue }
                loop.start()
                loop.node.volume = volume
            }
        } catch {
            CrashReporter.record(error, context: "Ambient.restart")
        }
    }
}

enum AmbientError: LocalizedError {
    case missing(AmbientSound)

    var errorDescription: String? {
        String(localized: "This sound couldn't be played.")
    }
}

/// One sound's player node, scheduling its file again each time a pass has
/// been read so the loop never runs dry. A generation number stops stale
/// callbacks (from before a stop) from scheduling more.
///
/// `@unchecked Sendable`: the node and file are used from the main actor and
/// from the node's own completion callbacks, which AVAudioPlayerNode allows;
/// the generation is guarded by a Mutex.
final class AmbientLoop: @unchecked Sendable {
    let node = AVAudioPlayerNode()
    let format: AVAudioFormat
    private let file: AVAudioFile
    private let frames: AVAudioFrameCount
    private let generation = Mutex(0)

    init(url: URL, seconds: Double) throws {
        file = try AVAudioFile(forReading: url)
        format = file.processingFormat
        let exact = AVAudioFrameCount(seconds * format.sampleRate)
        frames = min(exact, AVAudioFrameCount(clamping: file.length))
    }

    var isPlaying: Bool { node.isPlaying }

    func start() {
        let current = generation.withLock { (value: inout Int) -> Int in
            value += 1
            return value
        }
        node.stop()
        // Two passes queued: one playing, one waiting.
        schedule(current)
        schedule(current)
        node.play()
    }

    func stop() {
        generation.withLock { $0 += 1 }
        node.stop()
    }

    private func schedule(_ pass: Int) {
        node.scheduleSegment(file, startingFrame: 0, frameCount: frames, at: nil, completionCallbackType: .dataConsumed) { [weak self] _ in
            guard let self, self.generation.withLock({ (value: inout Int) in value }) == pass else { return }
            self.schedule(pass)
        }
    }
}
