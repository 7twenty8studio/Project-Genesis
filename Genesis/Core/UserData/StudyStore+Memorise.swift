import Foundation
import SwiftData

extension StudyStore {
    // MARK: Memorise Scripture

    func memoryVerses() -> [MemoryVerse] {
        (try? context.fetch(FetchDescriptor<MemoryVerse>(sortBy: [SortDescriptor(\.dueAt)]))) ?? []
    }

    func dueMemoryVerses(on date: Date = .now) -> [MemoryVerse] {
        let now = date
        let descriptor = FetchDescriptor<MemoryVerse>(predicate: #Predicate { $0.dueAt <= now }, sortBy: [SortDescriptor(\.dueAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Adds a passage to learn, or returns the one already there.
    @discardableResult
    func memorise(from start: VerseID, through end: VerseID, translationID: String) -> MemoryVerse {
        let first = start.rawValue
        let last = end.rawValue
        let existing = (try? context.fetch(FetchDescriptor<MemoryVerse>(predicate: #Predicate { $0.startRaw == first && $0.endRaw == last }))) ?? []
        if let found = existing.first { return found }
        let verse = MemoryVerse(start: start, end: end, translationID: translationID)
        context.insert(verse)
        save()
        return verse
    }

    func review(_ verse: MemoryVerse, _ grade: MemoryGrade, at now: Date = .now) {
        verse.schedule = verse.schedule.reviewed(grade, at: now)
        verse.lastReviewedAt = now
        verse.reviewCount += 1
        verse.updatedAt = now
        save()
    }

    func changeTranslation(of verse: MemoryVerse, to translationID: String) {
        verse.translationID = translationID
        verse.updatedAt = .now
        save()
    }

    func delete(_ verse: MemoryVerse) {
        recordDeletion(of: verse.id, in: SyncTable.memoryVerses)
        context.delete(verse)
        save()
    }
}
