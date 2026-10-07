import SwiftUI

/// The top of the Original parallel Bible: what each column holds, the
/// Interlinear switch, and (New Testament) what the dotted words mean.
struct OriginalParallelHeader: View {
    let chapterID: ChapterID
    let translation: Translation
    let language: OriginalLanguage
    let sideBySide: Bool
    /// Some Greek words on the page differ between editions.
    let marksEditions: Bool
    @Binding var interlinear: Bool

    @Environment(ReaderSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titles
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("reader.parallel.originalHeader")
            interlinearButton
            if marksEditions {
                Text("Dotted words are in the Textus Receptus, the Greek the KJV translates, but not in the Nestle-Aland text most modern Bibles use.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var titles: some View {
        if sideBySide {
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

    private var languageName: String {
        language == .greek ? String(localized: "Greek") : String(localized: "Hebrew")
    }

    /// The edition the words come from.
    private var sourceName: String {
        language == .greek
            ? String(localized: "Textus Receptus (STEPBible TAGNT)")
            : String(localized: "Leningrad Codex (STEPBible TAHOT)")
    }
}
