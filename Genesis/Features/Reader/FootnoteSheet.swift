import SwiftUI

/// A translator's footnote the person tapped in the reader.
struct ShownFootnote: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let verse: VerseID?
}

/// A footnote, shown apart from the text: the verse it belongs to and the
/// note exactly as the translation gives it. Biblica's licence requires
/// every footnote to be included and accessible to the reader.
struct FootnoteSheet: View {
    let footnote: ShownFootnote
    let translation: Translation

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private var reference: String? {
        footnote.verse.flatMap { PassageReference(verses: [$0]) }?.description(in: translation.language)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let reference {
                        Text("\(reference) · \(translation.abbreviation)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.accent)
                    }
                    Text(footnote.text)
                        .font(.body)
                        .foregroundStyle(palette.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("footnote.text")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(palette.background)
            .navigationTitle(Text("Footnote"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.3), .medium])
        .presentationDragIndicator(.visible)
    }
}
