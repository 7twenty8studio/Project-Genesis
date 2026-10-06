import SwiftUI

/// A note in Home's and Library's lists: the note's summary, with a small
/// picture of its handwritten page when it has one.
struct NoteListRow: View {
    let note: Note

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            NoteRow(note: note)
                .frame(maxWidth: .infinity, alignment: .leading)
            NoteDrawingThumbnail(note: note)
        }
    }
}
