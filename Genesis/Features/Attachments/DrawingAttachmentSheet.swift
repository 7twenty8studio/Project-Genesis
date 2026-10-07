import PencilKit
import SwiftUI

/// A Pencil page for sermon notes (Apple Pencil on iPad, a finger on iPhone),
/// using the same page as handwritten notes. Saved when closed.
struct DrawingAttachmentSheet: View {
    /// The page's saved drawing, or nil for a new page.
    let initialData: Data?
    let onSave: (Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var autosave = DrawingAutosave(delay: .seconds(60))
    @State private var latest: Data?
    @State private var changed = false

    var body: some View {
        NavigationStack {
            HandwritingPage(initialData: initialData, autosave: autosave, isTooLargeToSync: false) { data in
                latest = data
                changed = true
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .themedScreen()
            .navigationTitle("Drawing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { finish() }
                        .accessibilityIdentifier("drawing.done")
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func finish() {
        // Writes the page the person sees now, even mid-pause.
        autosave.flush()
        if changed { onSave(latest) }
        dismiss()
    }
}
