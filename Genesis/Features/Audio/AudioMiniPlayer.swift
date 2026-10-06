import SwiftUI

/// The listening bar at the bottom of the reader: what's playing, play and
/// pause, chapter skips, speed, sleep timer and audio settings.
struct AudioMiniPlayer: View {
    let onSettings: () -> Void
    var onAmbient: (() -> Void)?

    @Environment(AudioPlayerService.self) private var audio
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .accessibilityIdentifier("audio.title")
                    Text(audio.errorMessage ?? subtitle)
                        .font(.caption)
                        .foregroundStyle(audio.errorMessage == nil ? palette.secondaryText : .orange)
                        .lineLimit(2)
                        .accessibilityIdentifier("audio.subtitle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                control("backward.end.fill", label: "Previous chapter", id: "audio.previous") { audio.previousChapter() }
                playPauseButton
                control("forward.end.fill", label: "Next chapter", id: "audio.next") { audio.nextChapter() }
                optionsMenu
                control("xmark", label: "Stop listening", id: "audio.close") { audio.stop() }
            }
            if audio.isRecording, audio.duration > 0 {
                ProgressView(value: min(audio.elapsed, audio.duration), total: audio.duration)
                    .tint(palette.accent)
                    .accessibilityLabel("Chapter progress")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 560)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .sensoryFeedback(.selection, trigger: audio.isPlaying)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audio.player")
    }

    private var title: String {
        guard let chapter = audio.chapter else { return "" }
        if let verse = audio.verse { return "\(chapter.description(in: audio.translation.language)):\(verse.verse)" }
        return chapter.description(in: audio.translation.language)
    }

    private var subtitle: String {
        var parts = [audio.sourceTitle]
        if audio.settings.speed != 1 { parts.append(Self.speedLabel(audio.settings.speed)) }
        if let timer = audio.sleepTimer {
            if let end = audio.sleepEndsAt {
                parts.append(String(localized: "Sleep at \(end.formatted(date: .omitted, time: .shortened))"))
            } else {
                parts.append(timer.title)
            }
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var playPauseButton: some View {
        if audio.state == .loading {
            ProgressView()
                .frame(width: 40, height: 40)
                .accessibilityLabel("Loading")
        } else {
            let playing = audio.isPlaying
            Button {
                audio.togglePlayback()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(palette.accent)
            .accessibilityLabel(playing ? "Pause" : "Play")
            .accessibilityValue(playing ? "Playing" : "Paused")
            .accessibilityIdentifier("audio.playPause")
        }
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Speed", selection: Binding(get: { audio.settings.speed }, set: { audio.setSpeed($0) })) {
                ForEach(AudioSettings.speeds, id: \.self) { speed in
                    Text(Self.speedLabel(speed)).tag(speed)
                }
            }
            .pickerStyle(.menu)

            Menu("Sleep Timer", systemImage: "moon") {
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    timerButton(.minutes(minutes))
                }
                timerButton(.endOfChapter)
                if audio.sleepTimer != nil {
                    Button("Turn Off Timer", role: .destructive) { audio.setSleepTimer(nil) }
                }
            }

            if let onAmbient {
                Button("Ambient Sounds", systemImage: "speaker.wave.2", action: onAmbient)
                    .accessibilityIdentifier("audio.ambient")
            }

            Button("Audio Settings", systemImage: "slider.horizontal.3", action: onSettings)
                .accessibilityIdentifier("audio.settings")
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .frame(width: 32, height: 40)
                .contentShape(Rectangle())
        }
        .foregroundStyle(palette.text)
        .accessibilityLabel("Listening options")
        .accessibilityIdentifier("audio.options")
    }

    private func timerButton(_ timer: AudioPlayerService.SleepTimer) -> some View {
        Button {
            audio.setSleepTimer(timer)
        } label: {
            if audio.sleepTimer == timer {
                Label(timer.title, systemImage: "checkmark")
            } else {
                Text(timer.title)
            }
        }
    }

    private func control(_ systemImage: String, label: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 32, height: 40)
                .contentShape(Rectangle())
        }
        .foregroundStyle(palette.text)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    static func speedLabel(_ speed: Double) -> String {
        speed == 1
            ? String(localized: "1× speed")
            : String(localized: "\(speed.formatted(.number.precision(.fractionLength(0...2))))× speed")
    }
}
