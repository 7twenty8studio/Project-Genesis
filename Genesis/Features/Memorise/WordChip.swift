import SwiftUI

/// A word from the verse as a quiet rounded chip, set in the reader's font.
struct WordChip: View {
    let text: String
    var isEmphasised = false

    @Environment(\.palette) private var palette
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        Text(text)
            .font(settings.preferences.font.font(size: 19))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isEmphasised ? palette.accent : palette.separator, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A small sideways shake for a wrong tap. Animate `shakes` up by one per
/// mistake; with Reduce Motion, leave it at zero.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    // Nonisolated so they satisfy the protocol whatever its isolation.
    nonisolated var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    nonisolated func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(shakes * .pi * 4), y: 0))
    }
}

/// The verse in full once a game is solved: the exact text from the Bible.
struct SolvedPassage: View {
    let text: String

    @Environment(\.palette) private var palette
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        Text(text)
            .font(settings.preferences.font.font(size: 21))
            .foregroundStyle(palette.text)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("memorise.game.solved")
    }
}
