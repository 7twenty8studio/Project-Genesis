import SwiftUI

/// What's playing, from anywhere in the app: a small player above the tab bar
/// (like Music) while the Bible is read aloud or ambient sounds play. Tap it
/// for the full controls. The reader keeps its own listening bar, so this
/// shows on the other tabs.
struct NowPlayingAccessoryModifier: ViewModifier {
    let isEnabled: Bool
    let onOpen: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled) {
                NowPlayingAccessory(onOpen: onOpen)
            }
        } else {
            content
        }
    }
}

struct NowPlayingAccessory: View {
    let onOpen: () -> Void

    @Environment(AudioPlayerService.self) private var audio
    @Environment(AmbientSoundService.self) private var ambient
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: audio.isActive ? "headphones" : (ambient.currentMix?.systemImage ?? "speaker.wave.2"))
                        .font(.body.weight(.medium))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if placement != .inline, let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(subtitle.map { "\(title), \($0)" } ?? title))
            .accessibilityHint("Shows what's playing")
            .accessibilityIdentifier("nowPlaying.open")

            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.body)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("nowPlaying.playPause")

            if placement != .inline {
                Button(action: stopAll) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Stop")
                .accessibilityIdentifier("nowPlaying.stop")
            }
        }
        .padding(.horizontal, 14)
    }

    private var title: String {
        if audio.isActive, let chapter = audio.chapter {
            if let verse = audio.verse { return "\(chapter.description):\(verse.verse)" }
            return chapter.description
        }
        return ambient.summary
    }

    private var subtitle: String? {
        if audio.isActive {
            // "KJV · Device voice · Rain"
            return ambient.isPlaying ? "\(audio.sourceTitle) · \(ambient.summary)" : audio.sourceTitle
        }
        return String(localized: "Ambient sounds")
    }

    private var isPlaying: Bool { audio.isActive ? audio.isPlaying : ambient.isPlaying }

    private func togglePlayback() {
        if audio.isActive { audio.togglePlayback() } else { ambient.togglePlayback() }
    }

    private func stopAll() {
        if audio.isActive { audio.stop() }
        if ambient.showsControls { ambient.close() }
    }
}

/// The full controls for everything playing: the Bible being read aloud and
/// ambient sounds, each with its own play, pause and stop.
struct NowPlayingSheet: View {
    @Environment(AudioPlayerService.self) private var audio
    @Environment(AmbientSoundService.self) private var ambient
    @Environment(EntitlementService.self) private var entitlements
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ThemedRows {
                    if audio.isActive {
                        listening
                    }
                    if ambient.showsControls || entitlements.allows(.ambientSounds) {
                        ambientSection
                    }
                }
            }
            .themedScreen()
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("nowPlaying.done")
                }
            }
            .onChange(of: audio.isActive || ambient.showsControls) { _, playing in
                if !playing { dismiss() }
            }
        }
    }

    // MARK: Listening

    private var listening: some View {
        Section("Listening") {
            VStack(alignment: .leading, spacing: 2) {
                Text(chapterTitle)
                    .font(.headline)
                    .foregroundStyle(palette.text)
                Text(audio.errorMessage ?? audio.sourceTitle)
                    .font(.subheadline)
                    .foregroundStyle(audio.errorMessage == nil ? palette.secondaryText : .orange)
            }

            HStack {
                transport("backward.end.fill", label: "Previous chapter") { audio.previousChapter() }
                transport(audio.isPlaying ? "pause.circle.fill" : "play.circle.fill", label: audio.isPlaying ? "Pause" : "Play", size: 44) {
                    audio.togglePlayback()
                }
                .accessibilityIdentifier("nowPlaying.audio.playPause")
                transport("forward.end.fill", label: "Next chapter") { audio.nextChapter() }
            }
            .frame(maxWidth: .infinity)

            Picker("Speed", selection: Binding(get: { audio.settings.speed }, set: { audio.setSpeed($0) })) {
                ForEach(AudioSettings.speeds, id: \.self) { speed in
                    Text(AudioMiniPlayer.speedLabel(speed)).tag(speed)
                }
            }

            Picker("Sleep Timer", selection: Binding(get: { audio.sleepTimer }, set: { audio.setSleepTimer($0) })) {
                Text("Off").tag(AudioPlayerService.SleepTimer?.none)
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Text(AudioPlayerService.SleepTimer.minutes(minutes).title).tag(AudioPlayerService.SleepTimer?.some(.minutes(minutes)))
                }
                Text(AudioPlayerService.SleepTimer.endOfChapter.title).tag(AudioPlayerService.SleepTimer?.some(.endOfChapter))
            }

            if let chapter = audio.chapter {
                Button("Open in Reader", systemImage: "book") {
                    router.read(audio.verse ?? chapter.firstVerse)
                    dismiss()
                }
            }

            Button("Stop Listening", systemImage: "stop.fill", role: .destructive) { audio.stop() }
                .accessibilityIdentifier("nowPlaying.audio.stop")
        }
    }

    private var chapterTitle: String {
        guard let chapter = audio.chapter else { return "" }
        if let verse = audio.verse { return "\(chapter.description):\(verse.verse)" }
        return chapter.description
    }

    private func transport(_ systemImage: String, label: LocalizedStringKey, size: CGFloat = 22, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.accent)
        .accessibilityLabel(label)
    }

    // MARK: Ambient sounds

    private var ambientSection: some View {
        Section("Ambient Sounds") {
            if ambient.showsControls {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ambient.summary)
                            .font(.headline)
                            .foregroundStyle(palette.text)
                        Text(ambient.isPlaying ? String(localized: "Playing", comment: "Ambient sounds status") : String(localized: "Paused", comment: "Ambient sounds status"))
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    Button {
                        ambient.togglePlayback()
                    } label: {
                        Image(systemName: ambient.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(palette.accent)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(ambient.isPlaying ? "Pause" : "Play")
                    .accessibilityIdentifier("nowPlaying.ambient.playPause")
                }
            }
            if entitlements.allows(.ambientSounds) {
                NavigationLink {
                    AmbientSoundsView()
                } label: {
                    Label(ambient.showsControls ? String(localized: "Change Sounds") : String(localized: "Add Ambient Sounds"), systemImage: "slider.horizontal.3")
                }
            }
            if ambient.showsControls {
                Button("Stop Ambient Sounds", systemImage: "stop.fill", role: .destructive) { ambient.close() }
                    .accessibilityIdentifier("nowPlaying.ambient.stop")
            }
        }
    }
}
