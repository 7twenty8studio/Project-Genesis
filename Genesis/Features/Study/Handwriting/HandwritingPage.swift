import PencilKit
import SwiftUI

/// Which page of a note the editor shows.
enum NotePage: Hashable {
    case text, handwriting
}

/// A note's handwritten page: paper choice, a clear button and the canvas.
struct HandwritingPage: View {
    let initialData: Data?
    let autosave: DrawingAutosave
    /// True when the saved page is over the sync limit (it stays on this device).
    let isTooLargeToSync: Bool
    let onSave: (Data?) -> Void

    @Environment(\.palette) private var palette
    @AppStorage("handwriting.paper") private var paper: PaperStyle = .lined
    @State private var clearRequest = 0
    @State private var confirmClear = false
    @State private var isEmpty = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Paper", selection: $paper) {
                    ForEach(PaperStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("note.paper")
                Spacer()
                Button("Clear Page", systemImage: "trash", role: .destructive) { confirmClear = true }
                    .labelStyle(.iconOnly)
                    .disabled(isEmpty)
                    .accessibilityIdentifier("note.clearDrawing")
            }

            if isTooLargeToSync {
                Label("This page is too large to sync, so it stays on this device.", systemImage: "icloud.slash")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }

            HandwritingCanvas(
                initialData: initialData,
                paper: paper,
                palette: palette,
                clearRequest: clearRequest
            ) { drawing in
                isEmpty = drawing.strokes.isEmpty
                autosave.drawingChanged(drawing, write: onSave)
            }
            .frame(maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.separator, lineWidth: 1)
            }
        }
        .onAppear { isEmpty = initialData == nil }
        .confirmationDialog("Clear this page?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Page", role: .destructive) { clearRequest += 1 }
        } message: {
            Text("Your handwriting on this page will be removed.")
        }
    }
}
