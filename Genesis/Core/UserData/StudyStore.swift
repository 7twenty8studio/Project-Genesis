import Foundation
import SwiftData

/// Creates, changes and removes highlights, bookmarks and notes.
/// Views read with `@Query`; all writes go through here.
@MainActor
struct StudyStore {
    let context: ModelContext

    // MARK: Highlights

    func highlights(for verses: some Collection<VerseID>) -> [Highlight] {
        let raws = verses.map(\.rawValue)
        let descriptor = FetchDescriptor<Highlight>(predicate: #Predicate { raws.contains($0.verseRaw) })
        return (try? context.fetch(descriptor)) ?? []
    }

    func highlight(_ verses: some Collection<VerseID>, color: HighlightColor) {
        let existing = Dictionary(highlights(for: verses).map { ($0.verseRaw, $0) }, uniquingKeysWith: { first, _ in first })
        let now = Date.now
        for verse in verses {
            if let highlight = existing[verse.rawValue] {
                highlight.color = color
                highlight.updatedAt = now
            } else {
                context.insert(Highlight(verse: verse, color: color, date: now))
            }
        }
        save()
    }

    func removeHighlights(_ verses: some Collection<VerseID>) {
        for highlight in highlights(for: verses) {
            delete(highlight)
        }
        save()
    }

    /// Deletes a highlight and records the deletion for sync. Doesn't save.
    func delete(_ highlight: Highlight) {
        recordDeletion(of: highlight.id, in: SyncTable.highlights)
        context.delete(highlight)
    }

    func highlightColors(in chapter: ChapterID) -> [VerseID: HighlightColor] {
        let range = chapter.verseRange
        let low = range.lowerBound
        let high = range.upperBound
        let descriptor = FetchDescriptor<Highlight>(predicate: #Predicate { $0.verseRaw >= low && $0.verseRaw <= high })
        let highlights = (try? context.fetch(descriptor)) ?? []
        return Dictionary(highlights.map { ($0.verse, $0.color) }, uniquingKeysWith: { first, _ in first })
    }

    func add(_ highlights: [Highlight], to collection: HighlightCollection?) {
        for highlight in highlights {
            highlight.collection = collection
            highlight.updatedAt = .now
        }
        save()
    }

    @discardableResult
    func createCollection(named name: String) -> HighlightCollection {
        let collection = HighlightCollection(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(collection)
        save()
        return collection
    }

    // MARK: Bookmarks

    func bookmarks(in chapter: ChapterID) -> [Bookmark] {
        let range = chapter.verseRange
        let low = range.lowerBound
        let high = range.upperBound
        let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.verseRaw >= low && $0.verseRaw <= high })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Adds a bookmark at `verse`, or removes the chapter's bookmarks if one exists.
    /// Returns true when a bookmark was added.
    @discardableResult
    func toggleBookmark(at verse: VerseID) -> Bool {
        let existing = bookmarks(in: verse.chapterID)
        if existing.isEmpty {
            context.insert(Bookmark(verse: verse))
            save()
            return true
        }
        for bookmark in existing {
            recordDeletion(of: bookmark.id, in: SyncTable.bookmarks)
            context.delete(bookmark)
        }
        save()
        return false
    }

    // MARK: Notes

    func notes(in chapter: ChapterID) -> [Note] {
        // Optionals, to match the optional model properties in the predicate.
        let book: Int? = chapter.book
        let number: Int? = chapter.chapter
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.bookNumber == book && $0.chapterNumber == number },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func createNote(kind: NoteKind, anchor: NoteAnchor, title: String = "", body: String = "") -> Note {
        let note = Note(kind: kind, anchor: anchor, title: title, body: body)
        context.insert(note)
        save()
        return note
    }

    func delete(_ note: Note) {
        recordDeletion(of: note.id, in: SyncTable.notes)
        context.delete(note)
        save()
    }

    func delete(_ bookmark: Bookmark) {
        recordDeletion(of: bookmark.id, in: SyncTable.bookmarks)
        context.delete(bookmark)
        save()
    }

    func delete(_ collection: HighlightCollection) {
        for highlight in collection.highlights {
            highlight.collection = nil
            highlight.updatedAt = .now
        }
        recordDeletion(of: collection.id, in: SyncTable.highlightCollections)
        context.delete(collection)
        save()
    }

    /// Remembers a deletion so sync can tell the cloud. Cheap, so it is
    /// recorded even for guests (their first sign-in sends it).
    func recordDeletion(of id: UUID, in table: String) {
        let key = id
        let existing = (try? context.fetch(FetchDescriptor<Tombstone>(predicate: #Predicate { $0.recordID == key }))) ?? []
        guard existing.isEmpty else { return }
        context.insert(Tombstone(recordID: id, table: table))
    }

    func save() {
        do {
            try context.save()
            NotificationCenter.default.post(name: .genesisUserDataDidChange, object: nil)
        } catch {
            CrashReporter.record(error, context: "StudyStore.save")
        }
    }
}

extension Notification.Name {
    /// Posted after personal data is saved; sync listens for it.
    static let genesisUserDataDidChange = Notification.Name("genesisUserDataDidChange")
}
