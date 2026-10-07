import SwiftUI

/// The notes: a plain-text editor with buttons that add or remove Markdown
/// marks (bold, italic, heading, lists, quote), and a formatted preview.
struct SermonNotesEditor: View {
    @Binding var text: String
    @Binding var selection: TextSelection?
    var largeText = false

    @State private var isPreviewing = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            formatBar
            if isPreviewing {
                SermonMarkdownView(text: text, largeText: largeText)
                    .frame(minHeight: 120, alignment: .topLeading)
                    .accessibilityIdentifier("sermon.preview")
            } else {
                TextEditor(text: $text, selection: $selection)
                    .font(largeText ? .title2 : .body)
                    .foregroundStyle(palette.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: largeText ? 320 : 240)
                    .accessibilityLabel("Notes")
                    .accessibilityIdentifier("sermon.body")
            }
        }
    }

    private var formatBar: some View {
        HStack(spacing: 4) {
            ForEach(SermonMarkdown.Format.allCases) { format in
                Button {
                    apply(format)
                } label: {
                    Image(systemName: format.systemImage)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderless)
                .disabled(isPreviewing)
                .accessibilityLabel(format.title)
                .accessibilityIdentifier("sermon.format.\(format.rawValue)")
            }
            Spacer(minLength: 0)
            Button {
                isPreviewing.toggle()
            } label: {
                Image(systemName: isPreviewing ? "pencil" : "eye")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isPreviewing ? "Edit Notes" : "Preview Notes")
            .accessibilityIdentifier("sermon.previewToggle")
        }
        .foregroundStyle(palette.accent)
    }

    private func apply(_ format: SermonMarkdown.Format) {
        let end = text.count
        let range = SermonTextSelection.offsets(selection, in: text) ?? (end..<end)
        let edit = SermonMarkdown.apply(format, to: text, selection: range)
        text = edit.text
        selection = SermonTextSelection.selection(edit.selection, in: edit.text)
    }
}

/// Converts the editor's selection to Character offsets and back, so the
/// formatting logic stays pure (`SermonMarkdown`).
enum SermonTextSelection {
    static func offsets(_ selection: TextSelection?, in text: String) -> Range<Int>? {
        guard let selection, case let .selection(range) = selection.indices else { return nil }
        guard range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else { return nil }
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        let upper = text.distance(from: text.startIndex, to: range.upperBound)
        return lower..<max(lower, upper)
    }

    static func selection(_ range: Range<Int>, in text: String) -> TextSelection {
        let count = text.count
        let lower = text.index(text.startIndex, offsetBy: min(max(0, range.lowerBound), count))
        let upper = text.index(text.startIndex, offsetBy: min(max(0, range.upperBound), count))
        return lower == upper ? TextSelection(insertionPoint: lower) : TextSelection(range: lower..<upper)
    }
}

/// Sermon notes shown formatted, a line at a time.
struct SermonMarkdownView: View {
    let text: String
    var largeText = false

    @Environment(\.palette) private var palette

    var body: some View {
        let blocks = SermonMarkdown.blocks(text)
        VStack(alignment: .leading, spacing: 8) {
            if blocks.isEmpty {
                Text("No notes yet.")
                    .foregroundStyle(palette.secondaryText)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                SermonBlockView(block: block, largeText: largeText)
            }
        }
        .font(largeText ? .title2 : .body)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SermonBlockView: View {
    let block: SermonMarkdown.Block
    let largeText: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        let content = Text(SermonMarkdown.inline(block.text))
        switch block.kind {
        case .heading:
            content
                .font(.system(largeText ? .title : .title3, design: .serif, weight: .semibold))
                .foregroundStyle(palette.text)
                .padding(.top, 4)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\u{2022}").foregroundStyle(palette.accent)
                content.foregroundStyle(palette.text)
            }
        case let .numbered(number):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(number).").foregroundStyle(palette.accent).monospacedDigit()
                content.foregroundStyle(palette.text)
            }
        case .quote:
            HStack(spacing: 10) {
                Capsule().fill(palette.accent).frame(width: 3)
                content.italic().foregroundStyle(palette.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .paragraph:
            content.foregroundStyle(palette.text)
        }
    }
}
