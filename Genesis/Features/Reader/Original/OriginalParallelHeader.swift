import SwiftUI

/// The top of the Original parallel Bible: what each column holds (the
/// Hebrew or Greek edition named, with an info sheet about it), the
/// Interlinear switch, and (New Testament) what the dotted words mean.
struct OriginalParallelHeader: View {
    let chapterID: ChapterID
    let translation: Translation
    let language: OriginalLanguage
    /// The Greek edition this Bible follows.
    let greek: OriginalSource.Greek
    let sideBySide: Bool
    /// Some Greek words on the page aren't in the edition it's compared with.
    let marksEditions: Bool
    @Binding var interlinear: Bool
    @Binding var originalOnly: Bool

    @Environment(ReaderSettings.self) private var settings
    @Environment(\.palette) private var palette
    @State private var showsSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titles
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("reader.parallel.originalHeader")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    interlinearButton
                    originalOnlyButton
                    sourceButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        interlinearButton
                        originalOnlyButton
                    }
                    sourceButton
                }
            }
            if marksEditions {
                Text(greek.edition.dottedWords)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if WordStudyRepository.needsEnglishNote(bibleLanguage: translation.language) {
                Text("Word meanings and grammar are in English for now. More languages are coming soon.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("original.englishOnly")
            }
        }
        .padding(.bottom, 6)
        .sheet(isPresented: $showsSource) {
            OriginalSourceSheet(language: language, greek: greek, translation: translation)
        }
    }

    @ViewBuilder
    private var titles: some View {
        if originalOnly {
            column(title: chapterID.description(in: translation.language), subtitle: "\(languageName) · \(sourceName)")
        } else if sideBySide {
            HStack(alignment: .firstTextBaseline) {
                column(title: chapterID.description(in: translation.language), subtitle: translation.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                column(title: languageName, subtitle: sourceName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 25)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(translation.abbreviation) and \(languageName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                Text(sourceName)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private func column(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(settings.preferences.font.font(size: 22, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private var interlinearButton: some View {
        Button {
            interlinear.toggle()
        } label: {
            Label("Interlinear", systemImage: interlinear ? "checkmark.circle.fill" : "circle")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(interlinear ? palette.accent : palette.secondaryText)
        .accessibilityHint("Shows each word's transliteration and meaning beneath it")
        .accessibilityAddTraits(interlinear ? .isSelected : [])
        .accessibilityIdentifier("original.interlinear")
    }

    /// Hides the translation so only the Hebrew or Greek is read.
    private var originalOnlyButton: some View {
        Button {
            originalOnly.toggle()
        } label: {
            Label(originalOnlyTitle, systemImage: originalOnly ? "checkmark.circle.fill" : "circle")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(originalOnly ? palette.accent : palette.secondaryText)
        .accessibilityHint("Hides the translation beside the original")
        .accessibilityAddTraits(originalOnly ? .isSelected : [])
        .accessibilityIdentifier("original.only")
    }

    private var originalOnlyTitle: String {
        language == .greek ? String(localized: "Greek Only") : String(localized: "Hebrew Only")
    }

    /// Opens `OriginalSourceSheet`: about the edition and its source.
    private var sourceButton: some View {
        Button {
            showsSource = true
        } label: {
            Label(sourceButtonTitle, systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(palette.secondaryText)
        .accessibilityIdentifier("original.sourceInfo")
    }

    private var sourceButtonTitle: String {
        language == .greek ? String(localized: "About the Greek") : String(localized: "About the Hebrew")
    }

    private var languageName: String {
        language == .greek ? String(localized: "Greek") : String(localized: "Hebrew")
    }

    /// The edition the words come from: "Greek: Textus Receptus (the KJV's source)".
    private var sourceName: String {
        OriginalSourceText.heading(language: language, greek: greek, translation: translation)
    }
}

/// How the Original parallel Bible names its source text.
enum OriginalSourceText {
    /// "Hebrew: Leningrad Codex", "Greek: Textus Receptus (the KJV's source)",
    /// "Greek: Westcott–Hort (closest to the ASV's source)".
    static func heading(language: OriginalLanguage, greek: OriginalSource.Greek, translation: Translation) -> String {
        guard language == .greek else { return String(localized: "Hebrew: Leningrad Codex") }
        let name = greek.edition.name
        let bible = translation.abbreviation
        return greek.isExact
            ? String(localized: "Greek: \(name) (the \(bible)'s source)")
            : String(localized: "Greek: \(name) (closest to the \(bible)'s source)")
    }
}
