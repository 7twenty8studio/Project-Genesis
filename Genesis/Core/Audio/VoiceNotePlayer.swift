import AVFoundation
import Foundation
import Observation

/// Plays one voice recording with a scrubber. The session goes through
/// `AudioSession` (as `.voiceNote`).
@MainActor
@Observable
final class VoiceNotePlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    func load(_ url: URL) {
        stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        currentTime = 0
    }

    var isLoaded: Bool { player != nil }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        AudioSession.begin(.voiceNote)
        player.play()
        isPlaying = true
        tick()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
        AudioSession.end(.voiceNote)
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), player.duration)
        currentTime = player.currentTime
    }

    func stop() {
        player?.stop()
        player = nil
        ticker?.cancel()
        if isPlaying { AudioSession.end(.voiceNote) }
        isPlaying = false
    }

    private func tick() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    AudioSession.end(.voiceNote)
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
}
