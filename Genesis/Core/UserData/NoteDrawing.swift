import Foundation

/// Size rules for a note's handwritten page (PencilKit data).
///
/// Drawings sync as base64 text in `public.notes.drawing`, which the database
/// caps at 2 MB (see supabase/migrations/20261010000000_note_drawings.sql).
/// A larger drawing stays on its device: the note's text still syncs, the
/// drawing is left out of the push, and a pull never replaces it with nothing.
enum NoteDrawing {
    /// The database's limit on the base64 text, in bytes.
    static let maxSyncedBase64Length = 2_097_152

    /// Length of `data.base64EncodedString()` for this many bytes.
    static func base64Length(byteCount: Int) -> Int {
        ((byteCount + 2) / 3) * 4
    }

    /// True when the drawing (or no drawing) can go to the server.
    static func fitsSync(_ data: Data?) -> Bool {
        guard let data else { return true }
        return base64Length(byteCount: data.count) <= maxSyncedBase64Length
    }
}
