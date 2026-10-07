import Foundation
import Testing
@testable import Genesis

/// A clock the tests can move forward.
private final class TestClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@Suite("Group challenges")
@MainActor
struct GroupChallengeTests {
    private let chicago: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        chicago.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    private func challenge(_ kind: GroupChallengeKind, start: String, days: Int, chapters: [Int] = []) -> GroupChallenge {
        GroupChallenge(
            id: UUID(), groupID: UUID(), createdBy: nil, kind: kind, title: "Test", details: "",
            startDay: start, days: days, chapters: chapters,
            verseStart: kind == .memorise ? 19_023_001 : nil, verseEnd: kind == .memorise ? 19_023_003 : nil,
            translationID: kind == .memorise ? "KJV" : nil, createdAt: .now
        )
    }

    // MARK: Days and status

    @Test func dayIndexCountsCalendarDaysAcrossDaylightSaving() {
        // Clocks go back on 1 November 2026 and forward on 8 March 2026 in Chicago.
        let autumn = challenge(.streak, start: "2026-10-31", days: 7)
        let autumnLateNight = autumn.dayIndex(on: date(2026, 11, 1, 23, 30), calendar: chicago)
        let autumnJustAfterMidnight = autumn.dayIndex(on: date(2026, 11, 2, 0, 30), calendar: chicago)
        #expect(autumnLateNight == 2)
        #expect(autumnJustAfterMidnight == 3)

        let spring = challenge(.streak, start: "2026-03-07", days: 7)
        let springEarly = spring.dayIndex(on: date(2026, 3, 8, 0, 15), calendar: chicago)
        let springLate = spring.dayIndex(on: date(2026, 3, 9, 23, 45), calendar: chicago)
        #expect(springEarly == 2)
        #expect(springLate == 3)

        let before = spring.dayIndex(on: date(2026, 3, 6, 23, 59), calendar: chicago)
        #expect(before == 0, "The day before it starts")
    }

    @Test func statusFollowsTheCalendar() {
        let week = challenge(.streak, start: "2026-10-10", days: 7)
        let dayBefore = week.status(on: date(2026, 10, 9, 23, 59), calendar: chicago)
        let firstDay = week.status(on: date(2026, 10, 10, 0, 1), calendar: chicago)
        let lastDay = week.status(on: date(2026, 10, 16, 23, 59), calendar: chicago)
        let after = week.status(on: date(2026, 10, 17, 0, 1), calendar: chicago)
        #expect(dayBefore == .upcoming)
        #expect(firstDay == .running)
        #expect(lastDay == .running)
        #expect(after == .finished)

        let clampedLate = week.currentDay(on: date(2026, 12, 1), calendar: chicago)
        let clampedEarly = week.currentDay(on: date(2026, 10, 1), calendar: chicago)
        #expect(clampedLate == 7)
        #expect(clampedEarly == 1)
    }

    @Test func dailyItemsCantBeTickedAhead() {
        let week = challenge(.streak, start: "2026-10-10", days: 7)
        let onDayTwo = date(2026, 10, 11)
        let today = week.canTick(2, on: onDayTwo, calendar: chicago)
        let tomorrowSlack = week.canTick(3, on: onDayTwo, calendar: chicago)
        let dayAfterTomorrow = week.canTick(4, on: onDayTwo, calendar: chicago)
        let outside = week.canTick(8, on: date(2026, 10, 16), calendar: chicago)
        let longAfter = week.canTick(7, on: date(2026, 10, 20), calendar: chicago)
        #expect(today)
        #expect(tomorrowSlack, "A day's slack for time zones, as on the server")
        #expect(!dayAfterTomorrow)
        #expect(!outside)
        #expect(!longAfter, "Nothing changes once it has ended")
    }

    // MARK: Streaks

    @Test func streaksStayAliveUntilADayIsMissed() {
        let unbroken = ChallengeStreak.current([1, 2, 3], today: 3)
        let todayNotYet = ChallengeStreak.current([1, 2, 3], today: 4)
        let broken = ChallengeStreak.current([1, 2, 4], today: 4)
        let none = ChallengeStreak.current([], today: 5)
        #expect(unbroken == 3)
        #expect(todayNotYet == 3, "Today isn't over yet")
        #expect(broken == 1)
        #expect(none == 0)

        let aliveToday = ChallengeStreak.isAlive([3, 4], today: 4)
        let aliveYesterday = ChallengeStreak.isAlive([3], today: 4)
        let missed = ChallengeStreak.isAlive([1, 2], today: 4)
        let firstDay = ChallengeStreak.isAlive([], today: 1)
        let secondDayNothing = ChallengeStreak.isAlive([], today: 2)
        #expect(aliveToday)
        #expect(aliveYesterday)
        #expect(!missed)
        #expect(firstDay, "Nobody has missed a day on the first day")
        #expect(!secondDayNothing)
    }

