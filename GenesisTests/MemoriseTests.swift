import Foundation
import SwiftData
import Testing
@testable import Genesis

@Suite("Memorise Scripture")
@MainActor
struct MemoriseTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int, hour: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private var fresh: MemorySchedule {
        MemorySchedule(ease: MemorySchedule.startingEase, intervalDays: 0, repetitions: 0, dueAt: date(1))
    }

    @Test func goodReviewsSpreadOut() {
        let first = fresh.reviewed(.good, at: date(1), calendar: calendar)
        #expect(first.intervalDays == 1)
        #expect(first.dueAt == calendar.startOfDay(for: date(2)), "Ready the next morning")
        let second = first.reviewed(.good, at: date(2), calendar: calendar)
        #expect(second.intervalDays == 3)
        let third = second.reviewed(.good, at: date(5), calendar: calendar)
        #expect(third.intervalDays == 8, "3 days × ease 2.5, rounded")
        #expect(third.mastery == .familiar)
    }

    @Test func forgettingBringsItBackToday() {
        let learned = fresh.reviewed(.good, at: date(1), calendar: calendar).reviewed(.good, at: date(2), calendar: calendar)
        let forgot = learned.reviewed(.again, at: date(5), calendar: calendar)
        #expect(forgot.repetitions == 0)
        #expect(forgot.dueAt == date(5).addingTimeInterval(600))
        #expect(forgot.ease < learned.ease)
        #expect(forgot.mastery == .new)
    }

    @Test func easeNeverFallsTooLow() {
        var schedule = fresh
        for _ in 0..<20 { schedule = schedule.reviewed(.hard, at: date(1), calendar: calendar) }
        #expect(schedule.ease == MemorySchedule.minimumEase)
    }

    @Test func hintsRevealTheOpeningWords() {
        let text = "Trust in the LORD with all thine heart; and lean not"
        #expect(MemoryHint.opening(text, words: 4) == "Trust in the LORD\u{2026}")
        #expect(MemoryHint.opening(text, words: 50) == text, "The whole passage, with no ellipsis")
        #expect(MemoryHint.opening("Jesus wept.", words: 4) == "Jesus wept.")
        #expect(!MemoryHint.isComplete(text, words: 8))
        #expect(MemoryHint.isComplete(text, words: 11))
    }

    @Test func addingTheSamePassageTwiceKeepsOne() throws {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = StudyStore(context: container.mainContext)
        let start = VerseID(book: 20, chapter: 3, verse: 5)
        let end = VerseID(book: 20, chapter: 3, verse: 6)
        let first = store.memorise(from: start, through: end, translationID: "KJV")
        let again = store.memorise(from: start, through: end, translationID: "KJV")
        #expect(first.id == again.id)
        #expect(store.memoryVerses().count == 1)
        #expect(first.reference.description.contains("3:5"))
        #expect(store.dueMemoryVerses().count == 1, "New verses are due straight away")

        store.review(first, .good)
        #expect(store.dueMemoryVerses().isEmpty)
        #expect(first.reviewCount == 1)

        store.delete(first)
        #expect(store.memoryVerses().isEmpty)
        let tombstones = try container.mainContext.fetch(FetchDescriptor<Tombstone>())
        #expect(tombstones.first?.table == SyncTable.memoryVerses, "Deleting records it for sync")
    }

    @Test func syncRowUsesTheTableColumns() throws {
        let verse = MemoryVerse(start: VerseID(book: 43, chapter: 3, verse: 16), end: VerseID(book: 43, chapter: 3, verse: 16), translationID: "KJV")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = String(decoding: try encoder.encode(RemoteMemoryVerse(verse, userID: UUID())), as: UTF8.self)
        for column in ["start_verse", "end_verse", "translation_id", "interval_days", "due_at", "review_count"] {
            #expect(json.contains("\"\(column)\""), "\(column) matches the migration")
        }
    }
}
