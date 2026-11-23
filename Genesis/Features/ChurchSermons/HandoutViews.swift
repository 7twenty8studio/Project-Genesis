import SwiftUI

/// The church's words with each "[[n]]" shown as a blank, and a box under
/// them for each blank in that text. Plain words outside a handout.
struct HandoutText: View {
    let text: String
    let font: Font

    @Environment(HandoutModel.self) private var handout: HandoutModel?
    @Environment(\.palette) private var palette

    var body: some View {
        if let handout {
            let numbers = SermonBlanks.numbers(in: text, known: handout.known.contains)
            VStack(alignment: .leading, spacing: 8) {
                Text(attributed(handout))
                    .font(font)
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(numbers, id: \.self) { n in
                    BlankField(n: n)
                }
            }
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The text with each blank as the member's words (or a line), underlined and numbered.
    private func attributed(_ handout: HandoutModel) -> AttributedString {
        var out = AttributedString()
        for piece in SermonBlanks.pieces(text, known: handout.known.contains) {
            switch piece {
            case let .text(words):
                out += AttributedString(words)
            case let .blank(n):
                let words = handout.value(n)
                var mark = AttributedString(words.isEmpty ? "\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}" : words)
                mark.underlineStyle = .single
                mark.foregroundColor = palette.accent
                var number = AttributedString("\(n)")
                number.font = .caption2.weight(.bold)
                number.baselineOffset = 6
                number.foregroundColor = palette.secondaryText
                out += mark + number
            }
        }
        return out
    }
}

/// One blank's box: the member's words, then right or not yet once
/// checked, and the key's word while Show Answers is on.
struct BlankField: View {
    let n: Int

    @Environment(HandoutModel.self) private var handout: HandoutModel?
    @Environment(\.palette) private var palette

    var body: some View {
        if let handout, let blank = handout.blank(n) {
            let grade = handout.grade(n)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(n)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.secondaryText)
                    .frame(minWidth: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    TextField(
                        blank.hint ?? (blank.open ? String(localized: "Your own words") : String(localized: "Blank \(n)")),
                        text: Binding(get: { handout.value(n) }, set: { handout.set(n, $0) }),
                        axis: blank.open ? .vertical : .horizontal
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(palette.surface, in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(grade == true ? palette.accent : palette.accent.opacity(0.35), lineWidth: grade == true ? 2 : 1.5)
                    }
                    .accessibilityLabel(blank.open ? String(localized: "Blank \(n), your own words") : String(localized: "Blank \(n)"))
                    .accessibilityIdentifier("churchSermon.blank.\(n)")
                    if let grade {
                        Label(grade ? String(localized: "Correct") : String(localized: "Not yet"), systemImage: grade ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(grade ? palette.accent : palette.secondaryText)
                    }
                    if let answer = handout.shownAnswer(n) {
                        Text("Answer: \(answer)")
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            }
        }
    }
}

/// Under the handout: whether the answers are out, then Check Answers,
/// Show Answers and Practice Again (together, once the key is there).
struct HandoutBar: View {
    @Environment(HandoutModel.self) private var handout: HandoutModel?
    @Environment(\.palette) private var palette

    var body: some View {
        if let handout {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Handout")
                    .font(.headline)
                    .foregroundStyle(palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text(handout.status)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("churchSermon.handoutStatus")
                if handout.canCheck {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { buttons(handout) }
                        VStack(alignment: .leading, spacing: 8) { buttons(handout) }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: .rect(cornerRadius: 16))
            .padding(.top, 24)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func buttons(_ handout: HandoutModel) -> some View {
        Button("Check Answers", systemImage: "checkmark.circle") { handout.check() }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("churchSermon.checkAnswers")
        Button(handout.showing ? "Hide Answers" : "Show Answers", systemImage: handout.showing ? "eye.slash" : "eye") { handout.toggleShowing() }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("churchSermon.showAnswers")
        if handout.isPracticing {
            Button("Back to My Answers", systemImage: "arrow.uturn.backward") { handout.endPractice() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("churchSermon.backToMine")
        } else {
            Button("Practice Again", systemImage: "arrow.clockwise") { handout.startPractice() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("churchSermon.practice")
        }
    }
}
