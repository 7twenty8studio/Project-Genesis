import SwiftUI

/// An optional reflection prompt at the top of a new journal entry. Tap it
/// to start the entry with it, ask for another, or put it away.
struct JournalPromptCard: View {
    let prompt: String
    let onUse: () -> Void
    let onAnother: () -> Void
    let onDismiss: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onUse) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reflection prompt")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                    Text(prompt)
                        .font(.body)
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Starts your entry with this prompt."))
            .accessibilityIdentifier("note.prompt")

            Button("Another prompt", systemImage: "shuffle", action: onAnother)
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("note.prompt.another")
            Button("Dismiss prompt", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("note.prompt.dismiss")
        }
        .foregroundStyle(palette.accent)
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
