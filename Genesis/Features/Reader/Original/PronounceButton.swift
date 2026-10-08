import SwiftUI

/// A speaker button that says a Hebrew or Greek word aloud
/// (`WordPronouncer`). Pauses listening first so the two don't overlap.
struct PronounceButton: View {
    let word: String
    let language: OriginalLanguage

    @Environment(WordPronouncer.self) private var pronouncer
    @Environment(AudioPlayerService.self) private var audio
    @Environment(\.palette) private var palette

    private var isSpeaking: Bool { pronouncer.isSpeaking(word) }

    var body: some View {
        Button {
            if isSpeaking {
                pronouncer.stop()
            } else {
                if audio.isPlaying { audio.pause() }
                pronouncer.say(word, language: language)
            }
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .symbolEffect(.variableColor.iterative, isActive: isSpeaking)
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isSpeaking ? Text("Stop") : Text("Pronounce"))
        .accessibilityIdentifier("original.pronounce")
    }
}

/// Under a word with a `PronounceButton`: which pronunciation the voice
/// uses, and how to add a voice when the device has none.
struct PronunciationNote: View {
    let language: OriginalLanguage

    @Environment(WordPronouncer.self) private var pronouncer
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if pronouncer.missingVoice == language {
                Text(missingVoiceText)
                    .foregroundStyle(.orange)
            } else {
                Text(aboutText)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var aboutText: String {
        switch language {
        case .hebrew: String(localized: "Spoken by your device's Hebrew voice, in modern Israeli pronunciation.")
        case .greek: String(localized: "Spoken by your device's Greek voice, in modern Greek pronunciation. Many courses teach a different one for New Testament Greek.")
        }
    }

    private var missingVoiceText: String {
        switch language {
        case .hebrew: String(localized: "This device has no Hebrew voice. Add one in Settings › Accessibility › Spoken Content › Voices › Hebrew.")
        case .greek: String(localized: "This device has no Greek voice. Add one in Settings › Accessibility › Spoken Content › Voices › Greek.")
        }
    }
}
