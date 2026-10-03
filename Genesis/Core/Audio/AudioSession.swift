import AVFoundation

/// The one audio session, shared by Bible narration and ambient sounds so
/// neither switches it off while the other is still playing.
///
/// Narration takes the session for spoken audio (other apps' audio stops).
/// Ambient sounds on their own mix with other apps, so rain can play under
/// someone's own music.
@MainActor
enum AudioSession {
    enum User: Hashable {
        case narration, ambient
    }

    private static var users: Set<User> = []

    static func begin(_ user: User) {
        users.insert(user)
        apply()
    }

    static func end(_ user: User) {
        guard users.remove(user) != nil else { return }
        if users.isEmpty {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } else {
            apply()
        }
    }

    private static func apply() {
        let session = AVAudioSession.sharedInstance()
        do {
            if users.contains(.narration) {
                try session.setCategory(.playback, mode: .spokenAudio)
            } else {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)
        } catch {
            CrashReporter.record(error, context: "AudioSession")
        }
    }
}
