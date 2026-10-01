import AVFoundation
import Foundation

/// Plays one recorded chapter (streamed or downloaded) with AVPlayer.
@MainActor
final class RecordingPlayer {
    var onFinish: (() -> Void)?
    var onFailure: ((String) -> Void)?
    /// Elapsed and total seconds, about twice a second.
    var onProgress: ((Double, Double) -> Void)?

    private let player = AVPlayer()
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var statusTask: Task<Void, Never>?
    private var speed: Double = 1

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let item = self.player.currentItem else { return }
                let duration = item.duration.seconds
                self.onProgress?(time.seconds, duration.isFinite ? duration : 0)
            }
        }
    }

    func play(url: URL, speed: Double) {
        stop()
        self.speed = speed
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFinish?() }
        }
        player.replaceCurrentItem(with: item)
        player.defaultRate = Float(speed)
        player.playImmediately(atRate: Float(speed))
        statusTask = Task { [weak self] in
            // Report a file that can't be played (missing, offline, bad format).
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled, self.player.currentItem === item else { return }
                switch item.status {
                case .failed:
                    self.onFailure?(item.error?.localizedDescription ?? "This chapter couldn't be played.")
                    return
                case .readyToPlay:
                    return
                default:
                    continue
                }
            }
        }
    }

    func pause() {
        player.pause()
    }

    func resume() {
        player.playImmediately(atRate: Float(speed))
    }

    func setSpeed(_ speed: Double) {
        self.speed = speed
        player.defaultRate = Float(speed)
        if player.rate > 0 { player.rate = Float(speed) }
    }

    func skip(by seconds: Double) {
        let target = max(0, player.currentTime().seconds + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
    }

    func stop() {
        statusTask?.cancel()
        statusTask = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
