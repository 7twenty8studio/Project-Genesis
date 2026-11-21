import Foundation
import SwiftData

/// A person's own notes on a church's sermon (VRS-18): an ordinary
/// `Sermon` in Sermon Notes, linked by `sourceSermonID`. They're private,
/// synced like any sermon note, and stay when the church unpublishes or
/// changes the sermon. The church's outline isn't copied into them; only
/// the details and the verified passages (verse ids, never text).
@MainActor
enum ChurchSermonNotes {
    /// The notes already started from this sermon, if any.
    static func existing(for sermonID: UUID, in context: ModelContext) -> Sermon? {
        let target: UUID? = sermonID
        var descriptor = FetchDescriptor<Sermon>(predicate: #Predicate { $0.sourceSermonID == target })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Opens the person's notes on this sermon, starting them the first time.
    static func notes(for sermon: PublishedSermon, in context: ModelContext) -> Sermon {
        if let notes = existing(for: sermon.id, in: context) { return notes }
        let notes = Sermon(church: sermon.church, preachedAt: sermon.preachedDate ?? .now)
        apply(sermon, to: notes)
        context.insert(notes)
        try? context.save()
        return notes
    }

    /// Fills new notes from the published sermon.
    static func apply(_ sermon: PublishedSermon, to notes: Sermon) {
        notes.sourceSermonID = sermon.id
        notes.title = sermon.title
        notes.preacher = sermon.speaker
        notes.church = sermon.church
        notes.series = sermon.series
        notes.passages = Array(sermon.passages.prefix(Sermon.maximumPassages))
        notes.updatedAt = .now
    }
}
