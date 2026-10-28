import Foundation
import Testing
@testable import Genesis

/// The verse widget's options: rotation, fallbacks, older snapshots.
@Suite("Verse widget options")
struct VerseWidgetOptionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func pool(_ count: Int) -> [WidgetSnapshot.Passage] {
        (1...count).map { WidgetSnapshot.Passage(reference: "R\($0)", text: "T\($0)", verse: 43_003_000 + $0, translation: "KJV") }
    }

    @Test func randomVerseMovesOnEveryThreeHours() {
        var snapshot = WidgetSnapshot.placeholder
        snapshot.randomVerses = pool(5)
        let early = snapshot.passage(for: .random, on: date(7, 9), calendar: calendar)
        let later = snapshot.passage(for: .random, on: date(7, 11, 59), calendar: calendar)
        let next = snapshot.passage(for: .random, on: date(7, 12), calendar: calendar)
        #expect(early == later, "Same three-hour block, same verse")
        #expect(early != next)

        let slot = VerseWidgetSchedule.slot(for: date(7, 12), calendar: calendar)
        let previous = VerseWidgetSchedule.slot(for: date(7, 11, 59), calendar: calendar)
        let tomorrow = VerseWidgetSchedule.slot(for: date(8, 0), calendar: calendar)
        #expect(slot == previous + 1)
        #expect(tomorrow == VerseWidgetSchedule.slot(for: date(7, 21), calendar: calendar) + 1)
        let index = VerseWidgetSchedule.index(for: date(7, 12), count: 5, calendar: calendar)
        #expect(index == slot % 5)
        #expect(next == snapshot.randomVerses?[slot % 5])
    }

    @Test func rotatingTimelinesChangeEveryThreeHoursForADay() {
        let now = date(7, 10, 30)
        let dates = VerseWidgetSchedule.entryDates(rotates: true, from: now, calendar: calendar)
        #expect(dates.count == 9)
        #expect(dates.first == now)
        #expect(dates.dropFirst().first == date(7, 12))
        #expect(dates.last == date(8, 9))

        let daily = VerseWidgetSchedule.entryDates(rotates: false, from: now, calendar: calendar)
        #expect(daily.count == 7)
        #expect(daily.dropFirst().first == date(8, 0), "Daily options change at midnight")
    }

    @Test func onlyRandomAndCategoriesRotate() {
        let rotating = VerseWidgetSource.allCases.filter(\.rotates)
        let expected: [VerseWidgetSource] = [.random, .hope, .peace, .faith, .strength, .comfort, .love, .gratitude, .guidance]
        #expect(rotating == expected)
    }

    @Test func missingVersesFallBackToTheVerseOfTheDay() {
        var snapshot = WidgetSnapshot.placeholder
        snapshot.randomVerses = nil
        snapshot.categoryVerses = ["hope": []]
        snapshot.readingVerses = ["2026-10-06": pool(1)[0]]
        let now = date(7, 9)
        let daily = snapshot.dailyPassage(on: now, calendar: calendar)
        #expect(daily != nil)
        let random = snapshot.passage(for: .random, on: now, calendar: calendar)
        let hope = snapshot.passage(for: .hope, on: now, calendar: calendar)
        let peace = snapshot.passage(for: .peace, on: now, calendar: calendar)
        let reading = snapshot.passage(for: .fromYourReading, on: now, calendar: calendar)
        #expect(random == daily)
        #expect(hope == daily, "An empty category falls back")
        #expect(peace == daily, "A missing category falls back")
        #expect(reading == daily, "Only yesterday's reading verse was written")
    }

    @Test func fromYourReadingPicksTheDaysVerse() {
        var snapshot = WidgetSnapshot.placeholder
        let verses = pool(2)
        snapshot.readingVerses = ["2026-10-07": verses[0], "2026-10-08": verses[1]]
        let today = snapshot.passage(for: .fromYourReading, on: date(7, 23), calendar: calendar)
        let tomorrow = snapshot.passage(for: .fromYourReading, on: date(8, 1), calendar: calendar)
        #expect(today == verses[0])
        #expect(tomorrow == verses[1])
    }

    @Test func snapshotsWithoutVerseOptionsStillDecode() throws {
        // Written before the verse widget had options.
        let json = """
        {"generatedAt":0,"translation":"KJV","dailyVerses":[{"day":"2026-10-07","reference":"John 3:16","text":"For God so loved the world","verse":43003016}],
         "streakDays":2,"chaptersRead":5,"activePrayerCount":0,"isPremium":true}
        """
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.randomVerses == nil)
        #expect(snapshot.categoryVerses == nil)
        #expect(snapshot.readingVerses == nil)
        let hope = snapshot.passage(for: .hope, on: date(7, 9), calendar: calendar)
        #expect(hope?.reference == "John 3:16")
        #expect(hope?.translation == "KJV")
    }

    @Test func verseOptionsRoundTrip() throws {
        var snapshot = WidgetSnapshot.placeholder
        snapshot.randomVerses = pool(3)
        snapshot.categoryVerses = ["peace": pool(2)]
        snapshot.readingVerses = ["2026-10-07": pool(1)[0]]
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }
}

