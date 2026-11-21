import SwiftUI

/// Memorize's Bible menu: Automatic (the Bible being read, or its
/// public-domain stand-in beside a YouVersion Bible) or any Bible Memorize
/// may use (`BibleLibrary.memoriseBibles`), grouped by language.
struct MemoriseBiblePicker: View {
    @Environment(BibleLibrary.self) private var library

    var body: some View {
        Picker(selection: selection) {
            Text("Automatic (\(library.premiumToolsTranslation.abbreviation))")
                .tag(Self.automatic)
            ForEach(ReadingLibrary.groups(library.memoriseBibles, current: library.memoriseTranslation)) { group in
                Section(AppLanguage.displayName(group.language)) {
                    ForEach(group.translations) { translation in
                        Text("\(translation.abbreviation) · \(translation.name)")
                            .tag(translation.id)
                    }
                }
            }
        } label: {
            Text("Memorize In")
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("memorise.bible")
    }

    private static let automatic = ""

    private var selection: Binding<String> {
        Binding(
            get: { library.chosenMemoriseTranslation?.id ?? Self.automatic },
            set: { library.memoriseTranslationID = $0 == Self.automatic ? nil : $0 }
        )
    }
}
