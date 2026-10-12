import Foundation
import SwiftData
import Testing
@testable import Genesis

private var chicago: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    return calendar
}

private func date(_ month: Int, _ day: Int, _ hour: Int = 9, minute: Int = 0, year: Int = 2026) -> Date {
    chicago.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func facts(
    category: PrayerCategory = .personal,
    asked: Date,
    answered: Date? = nil,
    prayed: Date? = nil,
    hasContent: Bool = true
) -> PrayerFacts {
    PrayerFacts(
        id: UUID(),
        category: category,
        isAnswered: answered != nil,
        createdAt: asked,
        answeredAt: answered,
        lastPrayedAt: prayed,
        hasContent: hasContent
    )
}

@Suite("Prayer streak")
struct PrayerStreakTests {
    @Test func countsAddingPrayingAndAnswering() {
        let prayers = [
            facts(asked: date(10, 5)),
            facts(asked: date(9, 1), answered: date(10, 6)),
            facts(asked: date(9, 2), prayed: date(10, 7)),
        ]
        let days = PrayerStreak.days(log: [], prayers: prayers, calendar: chicago)
        let streak = PrayerStreak.length(of: days, on: date(10, 7, 20), calendar: chicago)
        #expect(streak == 3)
    }

    @Test func iPrayedTodayCounts() {
        let log = PrayerStreak.decodeLog(PrayerStreak.recording(date(10, 7), in: "", calendar: chicago))
        let days = PrayerStreak.days(log: log, prayers: [], calendar: chicago)
        let today = PrayerStreak.hasPrayed(on: date(10, 7, 22), in: days, calendar: chicago)
        let streak = PrayerStreak.length(of: days, on: date(10, 7, 22), calendar: chicago)
        #expect(today)
        #expect(streak == 1)
    }

    @Test func notBrokenUntilTheDayIsOver() {
        let log: Set<String> = ["2026-10-05", "2026-10-06"]
        let thisMorning = PrayerStreak.length(of: log, on: date(10, 7, 7), calendar: chicago)
        let dayAfter = PrayerStreak.length(of: log, on: date(10, 8, 7), calendar: chicago)
        #expect(thisMorning == 2, "Yesterday's streak still stands this morning")
        #expect(dayAfter == 0, "A missed day starts again, gently")
    }

    @Test func daylightSavingEndsInChicago() {
        // Clocks go back at 2 am on Sunday 1 November 2026 (a 25-hour day).
        let prayers = [
            facts(asked: date(10, 31, 23, minute: 30)),
            facts(asked: date(11, 1, 0, minute: 30)),
            facts(asked: date(11, 1, 23, minute: 45)),
            facts(asked: date(11, 2, 0, minute: 15)),
        ]
        let days = PrayerStreak.days(log: [], prayers: prayers, calendar: chicago)
        let streak = PrayerStreak.length(of: days, on: date(11, 2, 12), calendar: chicago)
        #expect(days == ["2026-10-31", "2026-11-01", "2026-11-02"])
        #expect(streak == 3)
    }

    @Test func daylightSavingStartsInChicago() {
        // Clocks go forward at 2 am on Sunday 8 March 2026 (a 23-hour day).
        let log: Set<String> = ["2026-03-07", "2026-03-08", "2026-03-09"]
        let streak = PrayerStreak.length(of: log, on: date(3, 9, 23, minute: 30), calendar: chicago)
        #expect(streak == 3)
    }

    @Test func theLogKeepsRecentDaysOnly() {
        let old = PrayerStreak.recording(date(1, 1, year: 2025), in: "", calendar: chicago)
        let raw = PrayerStreak.recording(date(10, 7), in: old + ",nonsense", calendar: chicago)
        let days = PrayerStreak.decodeLog(raw)
        #expect(days == ["2026-10-07"])
        let again = PrayerStreak.recording(date(10, 7, 21), in: raw, calendar: chicago)
        #expect(again == raw, "Once a day")
    }

    @Test func emptyPrayersDontCount() {
        let days = PrayerStreak.days(log: [], prayers: [facts(asked: date(10, 7), hasContent: false)], calendar: chicago)
        #expect(days.isEmpty)
    }
}

@Suite("Prayer statistics")
struct PrayerStatisticsTests {
    @Test func countsAnsweredActiveAndCategories() {
        let stats = PrayerStatistics([
            facts(category: .family, asked: date(9, 1), answered: date(9, 11)),
            facts(category: .family, asked: date(9, 2)),
            facts(category: .health, asked: date(9, 3), answered: date(9, 5)),
            facts(category: .work, asked: date(9, 4)),
            facts(category: .church, asked: date(9, 5), hasContent: false),
        ])
        #expect(stats.total == 4)
        #expect(stats.answered == 2)
        #expect(stats.active == 2)
        #expect(stats.answeredPercent == 50)
        let categories = stats.byCategory.map(\.category)
        #expect(categories == [.family, .work, .health], "Most first, then in the usual order")
        #expect(stats.byCategory.first?.count == 2)
        #expect(stats.averageAnswerDays == 6, "Ten days and two days")
    }

    @Test func emptyJournal() {
        let stats = PrayerStatistics([])
        #expect(stats.total == 0)
        #expect(stats.answeredPercent == 0)
        #expect(stats.averageDaysToAnswer == nil)
        #expect(stats.byCategory.isEmpty)
    }

    @Test func answeredTheSameDay() {
        let stats = PrayerStatistics([facts(asked: date(10, 7, 8), answered: date(10, 7, 20))])
        #expect(stats.averageAnswerDays == 0)
        #expect(stats.answeredPercent == 100)
    }

    @Test func percentRounds() {
        let stats = PrayerStatistics([
            facts(asked: date(9, 1), answered: date(9, 2)),
            facts(asked: date(9, 1)),
            facts(asked: date(9, 1)),
        ])
        #expect(stats.answeredPercent == 33)
    }
}

@Suite("Prayer timeline")
struct PrayerTimelineTests {
    @Test func monthsNewestFirstWithAnswers() {
        let answered = facts(asked: date(8, 20), answered: date(10, 2))
        let recent = facts(asked: date(10, 5))
        let months = PrayerTimeline.months([answered, recent, facts(asked: date(9, 9), hasContent: false)], calendar: chicago)
        let starts = months.map { Timestamp.dayString(from: $0.start, calendar: chicago) }
        #expect(starts == ["2026-10-01", "2026-08-01"], "Empty prayers leave no trace")
        let october = months.first?.entries.map(\.kind) ?? []
        #expect(october == [.asked, .answered], "Newest first within the month")
        let august = months.last?.entries.first
        #expect(august?.prayerID == answered.id)
        #expect(august?.kind == .asked)
    }

    @Test func monthBoundaryUsesTheLocalCalendar() {
        // 31 October, 11:30 pm in Chicago is already November in UTC.
        let months = PrayerTimeline.months([facts(asked: date(10, 31, 23, minute: 30))], calendar: chicago)
        let start = months.first.map { Timestamp.dayString(from: $0.start, calendar: chicago) }
        #expect(start == "2026-10-01")
    }
}

@Suite("Prayer categories and passages")
struct PrayerDataTests {
    @Test func savedCategoriesMapLeniently() {
        #expect(PrayerCategory(lenient: "family") == .family)
        #expect(PrayerCategory(lenient: " Church ") == .church)
        #expect(PrayerCategory(lenient: "HEALTH") == .health)
        #expect(PrayerCategory(lenient: "friends") == .friends, "Kept for prayers saved with it")
        #expect(PrayerCategory(lenient: "job") == .work)
        #expect(PrayerCategory(lenient: "healing") == .health)
        #expect(PrayerCategory(lenient: "marriage") == .family)
        #expect(PrayerCategory(lenient: "") == .personal)
        #expect(PrayerCategory(lenient: "something else") == .personal)
    }

    @Test func theFiveCategoriesComeFirst() {
        let firstFive = Array(PrayerCategory.allCases.prefix(5))
        #expect(firstFive == [.family, .church, .work, .health, .personal])
        let rawValues = Set(PrayerCategory.allCases.map(\.rawValue))
        #expect(rawValues == ["family", "church", "work", "personal", "health", "friends"], "Matches the prayers table's check")
    }

    @Test func passagesRoundTrip() {
        let passages = [
            PrayerPassage(start: VerseID(rawValue: 43_003_016), end: VerseID(rawValue: 43_003_017)),
            PrayerPassage(start: VerseID(rawValue: 19_023_001), end: VerseID(rawValue: 19_023_001)),
        ]
        let raw = PrayerPassage.encode(passages)
        #expect(raw == "43003016-43003017,19023001-19023001")
        let decoded = PrayerPassage.decode(raw)
        #expect(decoded == passages)
    }

    @Test func passageDecodingIsLenient() {
        let decoded = PrayerPassage.decode("43003016, junk,43003016-43003016,19023003-19023001,-")
        let ids = decoded.map(\.id)
        #expect(ids == ["43003016-43003016", "19023001-19023003"])
    }

    @Test func parsesReferences() {
        let verse = PrayerPassage.parse("John 3:16")
        #expect(verse?.start == VerseID(rawValue: 43_003_016))
        #expect(verse?.end == VerseID(rawValue: 43_003_016))
        let range = PrayerPassage.parse("Philippians 4:6-7")
        #expect(range?.end == VerseID(rawValue: 50_004_007))
        let chapter = PrayerPassage.parse("Psalm 23") { _ in 6 }
        #expect(chapter?.start == VerseID(rawValue: 19_023_001))
        #expect(chapter?.end == VerseID(rawValue: 19_023_006))
        let unknownLength = PrayerPassage.parse("Psalm 23")
        #expect(unknownLength == nil)
        let nonsense = PrayerPassage.parse("")
        #expect(nonsense == nil)
    }

    @Test func selectionStaysInOneChapter() {
        let passage = PrayerPassage(selection: [VerseID(rawValue: 43_003_017), VerseID(rawValue: 43_003_016)])
        #expect(passage?.start == VerseID(rawValue: 43_003_016))
        #expect(passage?.end == VerseID(rawValue: 43_003_017))
        let across = PrayerPassage(selection: [VerseID(rawValue: 43_003_036), VerseID(rawValue: 43_004_001)])
        #expect(across?.end == VerseID(rawValue: 43_003_036))
        let reference = passage?.reference.description(in: "en")
        #expect(reference == "John 3:16\u{2013}17")
    }

    @Test func searchFindsTitleBodyAndAnswer() {
        #expect(PrayerSearch.matches(title: "Healing for Grandma", body: "", answerNote: nil, query: "grandma"))
        #expect(PrayerSearch.matches(title: "", body: "Peace at work", answerNote: nil, query: "PEACE"))
        #expect(PrayerSearch.matches(title: "Job", body: "", answerNote: "A new role came", query: "role"))
        #expect(!PrayerSearch.matches(title: "Job", body: "", answerNote: nil, query: "garden"))
        #expect(PrayerSearch.matches(title: "Anything", body: "", answerNote: nil, query: "  "))
    }
}

@Suite("Prayer sync")
@MainActor
struct PrayerSyncTests {
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private func makePrayer() throws -> (Prayer, ModelContainer) {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = StudyStore(context: container.mainContext)
        let passage = PrayerPassage(start: VerseID(rawValue: 50_004_006), end: VerseID(rawValue: 50_004_007))
        let prayer = store.createPrayer(category: .health, passages: [passage])
        prayer.title = "Peace for Sam"
        return (prayer, container)
    }

    private func json(_ row: RemotePrayer) throws -> [String: Any] {
        let data = try SupabaseCoding.encoder().encode(row)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(object)
    }

    @Test func passagesAndPrayedGoUpAsIds() throws {
        let (prayer, container) = try makePrayer()
        _ = container
        prayer.lastPrayedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let object = try json(RemotePrayer(prayer, userID: userID))
        let passages = try #require(object["passages"] as? [[String: Any]])
        #expect(passages.count == 1)
        #expect(passages.first?["start_verse"] as? Int == 50_004_006)
        #expect(passages.first?["end_verse"] as? Int == 50_004_007)
        #expect(object["last_prayed_at"] is String)
        #expect(object["category"] as? String == "health")
    }

    @Test func clearedValuesAreExplicitNulls() throws {
        let (prayer, container) = try makePrayer()
        _ = container
        let object = try json(RemotePrayer(prayer, userID: userID))
        #expect(object["answered_at"] is NSNull, "Moving back to Praying clears the server's date")
        #expect(object["last_prayed_at"] is NSNull)
        #expect(object["reminder_at"] is NSNull)
        #expect(!object.keys.contains("deleted_at"))
    }

    @Test func unusualCategoriesAreNormalised() throws {
        let (prayer, container) = try makePrayer()
        _ = container
        prayer.categoryRaw = "Healing"
        let row = RemotePrayer(prayer, userID: userID)
        #expect(row.category == "health")
    }

    @Test func roundTrip() throws {
        let (prayer, container) = try makePrayer()
        _ = container
        let encoded = try SupabaseCoding.encoder().encode(RemotePrayer(prayer, userID: userID))
        let decoded = try SupabaseCoding.decoder().decode(RemotePrayer.self, from: encoded)
        let passages = decoded.prayerPassages
        #expect(passages == prayer.passages)
        #expect(decoded.title == "Peace for Sam")
    }

    @Test func rowsWithoutTheNewColumnsDecode() throws {
        let json = """
        {"id":"22222222-0000-0000-0000-000000000002","user_id":"\(userID.uuidString)","title":"Old","body":"",
         "category":"family","is_answered":false,"answered_at":null,"answer_note":null,"reminder_at":null,
         "reminder_repeats_daily":false,"created_at":"2026-10-06T10:00:00.000000+00:00",
         "updated_at":"2026-10-06T10:00:00.000000+00:00","deleted_at":null,"server_updated_at":"2026-10-06T10:00:01.123456+00:00"}
        """
        let row = try SupabaseCoding.decoder().decode(RemotePrayer.self, from: Data(json.utf8))
        #expect(row.passages == nil)
        #expect(row.prayerPassages == nil, "Local passages are left alone")
        #expect(row.lastPrayedAt == nil)
    }

    @Test func rowsWithTheNewColumnsDecode() throws {
        let json = """
        {"id":"22222222-0000-0000-0000-000000000003","user_id":"\(userID.uuidString)","title":"New","body":"",
         "category":"church","is_answered":false,"answered_at":null,"answer_note":null,"reminder_at":null,
         "reminder_repeats_daily":false,"passages":[{"start_verse":43003016,"end_verse":43003016},{"start_verse":5,"end_verse":5}],
         "last_prayed_at":"2026-10-07T14:00:00.123456+00:00","created_at":"2026-10-06T10:00:00.000000+00:00",
         "updated_at":"2026-10-07T14:00:00.123456+00:00","deleted_at":null,"server_updated_at":"2026-10-07T14:00:01.123456+00:00"}
        """
        let row = try SupabaseCoding.decoder().decode(RemotePrayer.self, from: Data(json.utf8))
        let ids = row.prayerPassages?.map(\.id)
        #expect(ids == ["43003016-43003016"], "Anything that isn't a verse id is skipped")
        #expect(row.lastPrayedAt != nil)
    }

    @Test func prayingAndAttachingThroughTheStore() throws {
        let (prayer, container) = try makePrayer()
        let store = StudyStore(context: container.mainContext)
        let extra = PrayerPassage(start: VerseID(rawValue: 43_003_016), end: VerseID(rawValue: 43_003_016))
        store.attach(extra, to: prayer)
        store.attach(extra, to: prayer)
        #expect(prayer.passages.count == 2, "Each passage once")
        store.detach(extra, from: prayer)
        #expect(prayer.passages.count == 1)
        let before = prayer.updatedAt
        store.markPrayed(prayer, on: .now)
        #expect(prayer.lastPrayedAt != nil)
        #expect(prayer.updatedAt >= before)
    }
}

@Suite("Prayer notes move to the journal")
@MainActor
struct PrayerNoteMoveTests {
    private func makeStore() throws -> (StudyStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (StudyStore(context: container.mainContext), container)
    }

    /// A note saved as a prayer, as older versions did.
    private func prayerNote(_ store: StudyStore, anchor: NoteAnchor, title: String = "", body: String = "") -> Note {
        let note = store.createNote(kind: .text, anchor: anchor, title: title, body: body)
        note.kindRaw = "prayer"
        return note
    }

    @Test func notesCanNoLongerBePrayers() {
        #expect(!NoteKind.allCases.contains(.prayer))
        #expect(NoteKind(rawValue: "prayer") == .prayer, "Older rows still read")
    }

    @Test func aPrayerNoteBecomesAJournalEntry() throws {
        let (store, container) = try makeStore()
        let context = container.mainContext
        let start = VerseID(rawValue: 50_004_006)
        let end = VerseID(rawValue: 50_004_007)
        let note = prayerNote(store, anchor: .verses(start, end), title: "Peace", body: "For Sam's surgery")
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        note.createdAt = created
        let noteID = note.id

        let added = store.movePrayerNotesToJournal()

        #expect(added == 1)
        let prayers = try context.fetch(FetchDescriptor<Prayer>())
        let prayer = try #require(prayers.first)
        #expect(prayers.count == 1)
        #expect(prayer.title == "Peace")
        #expect(prayer.body == "For Sam's surgery")
        #expect(prayer.createdAt == created)
        #expect(prayer.passages == [PrayerPassage(start: start, end: end)])
        #expect(prayer.id != noteID)
        #expect(prayer.id == PrayerNoteMove.prayerID(forNote: noteID), "The same on every device")
        let notes = try context.fetchCount(FetchDescriptor<Note>())
        #expect(notes == 0)
        let tombstones = try context.fetch(FetchDescriptor<Tombstone>())
        #expect(tombstones.map(\.recordID) == [noteID])
        #expect(tombstones.map(\.table) == [SyncTable.notes])
    }

    @Test func movingTwiceMakesOnePrayer() throws {
        let (store, container) = try makeStore()
        let context = container.mainContext
        let note = prayerNote(store, anchor: .none, body: "Wisdom at work")
        let noteID = note.id
        store.movePrayerNotesToJournal()
        // The same note arrives again from another device.
        let again = Note(kind: .text, anchor: .none, body: "Wisdom at work")
        again.id = noteID
        again.kindRaw = "prayer"
        context.insert(again)

        let added = store.movePrayerNotesToJournal()

        #expect(added == 0)
        let prayers = try context.fetchCount(FetchDescriptor<Prayer>())
        #expect(prayers == 1)
    }

    @Test func aWholeChapterBecomesItsPassage() throws {
        let (store, container) = try makeStore()
        let chapter = ChapterID(book: 19, chapter: 23)
        _ = prayerNote(store, anchor: .chapter(chapter), body: "The Lord is my shepherd")
        store.movePrayerNotesToJournal { _ in 6 }
        let prayer = try #require(try container.mainContext.fetch(FetchDescriptor<Prayer>()).first)
        #expect(prayer.passages == [PrayerPassage(start: chapter.firstVerse, end: VerseID(book: 19, chapter: 23, verse: 6))])
    }

    @Test func aThemeBecomesTheTitle() throws {
        let (store, container) = try makeStore()
        _ = prayerNote(store, anchor: .theme("Grace"), body: "Teach me grace")
        store.movePrayerNotesToJournal()
        let prayer = try #require(try container.mainContext.fetch(FetchDescriptor<Prayer>()).first)
        #expect(prayer.title == "Grace")
        #expect(prayer.passages.isEmpty)
    }

    @Test func handwrittenPrayersStayAsJournalNotes() throws {
        let (store, container) = try makeStore()
        let context = container.mainContext
        let note = prayerNote(store, anchor: .none, title: "Sketch")
        note.drawing = Data([1, 2, 3])

        let added = store.movePrayerNotesToJournal()

        #expect(added == 0)
        #expect(note.kind == .journal)
        #expect(note.drawing == Data([1, 2, 3]), "Nothing is lost")
        let prayers = try context.fetchCount(FetchDescriptor<Prayer>())
        #expect(prayers == 0)
    }

    @Test func emptyPrayerNotesAreRemoved() throws {
        let (store, container) = try makeStore()
        let context = container.mainContext
        _ = prayerNote(store, anchor: .none)
        let added = store.movePrayerNotesToJournal()
        #expect(added == 0)
        let notes = try context.fetchCount(FetchDescriptor<Note>())
        let prayers = try context.fetchCount(FetchDescriptor<Prayer>())
        #expect(notes == 0)
        #expect(prayers == 0)
    }

    @Test func otherNotesAreLeftAlone() throws {
        let (store, container) = try makeStore()
        let note = store.createNote(kind: .study, anchor: .theme("Faith"), body: "Hebrews 11")
        let added = store.movePrayerNotesToJournal()
        #expect(added == 0)
        #expect(note.kind == .study)
        let notes = try container.mainContext.fetchCount(FetchDescriptor<Note>())
        #expect(notes == 1)
    }
}