/// The curated category lists: every reference is real, whole and short.
@Suite("Verse categories")
struct VerseCategoryTests {
    private func repository(_ translation: Translation) throws -> BibleRepository {
        let url = try #require(Bundle.main.url(forResource: translation.id, withExtension: "sqlite"))
        return try BibleRepository(translation: translation, url: url)
    }

    @Test("Every category has 15 to 30 passages of at most three verses", arguments: VerseCategory.allCases)
    func categoryShape(category: VerseCategory) {
        let passages = VerseCategories.passages(for: category)
        #expect((15...30).contains(passages.count), Comment(rawValue: "\(category.rawValue): \(passages.count)"))
        #expect(Set(passages).count == passages.count, "No passage twice in a category")
        for passage in passages {
            let length = passage.end.verse - passage.start.verse + 1
            #expect(passage.start.chapterID == passage.end.chapterID)
            #expect((1...3).contains(length), Comment(rawValue: passage.reference.description(in: "en")))
        }
    }

    @Test("Every reference resolves in the bundled Bibles", arguments: Translation.bundled)
    func referencesResolve(translation: Translation) throws {
        let bible = try repository(translation)
        for passage in VerseCategories.encouraging {
            let verses = try bible.verses(from: passage.start, through: passage.end)
            let ids = verses.map(\.id)
            let empty = verses.contains { $0.text.isEmpty }
            #expect(ids == passage.verseIDs, Comment(rawValue: "\(translation.id) \(passage.reference.description(in: "en"))"))
            #expect(!empty)
        }
    }

    @Test func kjvPassagesAreWholeSentences() throws {
        let kjv = try repository(.kjv)
        for passage in VerseCategories.encouraging {
            let text = try kjv.verses(from: passage.start, through: passage.end).map(\.plainText).joined(separator: " ")
            let first = text.first
            let last = text.last
            let label = Comment(rawValue: passage.reference.description(in: "en"))
            #expect(first?.isUppercase == true, label)
            #expect(last == "." || last == "!" || last == "?", label)
            // Psalm titles and acrostic letters are part of some KJV verses.
            #expect(!text.contains("chief Musician") && !text.hasPrefix("A Psalm"), label)
        }
    }

    @Test func randomPoolIsTheSameAllDayAndNewTomorrow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 7))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 22))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 7))!
        let today = WidgetVerses.randomPool(on: morning, calendar: calendar)
        let later = WidgetVerses.randomPool(on: evening, calendar: calendar)
        let next = WidgetVerses.randomPool(on: tomorrow, calendar: calendar)
        let all = Set(VerseCategories.encouraging)
        #expect(today.count == WidgetVerses.randomPoolSize)
        #expect(Set(today).count == today.count, "No verse twice in a pool")
        #expect(today == later)
        #expect(today != next)
        #expect(Set(today).isSubset(of: all))
    }

    @Test func passagesKeepTheirOwnNumbering() {
        let john316 = CategoryPassage(book: 43, chapter: 3, verse: 16, through: 16)
        let acts1940 = CategoryPassage(book: 44, chapter: 19, verse: 40, through: 40)
        let romans1625 = CategoryPassage(book: 45, chapter: 16, verse: 25, through: 25)
        #expect(WidgetVerses.usesOwnBible(john316, translationID: "RV1909"))
        #expect(!WidgetVerses.usesOwnBible(acts1940, translationID: "RV1909"), "Numbered differently: shown from the KJV")
        #expect(!WidgetVerses.usesOwnBible(romans1625, translationID: "WEB"))
        #expect(WidgetVerses.usesOwnBible(acts1940, translationID: "KJV"))
        #expect(WidgetVerses.usesOwnBible(john316, translationID: "UNMAPPED"))
    }

    @Test @MainActor func passagesComeVerbatimFromTheCurrentBible() throws {
        let defaults = try #require(UserDefaults(suiteName: "VerseCategoryTests-\(UUID().uuidString)"))
        let library = BibleLibrary(defaults: defaults)
        library.currentTranslation = .web
        let hope = VerseCategories.passages(for: .hope)
        let passages = WidgetVerses.passages(hope, library: library)
        #expect(passages.count == hope.count)
        let fromWEB = passages.allSatisfy { $0.translation == "WEB" }
        #expect(fromWEB)
        let first = try #require(passages.first)
        let verse = try library.current.verse(hope[0].start)
        #expect(first.text == verse?.plainText, "Verbatim from the database")
    }
}

