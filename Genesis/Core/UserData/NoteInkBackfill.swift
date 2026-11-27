import Foundation

/// Pages saved before notes.ink existed have no Versely Ink on the server,
/// so Android can't show them. The first sync after pages start syncing as
/// ink (`VerselyInk.syncs`) pushes every note with a page once per account
/// on this device, without changing its edit time.
enum NoteInkBackfill {
    /// Per-account defaults key part (SyncService adds the account).
    static let key = "notes.inkBackfilled"

    static func isDue(syncs: Bool, done: Bool) -> Bool {
        syncs && !done
    }
}
