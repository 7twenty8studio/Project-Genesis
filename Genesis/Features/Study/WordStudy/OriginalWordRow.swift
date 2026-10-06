import SwiftUI

/// One Hebrew or Greek word: as written, transliterated, its English gloss
/// and Strong's number.
struct OriginalWordRow: View {
    let word: OriginalWord

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(word.text)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(palette.text)
                Text(word.transliteration)
                    .font(.caption.italic())
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(word.gloss)
                    .font(.subheadline)
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(.trailing)
                if let strongs = word.strongs {
                    Text(strongs)
                        .font(.caption2.monospaced())
                        .foregroundStyle(palette.accent)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wordStudy.word")
    }
}