    @Test func stillGoingCountsLiveStreaks() {
        let week = challenge(.streak, start: "2026-10-10", days: 7)
        let me = UUID()
        let rows = [
            ChallengeProgress(userID: me, displayName: "Sam", done: 3, items: [1, 2, 3]),
            ChallengeProgress(userID: UUID(), displayName: "Ruth", done: 2, items: [3, 4]),
            ChallengeProgress(userID: UUID(), displayName: "Jo", done: 1, items: [1]),
        ]
        let summary = GroupChallengeSummary(challenge: week, rows: rows, me: me, on: date(2026, 10, 13), calendar: chicago)
        #expect(summary.day == 4)
        #expect(summary.stillGoing == 2)
        #expect(summary.memberCount == 3)
        #expect(summary.myStreak == 3)
    }

    // MARK: Progress

    @Test func groupProgressIsEveryonesTicksOverEverything() {
        let mark = ReadingChallengeChapters.chapters(books: [41])
        let reading = challenge(.reading, start: "2026-10-01", days: 14, chapters: mark)
        let me = UUID()
        let rows = [
            ChallengeProgress(userID: me, displayName: "Sam", done: 4, items: [41_001, 41_002, 41_003, 41_004]),
            ChallengeProgress(userID: UUID(), displayName: "Ruth", done: 16, items: nil),
            // More than there is (shouldn't happen) counts as all of it.
            ChallengeProgress(userID: UUID(), displayName: "Jo", done: 20, items: nil),
        ]
        let summary = GroupChallengeSummary(challenge: reading, rows: rows, me: me, on: date(2026, 10, 5), calendar: chicago)
        #expect(summary.itemCount == 16)
        #expect(summary.groupDone == 36)
        #expect(summary.groupFraction == 0.75)
        #expect(summary.myFraction == 0.25)
        #expect(summary.myItems.count == 4)

        let empty = GroupChallengeSummary(challenge: reading, rows: [], me: me, on: date(2026, 10, 5), calendar: chicago)
        #expect(empty.groupFraction == 0)
    }

    // MARK: Reading

    @Test func readingChaptersForABook() {
        let mark = ReadingChallengeChapters.chapters(books: [41])
        #expect(mark.count == 16)
        #expect(mark.first == 41_001)
        #expect(mark.last == 41_016)

        let romans = ReadingChallengeChapters.chapters(book: 45, from: 1, through: 8)
        #expect(romans == Array(45_001...45_008))
        let clamped = ReadingChallengeChapters.chapters(book: 41, from: 10, through: 99)
        #expect(clamped.last == 41_016)

        let letters = ReadingChallengeChapters.chapters(books: [48, 45])
        #expect(letters.first == 45_001, "Canonical order")
        #expect(letters.count == 16 + 6)

        let chapter = ReadingChallengeChapters.chapterID(43_003)
        #expect(chapter == ChapterID(book: 43, chapter: 3))
        #expect(ReadingChallengeChapters.raw(chapter) == 43_003)
    }

    @Test func readingSelectionAndTitle() {
        var selection = ReadingChallengeSelection()
        selection.choose(book: 41)
        #expect(selection.chapters.count == 16)
        #expect(selection.name == "Mark")
        let title = ChallengeTitleSuggestion.reading(selection, days: 14)
        #expect(title == "Read Mark in 14 days")

        selection.choose(book: 45)
        selection.lastChapter = 8
        #expect(selection.name == "Romans 1\u{2013}8")

        selection.choose(books: [45, 46])
        #expect(!selection.isSingleBook)
        #expect(selection.chapters.count == 16 + 16)
        selection.choose(books: [])
        #expect(selection.books == [45, 46], "Choosing nothing keeps the books")
    }

    // MARK: Memorise and drafts

    @Test func passagesAreOneChapterAndShort() {
        let psalm = ChallengePassage.parse("Psalm 23:1-3")
        #expect(psalm?.start == VerseID(book: 19, chapter: 23, verse: 1))
        #expect(psalm?.end == VerseID(book: 19, chapter: 23, verse: 3))
        // The parsed passage is a tuple (not Equatable), so compare outside #expect.
        let wholeChapterRefused = ChallengePassage.parse("John 3") == nil
        #expect(wholeChapterRefused)
        let tooLongRefused = ChallengePassage.parse("Psalm 119:1-40") == nil
        #expect(tooLongRefused)
    }

