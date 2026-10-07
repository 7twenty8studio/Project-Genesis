import SwiftUI

/// About the text in the Original parallel Bible's second column: which
/// Hebrew or Greek edition it is, how it relates to the Bible being read,
/// what its spelling follows, and where the data comes from.
struct OriginalSourceSheet: View {
    let language: OriginalLanguage
    let greek: OriginalSource.Greek
    let translation: Translation

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ThemedRows {
                    Section(title) {
                        ForEach(sentences, id: \.self) { sentence in
                            Text(sentence)
                                .foregroundStyle(palette.text)
                        }
                    }
                    .listRowBackground(palette.surface)
                    Section("Source") {
                        Text(credit)
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.surface)
                }
            }
            .themedScreen()
            .navigationTitle(OriginalSourceText.heading(language: language, greek: greek, translation: translation))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("originalSource.done")
                }
            }
        }
    }

    private var title: String {
        language == .greek ? greek.edition.fullName : String(localized: "Leningrad Codex (about 1008)")
    }

    /// One or two sentences about the edition, then how the Bible relates
    /// to it, then what its spelling, order and punctuation follow.
    private var sentences: [String] {
        guard language == .greek else {
            return [
                String(localized: "The oldest complete manuscript of the Hebrew Bible, and the basis of printed Hebrew Bibles today."),
                String(localized: "Where the written text and the traditional reading differ, the reading is shown, as the KJV translates it."),
            ]
        }
        let edition = greek.edition
        let bible = translation.abbreviation
        var lines = [edition.about]
        lines.append(greek.isExact
            ? String(localized: "The \(bible) was translated from this text.")
            : String(localized: "The \(bible) was translated from a Greek text very close to this one; this is the closest edition available here."))
        lines.append(edition.spelling)
        if edition != .nestleAland {
            lines.append(String(localized: "Word order follows STEPBible's notes on this edition; where a whole phrase is rearranged, it may differ slightly from the printed edition."))
        }
        lines.append(String(localized: "Punctuation follows the Tyndale House Greek New Testament."))
        return lines
    }

    private var credit: String {
        language == .greek
            ? String(localized: "Greek text from STEPBible TAGNT (Translators Amalgamated Greek New Testament), created by STEPBible.org based on work at Tyndale House Cambridge, CC BY 4.0.")
            : String(localized: "Hebrew text from STEPBible TAHOT (Translators Amalgamated Hebrew Old Testament), created by STEPBible.org based on work at Tyndale House Cambridge, CC BY 4.0.")
    }
}
