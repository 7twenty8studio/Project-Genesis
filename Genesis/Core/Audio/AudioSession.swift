import AVFoundation

/// The one audio session, shared by Bible narration, ambient sounds and voice
/// recordings on prayers and sermons, so none switches it off while another
/// is still playing.
///
/// Narration and playing a voice recording take the session for spoken audio
/// (other apps' audio stops). Recording uses the microphone. Ambient sounds
/// on their own mix with other apps, so rain can play under someone's own music.
///
/// Deactivating can block for a moment, so it runs on a serial background
/// queue; activating waits on the same queue, so a quick stop-then-play never
/// ends with the session off, and playback starts with the right category.
@MainActor
enum AudioSession {
    enum User: Hashable {
        case narration, ambient
        /// Recording a voice note (`VoiceRecorder`).
        case recording
        /// Playing a voice note back (`VoiceNotePlayer`).
        case voiceNote
    }

    private static var users: Set<User> = []
    private static let queue = DispatchQueue(label: AudioSession.queueName, qos: .userInitiated)
    private nonisolated static let queueName = "genesis.audio-session"

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
        let spoken = users.contains(.narration) || users.contains(.voiceNote)
        let recording = users.contains(.recording)
        // Waits for any queued deactivation first, so the session ends up on.
        let failure: String? = queue.sync {
            let session = AVAudioSession.sharedInstance()
            do {
                if recording {
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                } else if spoken {
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
