import AVFoundation
import MediaPlayer

/// The lock screen, Control Center and headphone controls, plus the audio
/// session that lets reading carry on in the background.
@MainActor
final class NowPlayingController {
    struct Actions: Sendable {
        let play: @Sendable () -> Void
        let pause: @Sendable () -> Void
        let toggle: @Sendable () -> Void
        let next: @Sendable () -> Void
        let previous: @Sendable () -> Void
    }

    private var isConfigured = false
    private var interruptionObserver: NSObjectProtocol?

    /// Wires the remote commands once. Handlers hop to the main actor.
    func configure(_ actions: Actions, onInterruption: @escaping @MainActor (_ began: Bool, _ shouldResume: Bool) -> Void) {
        guard !isConfigured else { return }
        isConfigured = true
        Self.register(actions)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            let info = notification.userInfo
            let type = (info?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (info?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            MainActor.assumeIsolated {
                onInterruption(type == .began, options.contains(.shouldResume))
            }
        }
    }

    /// Registered from a nonisolated context so the handlers carry no actor
    /// isolation; MediaPlayer may call them on any thread.
    nonisolated private static func register(_ actions: Actions) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in actions.play(); return .success }
        center.pauseCommand.addTarget { _ in actions.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { _ in actions.toggle(); return .success }
        center.nextTrackCommand.addTarget { _ in actions.next(); return .success }
        center.previousTrackCommand.addTarget { _ in actions.previous(); return .success }
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }

    func activateSession() {
        AudioSession.begin(.narration)
    }

    func deactivateSession() {
        AudioSession.end(.narration)
    }

    func update(title: String, subtitle: String, isPlaying: Bool, speed: Double, elapsed: Double? = nil, duration: Double? = nil) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPMediaItemPropertyAlbumTitle: "Genesis",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: speed,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let elapsed { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed }
        if let duration, duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