private func johnVerse(_ number: Int, _ text: String, chapter: Int) -> Verse {
    Verse(id: VerseID(book: 43, chapter: chapter, verse: number), text: text, startsParagraph: false, isPoetry: false)
}

/// "From Your Reading": what counts as a verse that reads well alone.
@Suite("From your reading")
@MainActor
struct FromYourReadingTests {

    @Test func comfortableVersesAreWholeSentencesOfAReadableLength() {
        #expect(ReadingVersePicker.isComfortable("For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish."))
        #expect(ReadingVersePicker.isComfortable("\u{00BF}No es esta la palabra que te hablamos en Egipto, para que nos dejes servir?"))
        #expect(ReadingVersePicker.isComfortable("\u{201C}Don\u{2019}t let your heart be troubled. Believe in God. Believe also in me.\u{201D}"))
        #expect(!ReadingVersePicker.isComfortable("Jesus wept."), "Too short")
        #expect(!ReadingVersePicker.isComfortable("and he said unto them, Go ye into all the world, and preach the gospel to every creature."), "Starts mid-sentence")
        #expect(!ReadingVersePicker.isComfortable("Being confident of this very thing, that he which hath begun a good work in you will perform it,"), "Ends mid-sentence")
        let long = String(repeating: "And the Lord spake unto Moses, saying. ", count: 7)
        #expect(!ReadingVersePicker.isComfortable(long), "Too long")
    }

    @Test func picksTheSameVerseAllDayFromRecentChapters() {
        let good = "These things I have spoken unto you, that in me ye might have peace."
        let chapters = [ChapterID(book: 43, chapter: 1), ChapterID(book: 43, chapter: 2)]
        let verses: (ChapterID) -> [Verse] = { chapter in
            chapter.chapter == 1
                ? [johnVerse(1, "and so on,", chapter: 1)]
                : [johnVerse(1, good, chapter: 2), johnVerse(2, "Short.", chapter: 2)]
        }
        let first = ReadingVersePicker.pick(from: chapters, day: 100, verses: verses)
        let again = ReadingVersePicker.pick(from: chapters, day: 100, verses: verses)
        #expect(first?.id == again?.id)
        #expect(first?.text == good, "Chapters without a comfortable verse are skipped")
        let none = ReadingVersePicker.pick(from: [], day: 100, verses: verses)
        #expect(none == nil, "Nothing read lately: the widget shows the verse of the day")
    }

    @Test func recentChaptersCoverTheLastWeek() throws {
        let defaults = try #require(UserDefaults(suiteName: "FromYourReadingTests-\(UUID().uuidString)"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let progress = ReadingProgress(defaults: defaults, calendar: calendar)
        func day(_ number: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: number, hour: 9))!
        }
        progress.update(VerseID(book: 19, chapter: 1, verse: 1), at: day(1))
        progress.update(VerseID(book: 43, chapter: 3, verse: 1), at: day(5))
        progress.update(VerseID(book: 43, chapter: 3, verse: 16), at: day(5))
        progress.update(VerseID(book: 45, chapter: 8, verse: 1), at: day(8))
        let recent = progress.recentChapters(days: 7, endingOn: day(8))
        #expect(recent == [ChapterID(book: 45, chapter: 8), ChapterID(book: 43, chapter: 3)], "Most recent first, each once, nothing older than a week")

        let reloaded = ReadingProgress(defaults: defaults, calendar: calendar)
        let saved = reloaded.recentChapters(days: 7, endingOn: day(8))
        #expect(saved == recent)
    }
}