    @Test func draftsFollowTheServersRules() {
        let today = date(2026, 10, 6)
        var draft = GroupChallengeDraft(kind: .streak, title: "Read every day", startsOn: today, days: 21)
        let valid = draft.isValid(today: today, calendar: chicago)
        #expect(valid)

        draft.startsOn = date(2026, 12, 25)
        let tooFarAhead = draft.isValid(today: today, calendar: chicago)
        #expect(!tooFarAhead)

        draft.startsOn = today
        draft.days = 91
        let tooLong = draft.isValid(today: today, calendar: chicago)
        #expect(!tooLong)

        let reading = GroupChallengeDraft(kind: .reading, title: "Read Mark", startsOn: today, days: 14)
        let noChapters = reading.isValid(today: today, calendar: chicago)
        #expect(!noChapters)

        let untitled = GroupChallengeDraft(kind: .prayer, title: "   ", startsOn: today, days: 7)
        let blankTitle = untitled.isValid(today: today, calendar: chicago)
        #expect(!blankTitle)
    }

    // MARK: In-memory server

    private func fails(_ operation: () async throws -> Void) async -> Bool {
        do {
            try await operation()
            return false
        } catch {
            return true
        }
    }

    /// Signed in as "Sam": a member of the sample group and leader of a new one.
    private func makeBackend(clock: TestClock) async throws -> (backend: InMemoryGroupChallengeBackend, community: InMemoryCommunityBackend, myGroup: UUID) {
        let community = InMemoryCommunityBackend()
        try await community.setDisplayName("Sam")
        _ = try await community.requestToJoin(code: InMemoryCommunityBackend.sampleInviteCode)
        let myGroup = try await community.createGroup(GroupDraft(name: "Home Group"))
        let backend = InMemoryGroupChallengeBackend(community: community, calendar: chicago, now: { clock.date }, seeded: true)
        return (backend, community, myGroup)
    }

    private func streakDraft(_ clock: TestClock, days: Int = 7) -> GroupChallengeDraft {
        GroupChallengeDraft(kind: .streak, title: "Read every day", startsOn: clock.date, days: days)
    }

    @Test func onlyLeadersStartAndEndChallenges() async throws {
        let clock = TestClock(date(2026, 10, 6))
        let (backend, _, myGroup) = try await makeBackend(clock: clock)
        let sample = InMemoryGroupChallengeBackend.sampleGroupID

        let memberCreates = await fails { _ = try await backend.createChallenge(streakDraft(clock), in: sample) }
        #expect(memberCreates, "Members can't start challenges")
        let leaderCreates = await fails { _ = try await backend.createChallenge(streakDraft(clock), in: myGroup) }
        #expect(!leaderCreates)

        let seeded = try await backend.challenges(in: sample)
        #expect(seeded.count == 2, "The sample group has a streak and a passage")
        let first = try #require(seeded.first)
        let memberEnds = await fails { try await backend.endChallenge(first.id) }
        #expect(memberEnds, "Members can't end challenges")
    }

    @Test func aGroupRunsAtMostFiveChallenges() async throws {
        let clock = TestClock(date(2026, 10, 6))
        let (backend, _, myGroup) = try await makeBackend(clock: clock)
        for _ in 0..<GroupChallengeRules.maximumRunning {
            _ = try await backend.createChallenge(streakDraft(clock), in: myGroup)
        }
        let sixth = await fails { _ = try await backend.createChallenge(streakDraft(clock), in: myGroup) }
        #expect(sixth)

        // Once they've finished, there's room again.
        clock.date = date(2026, 10, 20)
        let afterwards = await fails { _ = try await backend.createChallenge(streakDraft(clock), in: myGroup) }
        #expect(!afterwards)
    }

    @Test func daysCantBeTickedAhead() async throws {
        let clock = TestClock(date(2026, 10, 6))
        let (backend, _, myGroup) = try await makeBackend(clock: clock)
        let id = try await backend.createChallenge(streakDraft(clock), in: myGroup)

        let todayFails = await fails { try await backend.setCheckin(true, item: 1, challenge: id) }
        let tomorrowFails = await fails { try await backend.setCheckin(true, item: 2, challenge: id) }
        let laterFails = await fails { try await backend.setCheckin(true, item: 3, challenge: id) }
        #expect(!todayFails)
        #expect(!tomorrowFails, "A day's slack, as on the server")
        #expect(laterFails)

        let rows = try await backend.progress(of: id)
        let me = rows.first { $0.displayName == "Sam" }
        #expect(me?.items == [1, 2])
        #expect(me?.done == 2)
    }

