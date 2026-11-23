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

    /// The member's saved work on this revision of the sermon's handout, if any.
    static func savedHandout(for sermon: PublishedSermon, in context: ModelContext) -> SermonHandout? {
        existing(for: sermon.id, in: context)?.handouts.last { $0.revision == sermon.revision }
    }

    /// Saves the member's answers on this revision of the handout with
    /// their notes (starting the notes the first time). The key goes with
    /// them only once revealed; a key saved earlier stays, even if the
    /// church hides it again. Other revisions' saved work is never changed.
    @discardableResult
    static func saveHandout(_ responses: [String: String], for sermon: PublishedSermon, in context: ModelContext) -> Sermon {
        let notes = notes(for: sermon, in: context)
        var saved = notes.handouts
        var copy = SermonHandout(sermon: sermon, responses: responses, keepKey: sermon.answers == .revealed)
        if let index = saved.lastIndex(where: { $0.sermonID == sermon.id && $0.revision == sermon.revision }) {
            if !copy.hasKey { copy.blanks = saved[index].blanks }
            saved[index] = copy
        } else {
            saved.append(copy)
        }
        notes.handouts = saved
        notes.updatedAt = .now
        try? context.save()
        return notes
    }

    /// Saves new answers on a saved handout (opened from Sermon Notes, even
    /// after the church unpublished it); its outline and key stay as saved.
    static func update(_ handout: SermonHandout, responses: [String: String], in notes: Sermon, context: ModelContext) {
        var saved = notes.handouts
        guard let index = saved.firstIndex(where: { $0.id == handout.id }) else { return }
        saved[index].responses = responses
        saved[index].savedAt = .now
        notes.handouts = saved
        notes.updatedAt = .now
        try? context.save()
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
