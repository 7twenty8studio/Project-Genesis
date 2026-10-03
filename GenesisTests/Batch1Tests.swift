import Foundation
import Testing
@testable import Genesis

@Suite("Parallel Bibles, icons, Year in Review")
@MainActor
struct Batch1Tests {
    private func verse(_ chapter: Int, _ number: Int, _ text: String) -> Verse {
        Verse(id: VerseID(book: 32, chapter: chapter, verse: number), text: text, startsParagraph: false, isPoetry: false)
    }

    @Test func parallelRowsPairVersesByNumber() {
        // Jonah 2: the KJV has 10 verses, a Spanish-numbered Bible 11.
        let english = (1...10).map { verse(2, $0, "en \($0)") }
        let spanish = (1...11).map { verse(2, $0, "es \($0)") }
        let rows = ParallelRow.merge(english, spanish)
        #expect(rows.count == 11)
        #expect(rows[0] == ParallelRow(number: 1, primary: "en 1", secondary: "es 1"))
        #expect(rows[10] == ParallelRow(number: 11, primary: nil, secondary: "es 11"))
    }

    @Test func seasonalIconFollowsTheCalendar() {
        let calendar = Calendar(identifier: .gregorian)
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2))!
        #expect(AppIconChoice.standard.iconName() == nil)
        #expect(AppIconChoice.night.iconName() == "AppIcon-Night")
        #expect(AppIconChoice.winter.iconName() == "AppIcon-Winter")
        let seasonal = AppIconChoice.seasons.iconName(on: october)
        #expect(seasonal == "AppIcon-Autumn" || seasonal == "AppIcon-Spring")
    }

    @Test func yearInReviewCountsOnlyThatYear() {
        let calendar = Calendar(identifier: .gregorian)
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }
        let review = YearInReview.make(
            year: 2026,
            readingDays: ["2026-03-01", "2026-03-02", "2026-03-03", "2026-05-10", "2025-12-31"],
            readingSeconds: ["2026-03-02": 1800, "2026-05-10": 600, "2025-12-31": 9000],
            chapters: Set([43_001, 43_002, 31_001]),
            highlights: [
                .init(date: date(2026, 3, 2), verse: VerseID(book: 43, chapter: 3, verse: 16), color: .yellow),
                .init(date: date(2026, 4, 2), verse: VerseID(book: 43, chapter: 1, verse: 1), color: .yellow),
                .init(date: date(2025, 4, 2), verse: VerseID(book: 1, chapter: 1, verse: 1), color: .blue),
            ],
            notes: [date(2026, 1, 5), date(2025, 6, 1)],
            prayers: [.init(created: date(2026, 2, 1), answered: date(2026, 6, 1)), .init(created: date(2025, 2, 1), answered: nil)],
            calendar: calendar
        )
        #expect(review.daysRead == 4)
        #expect(review.longestStreak == 3)
        #expect(review.minutesRead == 40)
        #expect(review.longestDayMinutes == 30)
        #expect(review.chaptersRead == 3)
        #expect(review.booksOpened == 2)
        #expect(review.booksFinished == 1) // Obadiah has one chapter
        #expect(review.topBook?.id == 43)
        #expect(review.highlights == 2)
        #expect(review.mostHighlightedBook?.id == 43)
        #expect(review.favoriteColor == .yellow)
        #expect(review.notes == 1)
        #expect(review.prayersAdded == 1)
        #expect(review.prayersAnswered == 1)
        #expect(review.hasActivity)
    }

    @Test func yearInReviewSeason() {
        let calendar = Calendar(identifier: .gregorian)
        let january = calendar.date(from: DateComponents(year: 2027, month: 1, day: 10))!
        let june = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        #expect(YearInReview.isSeason(on: january, calendar: calendar))
        #expect(!YearInReview.isSeason(on: june, calendar: calendar))
        #expect(YearInReview.reviewedYear(on: january, calendar: calendar) == 2026)
    }

    @Test func chaptersAreRecordedByYear() {
        let defaults = UserDefaults(suiteName: "batch1-\(UUID())")!
        let progress = ReadingProgress(defaults: defaults)
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        progress.update(VerseID(book: 19, chapter: 23, verse: 1), at: date)
        #expect(progress.chaptersByYear["2026"] == Set([19_023]))
        let reloaded = ReadingProgress(defaults: defaults)
        #expect(reloaded.chaptersByYear["2026"] == Set([19_023]))
    }
}
