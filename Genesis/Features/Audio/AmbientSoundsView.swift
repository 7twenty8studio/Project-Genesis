import SwiftUI

/// Choose ambient sounds to read and pray with: ready-made mixes, each sound
/// on or off with its own volume, and a timer. Premium (callers check).
struct AmbientSoundsView: View {
    @Environment(AmbientSoundService.self) private var ambient
    @Environment(\.palette) private var palette

    var body: some View {
        Form {
            ThemedRows {
                Section {
                    playRow
                    if let message = ambient.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    ForEach(AmbientSound.allCases) { sound in
                        soundRow(sound)
                    }
                } header: {
                    Text("Sounds")
                } footer: {
                    Text("Sounds keep playing when you lock your iPhone, play alongside music from other apps, and sit quieter while the Bible is read aloud.")
                }

                Section("Mixes") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(AmbientMix.all) { preset in
                                mixChip(preset)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    Picker(selection: Binding(get: { ambient.timerMinutes }, set: { ambient.setTimer(minutes: $0) })) {
                        Text("Off").tag(Int?.none)
                        ForEach(AmbientSoundService.timerChoices, id: \.self) { minutes in
                            Text("\(minutes) minutes").tag(Int?.some(minutes))
                        }
                    } label: {
                        Label("Timer", systemImage: "timer")
                    }
                    .accessibilityIdentifier("ambient.timer")
                } footer: {
                    if let end = ambient.timerEndsAt {
                        Text("Fades out at \(end.formatted(date: .omitted, time: .shortened)).")
                    }
                }
            }
        }
        .themedScreen()
        .navigationTitle("Ambient Sounds")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: ambient.mix.count)
    }

    private var playRow: some View {
        HStack(spacing: 14) {
            Button {
                ambient.togglePlayback()
            } label: {
                Image(systemName: ambient.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(ambient.mix.isEmpty ? palette.secondaryText : palette.accent)
            }
            .buttonStyle(.plain)
            .disabled(ambient.mix.isEmpty)
            .accessibilityLabel(ambient.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("ambient.playPause")

            VStack(alignment: .leading, spacing: 2) {
                Text(ambient.mix.isEmpty ? String(localized: "Choose a sound") : ambient.summary)
                    .font(.headline)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                Text(ambient.isPlaying ? String(localized: "Playing", comment: "Ambient sounds status") : String(localized: "Paused", comment: "Ambient sounds status"))
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityIdentifier("ambient.status")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func mixChip(_ preset: AmbientMix) -> some View {
        let selected = ambient.currentMix == preset
        return Button {
            ambient.choose(preset)
        } label: {
            Label(preset.title, systemImage: preset.systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(selected ? palette.background : palette.text)
                .background(selected ? palette.accent : palette.background, in: Capsule())
                .overlay(Capsule().strokeBorder(palette.separator, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("ambient.mix.\(preset.id)")
    }

    private func soundRow(_ sound: AmbientSound) -> some View {
        let on = ambient.contains(sound)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                ambient.toggle(sound)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: sound.systemImage)
                        .frame(width: 28)
                        .foregroundStyle(on ? palette.accent : palette.secondaryText)
                    Text(sound.title)
                        .foregroundStyle(palette.text)
                    Spacer()
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(on ? palette.accent : palette.separator)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("ambient.sound.\(sound.rawValue)")

            if on {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                    Slider(value: Binding(get: { Double(ambient.volume(of: sound)) }, set: { ambient.setVolume(Float($0), for: sound) }), in: 0...1)
                        .tint(palette.accent)
                        .accessibilityLabel("\(sound.title) volume")
                        .accessibilityIdentifier("ambient.volume.\(sound.rawValue)")
                    Image(systemName: "speaker.wave.3.fill")
                }
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .padding(.leading, 40)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Ambient sounds in their own sheet (from the listening bar or the reader's
/// ambient bar).
struct AmbientSoundsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AmbientSoundsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") { dismiss() }
                            .accessibilityIdentifier("ambient.done")
                    }
                }
        }
    }
}

/// A small bar at the bottom of the reader while ambient sounds play (and
/// the Bible isn't being read aloud): what's playing, pause and options.
struct AmbientMiniBar: View {
    let onOpen: () -> Void

    var body: some View {
        AmbientControlsRow(onOpen: onOpen)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: 420)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal, 12)
            .accessibilityElement(children: .contain)
    }
}

/// Ambient sounds' mix, pause and stop: on their own in `AmbientMiniBar`,
/// or under the Bible being read aloud in `AudioMiniPlayer`.
struct AmbientControlsRow: View {
    let onOpen: () -> Void

    @Environment(AmbientSoundService.self) private var ambient
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: ambient.currentMix?.systemImage ?? "speaker.wave.2")
                        .foregroundStyle(palette.accent)
                    Text(ambient.summary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ambient sounds, \(ambient.summary)")
            .accessibilityIdentifier("ambient.bar")

            Button {
                ambient.togglePlayback()
            } label: {
                Image(systemName: ambient.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(palette.accent)
            .accessibilityLabel(ambient.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("ambient.bar.playPause")

            Button {
                ambient.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 30, height: 36)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(palette.secondaryText)
            .accessibilityLabel("Stop ambient sounds")
            .accessibilityIdentifier("ambient.bar.close")
        }
    }
}
