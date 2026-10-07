import Foundation
import SwiftData

// Reading plans and the prayer journal. Same rules as the rest of StudyStore:
// every change updates `updatedAt`, deletions leave a tombstone for sync.

extension StudyStore {
    // MARK: Reading plans

    @discardableResult
    func start(_ plan: ReadingPlan, on date: Date = .now) -> PlanEnrollment {
        let enrollment = PlanEnrollment(plan: plan, startDate: date)
        context.insert(enrollment)
        save()
        return enrollment
    }

    func setDay(_ day: Int, completed: Bool, in enrollment: PlanEnrollment) {
        var days = enrollment.completedDays
        if completed { days.insert(day) } else { days.remove(day) }
        enrollment.completedDays = days
        enrollment.updatedAt = .now
        save()
    }

    /// Starts the plan again from today, clearing progress.
    func restart(_ enrollment: PlanEnrollment, on date: Date = .now) {
        enrollment.completedDays = []
        enrollment.startDate = Calendar.current.startOfDay(for: date)
        enrollment.isActive = true
        enrollment.updatedAt = .now
        save()
    }

    func delete(_ enrollment: PlanEnrollment) {
        recordDeletion(of: enrollment.id, in: SyncTable.readingPlans)
        context.delete(enrollment)
        save()
    }

    // MARK: Prayer journal

    /// Prayers with any content (answered ones included).
    func prayerCount() -> Int {
        let descriptor = FetchDescriptor<Prayer>(predicate: #Predicate { $0.title != "" || $0.body != "" })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    @discardableResult
    func createPrayer(category: PrayerCategory = .personal, passages: [PrayerPassage] = []) -> Prayer {
        let prayer = Prayer(category: category)
        prayer.passages = passages
        context.insert(prayer)
        save()
        return prayer
    }

    /// "I prayed for this": counts towards the prayer streak.
    func markPrayed(_ prayer: Prayer, on date: Date = .now) {
        prayer.lastPrayedAt = date
        prayer.updatedAt = .now
        save()
        PrayerStreak.record(on: date)
    }

    /// Attaches a passage (ids only), once.
    func attach(_ passage: PrayerPassage, to prayer: Prayer) {
        var passages = prayer.passages
        guard !passages.contains(passage), passages.count < PrayerPassage.maximumPerPrayer else { return }
        passages.append(passage)
        prayer.passages = passages
        prayer.updatedAt = .now
        save()
    }

    func detach(_ passage: PrayerPassage, from prayer: Prayer) {
        prayer.passages = prayer.passages.filter { $0 != passage }
        prayer.updatedAt = .now
        save()
    }

    func markAnswered(_ prayer: Prayer, note: String? = nil, answered: Bool = true) {
        prayer.isAnswered = answered
        prayer.answeredAt = answered ? .now : nil
        if let note { prayer.answerNote = note }
        if answered {
            prayer.reminderAt = nil
            prayer.reminderRepeatsDaily = false
        }
        prayer.updatedAt = .now
        save()
        PrayerReminders.update(for: prayer)
        if answered { PrayerStreak.record() }
    }

    func delete(_ prayer: Prayer) {
        PrayerReminders.cancel(prayerID: prayer.id)
        deleteAttachments(of: .prayer, id: prayer.id)
        recordDeletion(of: prayer.id, in: SyncTable.prayers)
        context.delete(prayer)
        save()
    }

    // MARK: Prayer notes

    /// Prayers live only in the Prayer Journal. A note marked as a prayer (made
    /// by an older version, here or on another device) becomes a journal
    /// entry with the same title, words, date and passage, and the note goes.
    /// A handwritten prayer page stays a note, as a journal note, because
    /// journal entries hold no handwriting. Nothing is lost either way.
    /// Returns how many prayers were added.
    @discardableResult
    func movePrayerNotesToJournal(lastVerse: (ChapterID) -> Int? = { _ in nil }) -> Int {
        let prayerKind = NoteKind.prayer.rawValue
        let notes = (try? context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.kindRaw == prayerKind }))) ?? []
        guard !notes.isEmpty else { return 0 }
        var added = 0
        for note in notes {
            if note.drawing != nil {
                note.kind = .journal
                note.updatedAt = .now
                continue
            }
            if !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // The same id on every device, so two devices moving the
                // same note make one prayer, not two.
                let id = PrayerNoteMove.prayerID(forNote: note.id)
                let existing = (try? context.fetchCount(FetchDescriptor<Prayer>(predicate: #Predicate { $0.id == id }))) ?? 0
                if existing == 0 {
                    let prayer = Prayer(title: PrayerNoteMove.title(for: note), body: note.body)
                    prayer.id = id
                    prayer.passages = PrayerNoteMove.passages(for: note.anchor, lastVerse: lastVerse)
                    prayer.createdAt = note.createdAt
                    context.insert(prayer)
                    added += 1
                }
            }
            recordDeletion(of: note.id, in: SyncTable.notes)
            context.delete(note)
        }
        save()
        return added
    }
}

/// How a prayer note becomes a Prayer Journal entry.
enum PrayerNoteMove {
    /// A stable id derived from the note's, and never equal to it (tombstones
    /// are keyed by id alone).
    static func prayerID(forNote id: UUID) -> UUID {
        var bytes = id.uuid
        bytes.0 ^= 0xA5
        bytes.1 ^= 0x5A
        return UUID(uuid: bytes)
    }

    /// The note's title, or its theme when it had no title.
    static func title(for note: Note) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty, case let .theme(theme) = note.anchor { return theme }
        return note.title
    }

    /// The verses or chapter the note was on, as a prayer passage (ids only).
    /// A whole chapter needs its last verse; a book or theme has no passage.
    static func passages(for anchor: NoteAnchor, lastVerse: (ChapterID) -> Int?) -> [PrayerPassage] {
        switch anchor {
        case let .verses(start, end):
            return [PrayerPassage(selection: [start, end])].compactMap { $0 }
        case let .chapter(chapter):
            guard let last = lastVerse(chapter), last >= 1 else { return [] }
            return [PrayerPassage(start: chapter.firstVerse, end: VerseID(book: chapter.book, chapter: chapter.chapter, verse: last))]
        case .book, .theme, .none:
            return []
        }
    }
}
