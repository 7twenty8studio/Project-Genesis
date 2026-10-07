import SwiftUI

/// Word Order for one passage: each verse's own words, shuffled as chips, to
/// tap back in order (a passage of several verses goes one verse at a time).
/// A wrong chip shakes gently and doesn't advance.
struct WordOrderBoard: View {
    let verseTexts: [String]
    /// Mistakes and chips placed, once every verse is rebuilt.
    let onSolved: (_ mistakes: Int, _ steps: Int) -> Void

    @Environment(\.palette) private var palette
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stage = 0
    @State private var game: WordOrderGame
    @State private var earlierMistakes = 0
    @State private var earlierSteps = 0
    @State private var shaking: Int?
    @State private var shakes: CGFloat = 0

    init(verseTexts: [String], onSolved: @escaping (_ mistakes: Int, _ steps: Int) -> Void) {
        self.verseTexts = verseTexts
        self.onSolved = onSolved
        _game = State(initialValue: WordOrderGame(text: verseTexts.first ?? "", seed: MemoryGame.randomSeed()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView {
                Text(builtSoFar)
                    .font(settings.preferences.font.font(size: 21))
                    .foregroundStyle(palette.text)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("memorise.wordOrder.built")
            }
            .frame(maxHeight: .infinity)

            if verseTexts.count > 1 {
                Text("Verse \(stage + 1) of \(verseTexts.count)")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            FlowLayout(spacing: 8) {
                ForEach(Array(game.shuffled.enumerated()), id: \.offset) { position, index in
                    if !game.isPlaced(index) {
                        Button {
                            tap(index)
                        } label: {
                            WordChip(text: game.words.tokens[index].text)
                        }
                        .buttonStyle(.plain)
                        .modifier(ShakeEffect(shakes: shaking == index ? shakes : 0))
                        .accessibilityIdentifier("memorise.chip.\(position)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sensoryFeedback(.selection, trigger: game.placed.count) { old, new in new > old }
        .sensoryFeedback(.impact(weight: .light), trigger: game.mistakes) { old, new in new > old }
    }

    /// Earlier verses of the passage (already rebuilt) and this one so far.
    private var builtSoFar: String {
        (verseTexts.prefix(stage) + [game.builtText]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func tap(_ index: Int) {
        if game.tap(index) {
            guard game.isSolved else { return }
            earlierMistakes += game.mistakes
            earlierSteps += game.words.tokens.count
            if stage + 1 < verseTexts.count {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    stage += 1
                    game = WordOrderGame(text: verseTexts[stage], seed: MemoryGame.randomSeed())
                }
            } else {
                onSolved(earlierMistakes, earlierSteps)
            }
        } else if !reduceMotion {
            // Whole numbers rest in place, so each mistake animates one shake.
            shaking = index
            withAnimation(.linear(duration: 0.3)) { shakes += 1 }
        }
    }
}
