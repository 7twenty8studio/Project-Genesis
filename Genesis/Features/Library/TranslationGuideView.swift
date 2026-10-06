import SwiftUI

/// "Which Bible is right for me?": how translations differ, where each Bible
/// in a language sits, and a suggestion for each way of reading.
struct TranslationGuideView: View {
    let language: String

    @Environment(BibleLibrary.self) private var library
    @Environment(AudioPlayerService.self) private var audio
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// The Bibles in `language`, most read first; live, so a download that
    /// finishes while the guide is open shows up.
    private var entries: [LibraryEntry] {
        ReadingLibrary.entries(
            in: language,
            installed: library.translations,
            catalog: library.catalog,
            recordedTranslationIDs: Set(audio.catalog.recordings.map(\.translation))
        )
    }

    private var languageName: String { AppLanguage.displayName(language) }

    var body: some View {
        NavigationStack {
            List {
                ThemedRows {
                    Section {
                        Text("Translations differ in how closely they follow the original Hebrew, Aramaic and Greek, and in how they sound. Many people read more than one.")
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.surface)

                    suggestions

                    Section {
                        spectrum
                        ForEach(TranslationApproach.allCases, id: \.self) { approach in
                            explanation(approach.title, approach.detail, systemImage: approach.systemImage)
                        }
                    } header: {
                        Text("How it's translated")
                    }
                    .listRowBackground(palette.surface)

                    Section {
                        ForEach(ReadingLevel.allCases, id: \.self) { level in
                            explanation(level.title, level.detail, systemImage: "textformat")
                        }
                    } header: {
                        Text("How it reads")
                    }
                    .listRowBackground(palette.surface)

                    Section {
                        explanation(TranslationRights.publicDomain.title, String(localized: "Free for anyone to read and share. Every Bible in Genesis today is public domain."), systemImage: "checkmark.seal")
                        explanation(TranslationRights.licensed.title, String(localized: "Used with the publisher's permission. Genesis will add licensed Bibles as agreements allow."), systemImage: "doc.text")
                        explanation(String(localized: "Audio"), String(localized: "Every Bible can be read aloud by a device voice. Some also have a recording by a narrator."), systemImage: "waveform")
                    } header: {
                        Text("Rights and audio")
                    }
                    .listRowBackground(palette.surface)
                }
            }
            .themedScreen()
            .navigationTitle("Choosing a Bible")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("guide.done")
                }
            }
        }
    }

    // MARK: Suggestions

    @ViewBuilder
    private var suggestions: some View {
        if entries.count == 1, let only = entries.first {
            Section {
                Text("There's one Bible in \(languageName) so far: \(only.translation.name).")
                    .foregroundStyle(palette.text)
                    .accessibilityIdentifier("guide.onlyBible")
            } header: {
                Text("Suggestions in \(languageName)")
            }
            .listRowBackground(palette.surface)
        } else if entries.count > 1 {
            Section {
                ForEach(ReadingPurpose.allCases, id: \.self) { purpose in
                    if let entry = ReadingLibrary.suggestion(for: purpose, in: entries) {
                        suggestionRow(purpose, entry)
                    }
                }
            } header: {
                Text("Suggestions in \(languageName)")
            }
            .listRowBackground(palette.surface)
        }
    }

    private func suggestionRow(_ purpose: ReadingPurpose, _ entry: LibraryEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: purpose.systemImage)
                .foregroundStyle(palette.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(purpose.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                Text(entry.translation.name)
                    .foregroundStyle(palette.text)
                if let reason = reason(entry.profile) {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide.suggestion.\(entry.id)")
    }

    /// "Balanced · Everyday language".
    private func reason(_ profile: TranslationProfile) -> String? {
        let parts = [profile.approach?.title, profile.readingLevel?.title].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: The spectrum

    /// The three approaches left to right, with this language's Bibles under
    /// each.
    private var spectrum: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(TranslationApproach.allCases, id: \.self) { approach in
                    VStack(spacing: 6) {
                        Text(approach.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.text)
                            .multilineTextAlignment(.center)
                        ForEach(entries.filter { $0.profile.approach == approach }) { entry in
                            Text(entry.translation.abbreviation)
                                .font(.system(.caption, design: .serif, weight: .bold))
                                .foregroundStyle(palette.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(palette.accent.opacity(0.14)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.left")
                Capsule().frame(height: 2)
                Image(systemName: "arrow.right")
            }
            .font(.caption2)
            .foregroundStyle(palette.separator)
            .accessibilityHidden(true)
            HStack(alignment: .top) {
                Text("Closer to the original wording")
                Spacer(minLength: 12)
                Text("Closer to everyday speech")
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption2)
            .foregroundStyle(palette.secondaryText)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide.spectrum")
    }

    private func explanation(_ title: String, _ detail: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(palette.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.text)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
