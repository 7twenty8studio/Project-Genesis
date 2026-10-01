import SwiftUI

/// Choose a device voice or a recorded narration, speed and follow-along,
/// and download recorded books for offline listening.
struct AudioSettingsView: View {
    @Environment(AudioPlayerService.self) private var audio
    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var voices: [NarrationVoice] = []

    private var settings: AudioSettings { audio.settings }
    private var translation: Translation { library.currentTranslation }
    private var recordings: [AudioRecording] { audio.catalog.recordings(for: translation) }

    var body: some View {
        NavigationStack {
            Form {
                narrationSection
                if case .deviceVoice = settings.source(for: translation) {
                    voiceSection
                }
                playbackSection
                if case let .recording(id) = settings.source(for: translation), let recording = audio.catalog.recording(id: id) {
                    Section {
                        NavigationLink("Download for Offline Listening") {
                            AudioDownloadsView(recording: recording)
                        }
                        .accessibilityIdentifier("audio.downloads")
                    } footer: {
                        Text("Recorded narration streams over the internet. Download books to listen offline.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .themedScreen()
            .navigationTitle("Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("audio.settings.done")
                }
            }
            .task {
                voices = NarrationVoice.available()
                await audio.catalog.refresh()
            }
        }
    }

    private var sourceBinding: Binding<AudioSource> {
        Binding(
            get: {
                let source = settings.source(for: translation)
                if case let .recording(id) = source, audio.catalog.recording(id: id) == nil { return .deviceVoice }
                return source
            },
            set: { source in
                settings.setSource(source, for: translation)
                audio.settingsChanged()
            }
        )
    }

    private var narrationSection: some View {
        Section {
            Picker("Narration", selection: sourceBinding) {
                Text("Device voice").tag(AudioSource.deviceVoice)
                ForEach(recordings) { recording in
                    Text("Recorded · \(recording.title)").tag(AudioSource.recording(recording.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .accessibilityIdentifier("audio.source")
        } header: {
            Text("Narration · \(translation.abbreviation)")
        } footer: {
            if case let .recording(id) = sourceBinding.wrappedValue, let recording = audio.catalog.recording(id: id) {
                Text("\(recording.description) \(recording.license).")
            } else if recordings.isEmpty {
                Text("The device voice reads along with the text and works offline. Recorded narration isn't available for the \(translation.name) yet.")
            } else {
                Text("The device voice reads along with the text and works offline. Recorded narration is read by a person and plays chapter by chapter.")
            }
        }
    }

    private var voiceSection: some View {
        Section {
            Picker("Voice", selection: Binding(
                get: { settings.voiceIdentifier ?? "" },
                set: {
                    settings.voiceIdentifier = $0.isEmpty ? nil : $0
                    audio.settingsChanged()
                }
            )) {
                Text("Automatic").tag("")
                ForEach(voices) { voice in
                    Text([voice.name, voice.qualityLabel, voice.language].compactMap { $0 }.joined(separator: " · "))
                        .tag(voice.id)
                }
            }
            .accessibilityIdentifier("audio.voice")
        } header: {
            Text("Voice")
        } footer: {
            Text("For the most natural sound, download an Enhanced or Premium voice in Settings › Accessibility › Spoken Content › Voices › English.")
        }
    }

    private var playbackSection: some View {
        @Bindable var settings = settings
        return Section {
            Picker("Speed", selection: Binding(get: { settings.speed }, set: { audio.setSpeed($0) })) {
                ForEach(AudioSettings.speeds, id: \.self) { speed in
                    Text(AudioMiniPlayer.speedLabel(speed)).tag(speed)
                }
            }
            Toggle("Follow Along", isOn: $settings.followsAlong)
                .accessibilityIdentifier("audio.follow")
            Toggle("Continue to Next Chapter", isOn: $settings.continuesToNextChapter)
        } header: {
            Text("Playback")
        } footer: {
            Text("Follow Along turns the pages and marks the verse being read (device voice), or opens each chapter as it plays (recorded narration).")
        }
    }
}

/// Download or remove recorded books.
struct AudioDownloadsView: View {
    let recording: AudioRecording

    @Environment(AudioPlayerService.self) private var audio
    @Environment(\.palette) private var palette
    @State private var errorMessage: String?

    var body: some View {
        let catalog = audio.catalog
        List {
            Section {
                LabeledContent("Space used", value: ByteCountFormatter.string(fromByteCount: catalog.downloadedBytes(), countStyle: .file))
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.orange)
                }
            }
            ForEach(Testament.allCases, id: \.self) { testament in
                Section(testament.title) {
                    ForEach(BibleBook.all.filter { $0.testament == testament }) { book in
                        row(book, catalog: catalog)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .themedScreen()
        .navigationTitle(recording.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ book: BibleBook, catalog: AudioRecordingCatalog) -> some View {
        HStack {
            Text(book.name)
                .foregroundStyle(palette.text)
            Spacer()
            if let progress = catalog.downloads[catalog.downloadKey(book, in: recording)] {
                ProgressView(value: progress)
                    .frame(width: 80)
            } else if catalog.isDownloaded(book, in: recording) {
                Button("Remove", role: .destructive) { catalog.removeDownload(book, in: recording) }
                    .buttonStyle(.borderless)
            } else {
                Button {
                    // Keeps going if this screen closes.
                    Task {
                        do {
                            try await catalog.download(book, in: recording)
                        } catch is CancellationError {
                        } catch {
                            errorMessage = "\(book.name): \(error.localizedDescription)"
                        }
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Download \(book.name)")
            }
        }
    }
}
