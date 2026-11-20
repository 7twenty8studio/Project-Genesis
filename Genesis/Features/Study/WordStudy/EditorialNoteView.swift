import SwiftUI

/// Versely's own note on a commentary passage (editorial_notes in
/// WordStudy.sqlite), shown before the paragraph it's about and set apart
/// from the commentary: a rule down the side, the accent colour, an icon,
/// so it never reads as Henry's words. The text arrives in the app's
/// language from the database.
struct EditorialNoteView: View {
    let text: String

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.bubble")
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.accent)
                .frame(width: 3)
                .padding(.vertical, 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wordStudy.editorialNote")
    }
}
