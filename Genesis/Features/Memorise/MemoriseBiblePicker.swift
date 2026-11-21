import SwiftUI

/// Memorize's Bible menu: Automatic (the Bible being read, or its
/// public-domain stand-in beside a YouVersion Bible) or any Bible Memorize
/// may use (`BibleLibrary.memoriseBibles`), grouped by language. The row
/// shows only the abbreviation ("RV1909") so it stays on one line at every
/// text size; the menu lists full names.
struct MemoriseBiblePicker: View {
    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette

    var body: some View {
        LabeledContent {
            Menu {
                Picker(selection: selection) {
                    Text(automaticTitle)
                        .tag(Self.automatic)
                    ForEach(ReadingLibrary.groups(library.memoriseBibles, current: library.memoriseTranslation)) { group in
                        Section(AppLanguage.displayName(group.language)) {
                            ForEach(group.translations) { translation in
                                Text(verbatim: "\(translation.abbreviation) · \(translation.name)")
                                    .tag(translation.id)
                            }
                        }
                    }
                } label: {
                    Text("Memorize In")
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: shortTitle)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(palette.accent)
                .fixedSize()
            }
            .accessibilityLabel(Text("Memorize In"))
            .accessibilityValue(Text(verbatim: fullTitle))
            .accessibilityIdentifier("memorise.bible")
        } label: {
            Text("Memorize In")
                .foregroundStyle(palette.text)
                .lineLimit(1)
        }
    }

    private static let automatic = ""

    private var automaticTitle: String {
        String(localized: "Automatic (\(library.premiumToolsTranslation.abbreviation))")
    }

    /// The row: "RV1909", or "Automatic (KJV)".
    private var shortTitle: String {
        library.chosenMemoriseTranslation?.abbreviation ?? automaticTitle
    }

    /// For VoiceOver: the Bible's full name.
    private var fullTitle: String {
        guard let chosen = library.chosenMemoriseTranslation else { return automaticTitle }
        return "\(chosen.abbreviation) · \(chosen.name)"
    }

    private var selection: Binding<String> {
        Binding(
            get: { library.chosenMemoriseTranslation?.id ?? Self.automatic },
            set: { library.memoriseTranslationID = $0 == Self.automatic ? nil : $0 }
        )
    }
}
