import AVFoundation

/// The one audio session, shared by Bible narration and ambient sounds so
/// neither switches it off while the other is still playing.
///
/// Narration takes the session for spoken audio (other apps' audio stops).
/// Ambient sounds on their own mix with other apps, so rain can play under
/// someone's own music.
///
/// Deactivating can block for a moment, so it runs on a serial background
/// queue; activating waits on the same queue, so a quick stop-then-play never
/// ends with the session off, and playback starts with the right category.
@MainActor
enum AudioSession {
    enum User: Hashable {
        case narration, ambient
    }

    private static var users: Set<User> = []
    private static let queue = DispatchQueue(label: "genesis.audio-session", qos: .userInitiated)

    static func begin(_ user: User) {
        users.insert(user)
        apply()
    }

    static func end(_ user: User) {
        guard users.remove(user) != nil else { return }
        if users.isEmpty {
            queue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        } else {
            apply()
        }
    }

    private static func apply() {
        let spoken = users.contains(.narration)
        // Waits for any queued deactivation first, so the session ends up on.
        let failure: String? = queue.sync {
            let session = AVAudioSession.sharedInstance()
            do {
                if spoken {
                    try session.setCategory(.playback, mode: .spokenAudio)
                } else {
                    try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                }
                try session.setActive(true)
                return nil
            } catch {
                return String(describing: error)
            }
        }
        if let failure { CrashReporter.record(AudioSessionError(message: failure), context: "AudioSession") }
    }
}

private struct AudioSessionError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