    @Test func endedChallengesRefuseTicks() async throws {
        let clock = TestClock(date(2026, 10, 6))
        let (backend, _, myGroup) = try await makeBackend(clock: clock)
        let short = try await backend.createChallenge(streakDraft(clock, days: 3), in: myGroup)
        clock.date = date(2026, 10, 11)
        let afterTheEnd = await fails { try await backend.setCheckin(true, item: 3, challenge: short) }
        #expect(afterTheEnd)

        clock.date = date(2026, 10, 6)
        let ended = try await backend.createChallenge(streakDraft(clock), in: myGroup)
        try await backend.setCheckin(true, item: 1, challenge: ended)
        try await backend.endChallenge(ended)
        let afterEnding = await fails { try await backend.setCheckin(true, item: 2, challenge: ended) }
        #expect(afterEnding)

        // Ended early, it stays with everyone's progress, as finished.
        let remaining = try await backend.challenges(in: myGroup)
        let kept = remaining.first { $0.id == ended }
        let endedChallenge = try #require(kept)
        #expect(endedChallenge.endedAt != nil)
        let status = endedChallenge.status(on: clock.date, calendar: chicago)
        #expect(status == .finished)
        let rows = try await backend.progress(of: ended)
        let mine = rows.first { $0.displayName == "Sam" }
        #expect(mine?.done == 1)
    }

    @Test func endedChallengesMakeRoomAndAreFinished() async throws {
        let clock = TestClock(date(2026, 10, 6))
        let (backend, _, myGroup) = try await makeBackend(clock: clock)
        var ids: [UUID] = []
        for _ in 0..<GroupChallengeRules.maximumRunning {
            let id = try await backend.createChallenge(streakDraft(clock), in: myGroup)
            ids.append(id)
        }
        let first = try #require(ids.first)
        try await backend.endChallenge(first)
        let another = await fails { _ = try await backend.createChallenge(streakDraft(clock), in: myGroup) }
        #expect(!another, "Ended challenges don't count toward the five")

        let endedNow = challenge(.streak, start: "2026-10-06", days: 7)
        var stopped = endedNow
        stopped.endedAt = clock.date
        let runningStatus = endedNow.status(on: clock.date, calendar: chicago)
        let stoppedStatus = stopped.status(on: clock.date, calendar: chicago)
        let stoppedCanTick = stopped.canTick(1, on: clock.date, calendar: chicago)
        #expect(runningStatus == .running)
        #expect(stoppedStatus == .finished)
        #expect(!stoppedCanTick)
    }

    @Test func othersChaptersStayPrivate() async throws {
        let clock = TestClock(date(2026, 10, 6))
        let (backend, community, myGroup) = try await makeBackend(clock: clock)
        var draft = GroupChallengeDraft(kind: .reading, title: "Read Mark", startsOn: clock.date, days: 14)
        draft.chapters = ReadingChallengeChapters.chapters(books: [41])
        let id = try await backend.createChallenge(draft, in: myGroup)
        try await backend.setCheckin(true, item: 41_001, challenge: id)
        let wrongChapter = await fails { try await backend.setCheckin(true, item: 42_001, challenge: id) }
        #expect(wrongChapter, "Only the challenge's chapters")

        let me = await community.currentUserID()
        let rows = try await backend.progress(of: id)
        let mine = rows.first { $0.userID == me }
        #expect(mine?.items == [41_001])
    }

    @Test func modelTicksStraightAway() async throws {
        let clock = TestClock(date(2026, 10, 6))
        let (backend, community, myGroup) = try await makeBackend(clock: clock)
        let store = CommunityStore(backend: community)
        await store.refresh()
        let model = GroupChallengesModel(groupID: myGroup, backend: backend, store: store, calendar: chicago, now: { clock.date })
        #expect(model.canManage)

        let id = await model.create(streakDraft(clock))
        let createdID = try #require(id)
        let found = model.challenge(createdID)
        let created = try #require(found)
        await model.setDone(true, item: 1, in: created)
        let summary = model.summary(for: created)
        #expect(summary.myDone == 1)
        #expect(summary.stillGoing == 1)
        let ticked = model.hasTicked(1, in: created)
        #expect(ticked)

        // A day ahead of the slack is refused and put back.
        await model.setDone(true, item: 5, in: created)
        let refused = model.hasTicked(5, in: created)
        #expect(!refused)
        #expect(model.errorMessage != nil)
    }
}
