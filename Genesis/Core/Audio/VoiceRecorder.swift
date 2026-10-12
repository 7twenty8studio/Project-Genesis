import AVFoundation
import Foundation
import Observation

/// Records a voice note for a prayer or sermon: AAC, mono, 32 kbps, stopping
/// itself after 4 hours (`AttachmentLimits`). The session goes through `AudioSession`.
@MainActor
@Observable
final class VoiceRecorder {
    enum State: Equatable {
        case idle
        case recording
        /// Stopped, with the recording ready to keep or discard.
        case finished(URL, duration: TimeInterval)
        case denied
        case failed
    }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    /// The input level, 0…1, for the meter.
    private(set) var level: Double = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private let files: AttachmentFiles

    init(files: AttachmentFiles) {
        self.files = files
    }

    static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: AttachmentLimits.audioSampleRate,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: AttachmentLimits.audioBitRate,
    ]

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .denied
            return
        }
        discard()
        AudioSession.begin(.recording)
        let url = files.scratchURL(extension: AttachmentKind.audio.fileExtension)
        do {
            let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: AttachmentLimits.maxAudioDuration) else {
                throw VoiceRecorderError.couldNotStart
            }
            self.recorder = recorder
            state = .recording
            elapsed = 0
            watch(url: url)
        } catch {
            AudioSession.end(.recording)
            state = .failed
        }
    }

    func stop() {
        recorder?.stop()
    }

    /// Throws away an unsaved recording.
    func discard() {
        meterTask?.cancel()
        if let recorder {
            // Closed mid-recording: `finish` won't run, so release the
            // session and remove the scratch file here.
            recorder.stop()
            recorder.deleteRecording()
            AudioSession.end(.recording)
        }
        recorder = nil
        if case let .finished(url, _) = state {
            try? FileManager.default.removeItem(at: url)
        }
        state = .idle
        level = 0
        elapsed = 0
    }

    /// The finished recording, handed over to be kept (the recorder forgets it).
    func takeRecording() -> (url: URL, duration: TimeInterval)? {
        guard case let .finished(url, duration) = state else { return nil }
        state = .idle
        return (url, duration)
    }

    /// Updates the meter and time until recording stops (by the person or the
    /// two-hour limit).
    private func watch(url: URL) {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.updateMeter() else { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            self?.finish(url: url)
        }
    }

    /// False once recording has stopped.
    private func updateMeter() -> Bool {
        guard let recorder, recorder.isRecording else { return false }
        recorder.updateMeters()
        level = VoiceLevel.normalized(decibels: Double(recorder.averagePower(forChannel: 0)))
        elapsed = recorder.currentTime
        return true
    }

    private func finish(url: URL) {
        AudioSession.end(.recording)
        recorder = nil
        meterTask = nil
        level = 0
        let duration = AttachmentMedia.audioDuration(at: url) ?? elapsed
        state = duration > 0.5 ? .finished(url, duration: duration) : .idle
        if duration <= 0.5 { try? FileManager.default.removeItem(at: url) }
    }
}

private enum VoiceRecorderError: Error {
    case couldNotStart
}

/// Microphone level for the meter.
enum VoiceLevel {
    /// −60 dB (or quieter) is 0; 0 dB is 1; linear in between.
    static func normalized(decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(1, max(0, (decibels + 60) / 60))
    }

    /// "1:05" or "1:02:03".
    static func timeText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
