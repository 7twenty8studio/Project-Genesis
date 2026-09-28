import SwiftUI

/// Related passages for a verse, strongest links first, with each passage's
/// text from the current translation.
struct CrossReferencesView: View {
    let verse: VerseID
    let onOpen: (VerseID) -> Void

    @Environment(BibleLibrary.self) private var library
    @Environment(\.palette) private var palette
    @State private var items: [Item] = []
    @State private var sourceText = ""

    struct Item: Identifiable {
        let reference: CrossReference
        let text: String
        var id: Int { reference.id }
    }

    var body: some View {
        List {
            Section {
                VerseSnippet(reference: PassageReference(verse: verse).description, text: sourceText, lineLimit: nil)
                    .listRowBackground(palette.surface)
            }

            Section {
                if items.isEmpty {
                    Text("No cross references for this verse.")
                        .foregroundStyle(palette.secondaryText)
                        .listRowBackground(palette.surface)
                }
                ForEach(items) { item in
                    Button {
                        onOpen(item.reference.target)
                    } label: {
                        VerseSnippet(reference: item.reference.reference.description, text: item.text)
                    }
                    .listRowBackground(palette.surface)
                }
            } header: {
                Text("Related passages")
            } footer: {
                Text(CrossReferenceRepository.attribution)
            }
        }
        .themedScreen()
        .navigationTitle("Cross References")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: verse) { load() }
        .task(id: library.currentTranslation) { load() }
    }

    private func load() {
        let repository = library.current
        sourceText = (try? repository.verse(verse))?.plainText ?? ""
        let references = (try? library.crossReferences?.references(from: verse)) ?? []
        items = references.map { reference in
            let passage = (try? repository.verses(from: reference.target, through: reference.targetEnd)) ?? []
            let text = passage.prefix(3).map(\.plainText).joined(separator: " ") + (passage.count > 3 ? " \u{2026}" : "")
            return Item(reference: reference, text: text)
        }
    }
}
