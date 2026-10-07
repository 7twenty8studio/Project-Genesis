import SwiftUI

/// Fill the Gaps for one passage: the verse with some words hidden; choose
/// each hidden word in turn from a few of the verse's own words. The better
/// the passage is known, the more gaps (`MemoryGame.gapCount`).
struct FillGapsBoard: View {
    /// Mistakes and gaps filled, once every gap is filled.
    let onSolved: (_ mistakes: Int, _ steps: Int) -> Void

    @Environment(\.palette) private var palette
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var game: FillGapsGame
    @State private var shaking: String?
    @State private var shakes: CGFloat = 0

    init(text: String, mastery: MemoryMastery, nearby: [String], onSolved: @escaping (_ mistakes: Int, _ steps: Int) -> Void) {
        self.onSolved = onSolved
        _game = State(initialValue: FillGapsGame(text: text, mastery: mastery, nearby: nearby, seed: MemoryGame.randomSeed()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView {
                FlowLayout(spacing: 6) {
                    ForEach(Array(game.words.tokens.enumerated()), id: \.offset) { index, token in
                        word(token, at: index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            if !game.isSolved {
                Text("Choose the missing word.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                FlowLayout(spacing: 8) {
                    ForEach(Array(game.currentChoices.enumerated()), id: \.offset) { position, choice in
                        Button {
                            choose(choice)
                        } label: {
                            WordChip(text: choice)
                        }
                        .buttonStyle(.plain)
                        .modifier(ShakeEffect(shakes: shaking == choice ? shakes : 0))
                        .accessibilityIdentifier("memorise.choice.\(position)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sensoryFeedback(.selection, trigger: game.filled) { old, new in new > old }
        .sensoryFeedback(.impact(weight: .light), trigger: game.mistakes) { old, new in new > old }
    }

    @ViewBuilder
    private func word(_ token: VerseToken, at index: Int) -> some View {
        let font = settings.preferences.font.font(size: 21)
        if game.isHidden(index) {
            let isCurrent = game.currentGap == index
            HStack(spacing: 0) {
                Text(token.leadingPunctuation)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isCurrent ? palette.accent.opacity(0.18) : palette.separator.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isCurrent ? palette.accent : .clear, lineWidth: 1)
                    )
                    .frame(width: 64, height: 26)
                Text(token.trailingPunctuation)
            }
            .font(font)
            .foregroundStyle(palette.text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isCurrent ? String(localized: "Missing word, choose it below") : String(localized: "Missing word"))
        } else {
            Text(token.text)
                .font(font)
                .foregroundStyle(game.wasFilled(index) ? palette.accent : palette.text)
        }
    }

    private func choose(_ choice: String) {
        let wasRight = withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { game.choose(choice) }
        if wasRight {
            if game.isSolved { onSolved(game.mistakes, game.gaps.count) }
        } else if !reduceMotion {
            // Whole numbers rest in place, so each mistake animates one shake.
            shaking = choice
            withAnimation(.linear(duration: 0.3)) { shakes += 1 }
        }
    }
}
