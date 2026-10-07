import SwiftUI

/// One word of an interlinear verse: the Hebrew or Greek verbatim, its
/// transliteration and its English gloss in this verse.
struct InterlinearWordView: View {
    let word: OriginalWord
    let fontSize: CGFloat

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 2) {
            Text(OriginalText.display(word.text))
                .font(OriginalFont.font(for: word.language, size: OriginalFont.readingSize(fontSize, language: word.language)))
                .foregroundStyle(palette.text)
                .underline(word.isNotInComparison, pattern: .dot, color: palette.accent)
            Text(word.transliteration)
                .font(.caption.italic())
                .foregroundStyle(palette.secondaryText)
            Text(word.gloss)
                .font(.caption)
                .foregroundStyle(palette.accent)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Lays words out in lines that wrap, left to right or (Hebrew) right to
/// left; no word is wider than `maximumWordWidth`, so long glosses wrap
/// under their word. Placement is computed here (in a left-to-right
/// environment) rather than mirrored by the system.
struct InterlinearFlow: Layout {
    var rightToLeft: Bool
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 14
    var maximumWordWidth: CGFloat = 150

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = arrange(width: width, subviews: subviews)
        let height = lines.last.map { $0.y + $0.height } ?? 0
        let widest = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for line in arrange(width: bounds.width, subviews: subviews) {
            var x = rightToLeft ? bounds.maxX : bounds.minX
            for (index, size) in zip(line.indices, line.sizes) {
                if rightToLeft { x -= size.width }
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + line.y), proposal: ProposedViewSize(size))
                x += rightToLeft ? -spacing : size.width + spacing
            }
        }
    }

    private struct Line {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
        let cap = min(maximumWordWidth, width.isFinite ? width : maximumWordWidth)
        var lines: [Line] = []
        var current = Line()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: cap, height: nil))
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                lines.append(current)
                current = Line(y: current.y + current.height + lineSpacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
            current.sizes.append(size)
        }
        if !current.indices.isEmpty {
            lines.append(current)
        }
        return lines
    }
}
