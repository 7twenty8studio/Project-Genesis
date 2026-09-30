import SwiftUI
import UIKit

/// Appears when verses are selected (long-press a verse). Highlight, note,
/// bookmark, copy, share and cross references.
struct SelectionActionBar: View {
    let onNote: () -> Void
    let onCrossReferences: () -> Void
    let onExplain: () -> Void

    @Environment(ReaderViewModel.self) private var reader
    @Environment(\.palette) private var palette
    @State private var copied = false
    @State private var highlightTrigger = 0

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(reader.selectedReference?.description ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .accessibilityIdentifier("selection.reference")
                Spacer()
                Button(action: onExplain) {
                    Label("Explain", systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("selection.explain")
                Button {
                    reader.clearSelection()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Done selecting")
                .accessibilityIdentifier("selection.done")
            }

            HStack(spacing: 12) {
                ForEach(HighlightColor.allCases) { color in
                    Button {
                        highlightTrigger += 1
                        reader.highlightSelection(color)
                    } label: {
                        Circle()
                            .fill(color.swatch)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(palette.separator, lineWidth: 1))
                    }
                    .accessibilityLabel("Highlight \(color.title)")
                    .accessibilityIdentifier("selection.highlight.\(color.rawValue)")
                }
                Button {
                    reader.removeHighlightFromSelection()
                } label: {
                    Image(systemName: "eraser")
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Remove highlight")
                .accessibilityIdentifier("selection.removeHighlight")
            }

            HStack {
                action("Note", systemImage: "note.text.badge.plus", perform: onNote)
                    .accessibilityIdentifier("selection.note")
                action("Bookmark", systemImage: "bookmark") { reader.toggleBookmark() }
                    .accessibilityIdentifier("selection.bookmark")
                action(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = reader.shareTextForSelection
                    copied = true
                }
                .accessibilityIdentifier("selection.copy")
                ShareLink(item: reader.shareTextForSelection) {
                    actionLabel("Share", systemImage: "square.and.arrow.up")
                }
                if reader.selection.count == 1 {
                    action("Related", systemImage: "arrow.triangle.branch", perform: onCrossReferences)
                        .accessibilityIdentifier("selection.related")
                }
            }
        }
        .foregroundStyle(palette.text)
        .padding(18)
        .frame(maxWidth: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
        .sensoryFeedback(.impact(weight: .light), trigger: highlightTrigger)
        .onChange(of: reader.selection) { copied = false }
    }

    private func action(_ title: String, systemImage: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            actionLabel(title, systemImage: systemImage)
        }
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.body)
            Text(title)
                .font(.caption2)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
}
