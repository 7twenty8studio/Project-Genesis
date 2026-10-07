import SwiftUI

/// Records a voice note: record, stop, listen back, then keep or discard.
/// For sermons, a gentle reminder that some churches ask not to be recorded.
struct VoiceRecorderSheet: View {
    let owner: AttachmentOwner
    let onKeep: (URL, TimeInterval) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var recorder: VoiceRecorder
    @State private var player = VoiceNotePlayer()

    init(owner: AttachmentOwner, files: AttachmentFiles, onKeep: @escaping (URL, TimeInterval) -> Void) {
        self.owner = owner
        self.onKeep = onKeep
        _recorder = State(initialValue: VoiceRecorder(files: files))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if owner == .sermon {
                    Label("Some churches ask that sermons not be recorded. Please check first.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                Text(verbatim: VoiceLevel.timeText(shownTime))
                    .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.text)
                    .accessibilityIdentifier("recorder.time")
                LevelMeter(level: recorder.level)
                    .frame(height: 28)
                    .opacity(recorder.state == .recording ? 1 : 0.3)
                controls
                Spacer(minLength: 0)
                statusText
            }
            .padding(24)
            .themedScreen()
            .navigationTitle("Voice Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(recorder.state == .recording)
        .onDisappear {
            player.stop()
            recorder.discard()
        }
    }

    private var shownTime: TimeInterval {
        switch recorder.state {
        case .finished: player.isLoaded ? player.currentTime : 0
        default: recorder.elapsed
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch recorder.state {
        case .recording:
            roundButton(String(localized: "Stop", comment: "Stop recording"), systemImage: "stop.fill", identifier: "recorder.stop") { recorder.stop() }
        case let .finished(url, duration):
            VStack(spacing: 12) {
                Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(duration, 0.1))
                    .accessibilityLabel("Position")
                HStack(spacing: 28) {
                    roundButton(String(localized: "Record Again"), systemImage: "arrow.counterclockwise", identifier: "recorder.again") {
                        player.stop()
                        Task { await recorder.start() }
                    }
                    roundButton(player.isPlaying ? String(localized: "Pause") : String(localized: "Play"), systemImage: player.isPlaying ? "pause.fill" : "play.fill", identifier: "recorder.play") {
                        if !player.isLoaded { player.load(url) }
                        player.togglePlayback()
                    }
                }
            }
        default:
            roundButton(String(localized: "Record", comment: "Start recording"), systemImage: "mic.fill", identifier: "recorder.record") {
                Task { await recorder.start() }
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch recorder.state {
        case .denied:
            Text("Genesis can't use the microphone. Turn it on in Settings › Privacy & Security › Microphone.")
                .font(.footnote)
                .foregroundStyle(.orange)
        case .failed:
            Text("Recording couldn't start. Please try again.")
                .font(.footnote)
                .foregroundStyle(.orange)
        default:
            Text("Up to two hours. Recordings stay private to you.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", systemImage: "xmark") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", systemImage: "checkmark") {
                player.stop()
                if let recording = recorder.takeRecording() {
                    onKeep(recording.url, recording.duration)
                }
                dismiss()
            }
            .disabled(!isFinished)
            .accessibilityIdentifier("recorder.save")
        }
    }

    private var isFinished: Bool {
        if case .finished = recorder.state { return true }
        return false
    }

    private func roundButton(_ title: String, systemImage: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title)
                .frame(width: 72, height: 72)
                .foregroundStyle(.white)
                .background(palette.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(identifier)
    }
}

/// The microphone level as a row of bars.
private struct LevelMeter: View {
    let level: Double

    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let bars = 24
            let lit = Int((level * Double(bars)).rounded())
            HStack(spacing: 3) {
                ForEach(0..<bars, id: \.self) { index in
                    Capsule()
                        .fill(index < lit ? palette.accent : palette.separator)
                        .frame(width: max(2, (proxy.size.width - CGFloat(bars - 1) * 3) / CGFloat(bars)))
                }
            }
        }
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.1), value: level)
    }
}
