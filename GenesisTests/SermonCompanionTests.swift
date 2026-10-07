import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Genesis

private var chicago: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    calendar.firstWeekday = 1
    return calendar
}

private func date(_ month: Int, _ day: Int, _ hour: Int = 10, year: Int = 2026) -> Date {
    chicago.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private func sermon(
    _ title: String = "",
    preacher: String = "",
    church: String = "",
    series: String = "",
    body: String = "",
    on preachedAt: Date,
    favourite: Bool = false,
    hasContent: Bool = true
) -> SermonFacts {
    SermonFacts(
        id: UUID(),
        title: title,
        preacher: preacher,
        church: church,
        series: series,
        body: body,
        preachedAt: preachedAt,
        isFavourite: favourite,
        hasContent: hasContent
    )
}

@Suite("Sermon grouping")
struct SermonGroupingTests {
    @Test func thisWeekThenEarlierMonthsNewestFirst() {
        // Wednesday 7 October 2026; the week began on Sunday the 4th.
        let now = date(10, 7, 12)
        let sunday = sermon("Grace upon grace", on: date(10, 4))
        let lateSeptember = sermon("Living water", on: date(9, 27))
        let earlySeptember = sermon("The vine", on: date(9, 6))
        let august = sermon("The good shepherd", on: date(8, 30))
        let sections = SermonGrouping.byDate([august, earlySeptember, sunday, lateSeptember], now: now, calendar: chicago)
        let kinds = sections.map(\.kind)
        #expect(kinds == [.thisWeek, .month(date(9, 1, 0)), .month(date(8, 1, 0))])
        let september = sections[1].sermons.map(\.id)
        #expect(september == [lateSeptember.id, earlySeptember.id], "Newest first within a month")
        let thisWeek = sections[0].sermons.map(\.id)
        #expect(thisWeek == [sunday.id])
    }

    @Test func lastSaturdayIsNotThisWeek() {
        let now = date(10, 7, 12)
        let sections = SermonGrouping.byDate([sermon("Saturday", on: date(10, 3, 19))], now: now, calendar: chicago)
        let kinds = sections.map(\.kind)
        #expect(kinds == [.month(date(10, 1, 0))])
    }

    @Test func byChurchIgnoresCaseSpacingAndAccents() {
        let first = sermon("One", church: "Grace Chapel", on: date(9, 6))
        let second = sermon("Two", church: "grace  chapel ", on: date(9, 13))
        let third = sermon("Three", church: "Iglesia Bautista", on: date(9, 20))
        let fourth = sermon("Four", church: "iglesia bautísta", on: date(9, 27))
        let none = sermon("Five", church: "  ", on: date(10, 4))
        let sections = SermonGrouping.byChurch([first, second, third, fourth, none])
        let kinds = sections.map(\.kind)
        #expect(kinds == [.church("grace  chapel"), .church("iglesia bautísta"), .noChurch], "A to Z, named as most recently typed, no church last")
        let grace = sections[0].sermons.map(\.id)
        #expect(grace == [second.id, first.id])
    }

    @Test func churchSuggestionsMostRecentFirst() {
        let sermons = [
            sermon(church: "Grace Chapel", on: date(9, 6)),
            sermon(church: "City Church", on: date(9, 13)),
            sermon(church: "grace chapel", on: date(9, 20)),
            sermon(church: "Iglesia Bautista", on: date(9, 27)),
        ]
        let all = SermonGrouping.churchSuggestions(sermons, typed: "")
        #expect(all == ["Iglesia Bautista", "grace chapel", "City Church"])
        let typed = SermonGrouping.churchSuggestions(sermons, typed: "gra")
        #expect(typed == ["grace chapel"])
        let exact = SermonGrouping.churchSuggestions(sermons, typed: "Grace Chapel")
        #expect(exact.isEmpty, "Nothing to suggest once it's typed in full")
    }

    @Test func searchCoversEveryField() {
        let notes = sermon("Sunday", preacher: "Pastor Ruth", church: "Grace Chapel", series: "Galatians", body: "## Freedom\n- **Walk** by the Spirit", on: date(10, 4))
        #expect(SermonSearch.matches(notes, query: "ruth"))
        #expect(SermonSearch.matches(notes, query: "GRACE"))
        #expect(SermonSearch.matches(notes, query: "galatians"))
        #expect(SermonSearch.matches(notes, query: "walk by"), "Marks don't get in the way")
        #expect(SermonSearch.matches(notes, query: "freedom"))
        #expect(!SermonSearch.matches(notes, query: "exodus"))
        #expect(SermonSearch.matches(notes, query: "  "))
    }

    @Test func favouritesFilterAndEmptySermons() {
        let favourite = sermon("Kept", on: date(9, 6), favourite: true)
        let other = sermon("Other", on: date(9, 13))
        let empty = sermon(on: date(9, 20), hasContent: false)
        let all = SermonGrouping.visible([favourite, other, empty], query: "", favouritesOnly: false).map(\.id)
        #expect(all == [other.id, favourite.id], "Empty notes are left out, newest first")
        let favourites = SermonGrouping.visible([favourite, other, empty], query: "", favouritesOnly: true).map(\.id)
        #expect(favourites == [favourite.id])
        let searched = SermonGrouping.visible([favourite, other], query: "other", favouritesOnly: true)
        #expect(searched.isEmpty)
    }

    @Test func untitledSermonsUseTheirFirstLine() {
        let untitled = sermon(body: "## Hope that holds\nMore", on: date(9, 6))
        #expect(untitled.displayTitle == "Hope that holds")
    }

    @Test func sundayMorningCard() {
        #expect(SermonSunday.isSundayMorning(date(10, 4, 9), calendar: chicago))
        #expect(!SermonSunday.isSundayMorning(date(10, 4, 18), calendar: chicago), "Not Sunday evening")
        #expect(!SermonSunday.isSundayMorning(date(10, 7, 9), calendar: chicago), "Not Wednesday")
    }
}

@Suite("Sermon Markdown")
struct SermonMarkdownTests {
    @Test func spansFollowTheMarks() {
        let spans = SermonMarkdown.spans("God is **love** and *light*")
        #expect(spans == [
            .init(text: "God is "),
            .init(text: "love", bold: true),
            .init(text: " and "),
            .init(text: "light", italic: true),
        ])
        #expect(SermonMarkdown.spans("***grace***") == [.init(text: "grace", bold: true, italic: true)])
        #expect(SermonMarkdown.spans("5 * 3 and a\\*b") == [.init(text: "5 * 3 and a*b")], "Lone and escaped asterisks stay")
    }

    @Test func spansBackToMarkdown() {
        let spans: [SermonMarkdown.Span] = [
            .init(text: "Be "),
            .init(text: "still ", bold: true),
            .init(text: "and", bold: true),
            .init(text: " 2*3"),
        ]
        #expect(SermonMarkdown.markdown(spans) == "Be **still and** 2\\*3", "Marks hug the words; asterisks are escaped")
        #expect(SermonMarkdown.spans(SermonMarkdown.markdown(spans)).map(\.text).joined() == "Be still and 2*3")
    }

    @Test func blocksForTheFormattedView() {
        let blocks = SermonMarkdown.blocks("## Point one\n\n- **Pray**\n2. Read\n> Be still\nPlain")
        let kinds = blocks.map(\.kind)
        #expect(kinds == [.heading, .bullet, .numbered(2), .quote, .paragraph])
        let texts = blocks.map(\.text)
        #expect(texts == ["Point one", "**Pray**", "Read", "Be still", "Plain"])
    }

    @Test func plainTextDropsTheMarks() {
        let plain = SermonMarkdown.plainText("## Title\n- **bold** and *italic*\n> quote")
        #expect(plain == "Title\nbold and italic\nquote")
    }

    @Test func insertingAReference() {
        let middle = SermonMarkdown.inserting("John 3:16", into: "Read and pray", at: 4)
        #expect(middle.text == "Read John 3:16 and pray")
        #expect(middle.selection == 14..<14)
        let end = SermonMarkdown.inserting("Juan 3:16", into: "Notes", at: nil)
        #expect(end.text == "Notes\nJuan 3:16")
        let empty = SermonMarkdown.inserting("John 1:1", into: "", at: nil)
        #expect(empty.text == "John 1:1")
    }
}

@MainActor
@Suite("Sermon rich text")
struct SermonRichTextTests {
    private let style = SermonRichText.Style()
    private let context = EnvironmentValues().fontResolutionContext

    private func roundTrip(_ markdown: String) -> String {
        SermonRichText.markdown(SermonRichText.attributed(markdown, style: style), context: context)
    }

    private func markdown(_ text: AttributedString) -> String {
        SermonRichText.markdown(text, context: context)
    }

    @Test func notesShowWithoutMarks() {
        let text = SermonRichText.attributed("## Point one\n- **Pray** and *wait*\n2. Read\n> Be still", style: style)
        #expect(String(text.characters) == "Point one\n\u{2022} Pray and wait\n2. Read\nBe still")
    }

    @Test func notesRoundTrip() {
        let notes = "## Point one\n- **Pray** and *wait*\n2. Read\n> Be **still**\n\nPlain ***both***"
        #expect(roundTrip(notes) == notes)
        #expect(roundTrip("") == "")
        #expect(roundTrip("* Item") == "- Item", "Bullets are saved one way")
    }

    @Test func headingTogglesOnTheCursorsLine() {
        let text = SermonRichText.attributed("Intro\nMain point\nEnd", style: style)
        let heading = SermonRichText.toggling(.heading, in: text, selection: 8..<8, style: style, context: context)
        #expect(markdown(heading.text) == "Intro\n## Main point\nEnd")
        #expect(heading.selection == 16..<16, "The cursor ends up at the end of the line")
        let removed = SermonRichText.toggling(.heading, in: heading.text, selection: 10..<10, style: style, context: context)
        #expect(markdown(removed.text) == "Intro\nMain point\nEnd")
    }

    @Test func listsCoverEverySelectedLine() {
        let text = SermonRichText.attributed("Love\nJoy\nPeace", style: style)
        let bullets = SermonRichText.toggling(.bullet, in: text, selection: 0..<15, style: style, context: context)
        #expect(markdown(bullets.text) == "- Love\n- Joy\n- Peace")
        let numbered = SermonRichText.toggling(.numbered, in: bullets.text, selection: bullets.selection, style: style, context: context)
        #expect(markdown(numbered.text) == "1. Love\n2. Joy\n3. Peace", "Switching replaces the old mark")
        let plain = SermonRichText.toggling(.numbered, in: numbered.text, selection: numbered.selection, style: style, context: context)
        #expect(markdown(plain.text) == "Love\nJoy\nPeace")
        let quote = SermonRichText.toggling(.quote, in: SermonRichText.attributed("- Love\nJoy", style: style), selection: 2..<2, style: style, context: context)
        #expect(markdown(quote.text) == "> Love\nJoy", "A quote replaces the list mark")
    }

    @Test func joinedLinesTakeTheFirstLinesStyle() {
        let text = SermonRichText.attributed("## Title\nBody\n> Quote", style: style)
        let joined = SermonRichText.replacing(5..<6, with: AttributedString(), in: text)
        #expect(markdown(SermonRichText.normalized(joined, style: style, context: context)) == "## TitleBody\n> Quote")
        let intoPlain = SermonRichText.replacing(10..<11, with: AttributedString(), in: text)
        #expect(markdown(SermonRichText.normalized(intoPlain, style: style, context: context)) == "## Title\nBodyQuote")
    }

    @Test func returnCarriesListsOn() {
        let ended = SermonRichText.endedLine(old: "Intro\n\u{2022} Milk", new: "Intro\n\u{2022} Milk\n", cursor: 13)
        #expect(ended?.start == 6)
        #expect(ended?.text == "\u{2022} Milk")
        #expect(SermonRichText.endedLine(old: "ab", new: "abc", cursor: 3) == nil, "Only a typed line break")
        #expect(SermonRichText.continuation(of: "\u{2022} Milk") == "\u{2022} ")
        #expect(SermonRichText.continuation(of: "2. Read") == "3. ")
        #expect(SermonRichText.continuation(of: "Plain") == nil)
        #expect(SermonRichText.endsList("\u{2022} "))
        #expect(SermonRichText.endsList("4. "))
        #expect(!SermonRichText.endsList(""))
    }
}

@Suite("Sermon verse lookup")
struct SermonLookupTests {
    private func resolve(_ text: String, inBible: Bool = true) -> SermonLookup.Outcome {
        SermonLookup.resolve(text, lastVerse: { _ in 6 }, hasVerses: { _ in inBible })
    }

    @Test func englishAndSpanishNames() {
        let john = PrayerPassage(start: VerseID(rawValue: 43_003_016), end: VerseID(rawValue: 43_003_016))
        let english = resolve("John 3:16")
        let spanish = resolve("Juan 3:16")
        let accentless = resolve("  juan 3:16 ")
        #expect(english == .found(john))
        #expect(spanish == .found(john))
        #expect(accentless == .found(john))
        let psalm = resolve("Salmos 23")
        let wholePsalm = PrayerPassage(start: VerseID(rawValue: 19_023_001), end: VerseID(rawValue: 19_023_006))
        #expect(psalm == .found(wholePsalm), "A whole chapter runs to its last verse")
        let range = resolve("1 Corintios 13:4-7")
        let love = PrayerPassage(start: VerseID(rawValue: 46_013_004), end: VerseID(rawValue: 46_013_007))
        #expect(range == .found(love))
    }

    @Test func otherOutcomes() {
        let empty = resolve("   ")
        let nonsense = resolve("hello there")
        let missing = resolve("John 3:16", inBible: false)
        #expect(empty == .empty)
        #expect(nonsense == .notAReference)
        #expect(missing == .notInBible)
    }
}

@Suite("Church Mode screen")
struct ChurchModeScreenTests {
    @Test func keepsAwakeOnlyWhileOnShowingAndActive() {
        #expect(ScreenAwakeKeeper.shouldKeepAwake(churchMode: true, isShowing: true, isActive: true))
        #expect(!ScreenAwakeKeeper.shouldKeepAwake(churchMode: false, isShowing: true, isActive: true))
        #expect(!ScreenAwakeKeeper.shouldKeepAwake(churchMode: true, isShowing: false, isActive: true))
        #expect(!ScreenAwakeKeeper.shouldKeepAwake(churchMode: true, isShowing: true, isActive: false))
    }

    @Test func restoresTheIdleTimerOnLeaving() {
        var keeper = ScreenAwakeKeeper()
        let enter = keeper.update(keepAwake: true, current: false)
        #expect(enter == true)
        #expect(keeper.isHolding)
        let again = keeper.update(keepAwake: true, current: true)
        #expect(again == nil, "Nothing to change while it holds")
        let leave = keeper.update(keepAwake: false, current: true)
        #expect(leave == false, "Back as it was")
        #expect(!keeper.isHolding)
        let idle = keeper.update(keepAwake: false, current: false)
        #expect(idle == nil)
    }

    @Test func backgroundAndBack() {
        var keeper = ScreenAwakeKeeper()
        _ = keeper.update(keepAwake: true, current: false)
        let background = keeper.update(keepAwake: false, current: true)
        #expect(background == false)
        let foreground = keeper.update(keepAwake: true, current: false)
        #expect(foreground == true)
    }

    @Test func leavesSomeoneElsesSettingAlone() {
        // Something else had already kept the screen awake.
        var keeper = ScreenAwakeKeeper()
        let enter = keeper.update(keepAwake: true, current: true)
        #expect(enter == nil)
        let leave = keeper.update(keepAwake: false, current: true)
        #expect(leave == nil, "It stays awake, as it was before")
    }
}

@Suite("Hidden features")
@MainActor
struct HiddenFeatureTests {
    @Test func prayerRemindersPauseAndResumeWithTheSwitch() {
        #expect(PrayerReminders.change(wasOn: nil, isOn: false) == .pauseAll, "Off at launch clears them")
        #expect(PrayerReminders.change(wasOn: nil, isOn: true) == .none)
        #expect(PrayerReminders.change(wasOn: true, isOn: false) == .pauseAll)
        #expect(PrayerReminders.change(wasOn: false, isOn: true) == .resumeAll)
        #expect(PrayerReminders.change(wasOn: true, isOn: true) == .none)
    }

    @Test func pausedRemindersArentScheduled() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let later = now.addingTimeInterval(3600)
        let earlier = now.addingTimeInterval(-3600)
        #expect(PrayerReminders.shouldSchedule(isAnswered: false, reminderAt: later, repeatsDaily: false, paused: false, now: now))
        #expect(!PrayerReminders.shouldSchedule(isAnswered: false, reminderAt: later, repeatsDaily: false, paused: true, now: now))
        #expect(!PrayerReminders.shouldSchedule(isAnswered: true, reminderAt: later, repeatsDaily: false, paused: false, now: now))
        #expect(!PrayerReminders.shouldSchedule(isAnswered: false, reminderAt: earlier, repeatsDaily: false, paused: false, now: now))
        #expect(PrayerReminders.shouldSchedule(isAnswered: false, reminderAt: earlier, repeatsDaily: true, paused: false, now: now))
        #expect(!PrayerReminders.shouldSchedule(isAnswered: false, reminderAt: nil, repeatsDaily: true, paused: false, now: now))
    }

    @Test func hiddenMemoriseLeavesItsWidgetEmpty() throws {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(MemoryVerse(start: VerseID(rawValue: 43_003_016), end: VerseID(rawValue: 43_003_016), translationID: "KJV"))
        try context.save()
        let defaults = try #require(UserDefaults(suiteName: "hidden-memorise-\(UUID())"))
        let library = BibleLibrary(defaults: defaults)
        let progress = ReadingProgress(defaults: defaults)
        let shown = WidgetSnapshotWriter.make(library: library, progress: progress, context: context, isPremium: true)
        let hidden = WidgetSnapshotWriter.make(library: library, progress: progress, context: context, isPremium: true, memoriseShown: false)
        #expect(shown.memorise?.total == 1)
        #expect(shown.memorise?.isHidden == nil)
        #expect(hidden.memorise?.isHidden == true)
        #expect(hidden.memorise?.reference == nil, "No passage while it's switched off")
        #expect(hidden.memorise?.hint == nil)
        #expect(hidden.memorise?.total == 0)
    }

    @Test func olderSnapshotsDecodeWithoutTheHiddenFlag() throws {
        let json = #"{"isUnlocked":true,"dueDates":[],"total":0}"#
        let memorise = try JSONDecoder().decode(WidgetSnapshot.Memorise.self, from: Data(json.utf8))
        #expect(memorise.isHidden == nil)
    }
}

@Suite("Sermon Notes switch")
@MainActor
struct SermonFeatureTests {
    @Test func hasItsOwnSwitchThatStartsOnForSavedChoices() {
        let defaults = UserDefaults(suiteName: "Sermons-\(UUID())")!
        // A choice saved before Sermon Notes existed.
        let known = OptionalFeature.allCases.map(\.rawValue).filter { $0 != OptionalFeature.sermons.rawValue }
        defaults.set(["prayer"], forKey: "features.enabled")
        defaults.set(known, forKey: "features.known")
        defaults.set(true, forKey: "features.chosen")
        let features = FeaturePreferences(defaults: defaults)
        #expect(features.isOn(.sermons))
        #expect(!features.isOn(.plans), "Everything else stays as chosen")
        #expect(OptionalFeature.sermons.legacyParent == nil)
        #expect(OptionalFeature.sermons.area == .study)
        #expect(OptionalFeature.sermons.isOfferedInSetup)
        #expect(OptionalFeature.defaults.contains(.sermons))
    }

    @Test func entryPointsBelongToTheSwitch() {
        #expect(HomeRoute.sermons.feature == .sermons)
        #expect(LibraryView.Shelf.sermons.feature == .sermons)
        #expect(LibraryView.Shelf.notes.feature == nil)
        #expect(WhatsNewCatalog.sermonCompanion.feature == .sermons)
        #expect(WhatsNewCatalog.sermonCompanion.flag == nil)
        let ids = WhatsNewCatalog.all.map(\.id)
        #expect(ids.contains("sermon-companion-church-mode"))
    }
}

@Suite("Sermon sync")
@MainActor
struct SermonSyncTests {
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private func makeSermon() throws -> (Sermon, ModelContainer) {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = StudyStore(context: container.mainContext)
        let sermon = store.createSermon(church: "Grace Chapel", on: Date(timeIntervalSince1970: 1_791_000_000))
        sermon.title = "Grace upon grace"
        sermon.preacher = "Pastor Ruth"
        sermon.body = "## Grace\n- **Full** of grace"
        let passage = PrayerPassage(start: VerseID(rawValue: 43_001_014), end: VerseID(rawValue: 43_001_016))
        store.attach(passage, to: sermon)
        return (sermon, container)
    }

    private func json(_ row: RemoteSermon) throws -> [String: Any] {
        let data = try SupabaseCoding.encoder().encode(row)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(object)
    }

    @Test func goesUpWithIdsOnlyAndExplicitNulls() throws {
        let (sermon, container) = try makeSermon()
        _ = container
        let object = try json(RemoteSermon(sermon, userID: userID))
        let passages = try #require(object["passages"] as? [[String: Any]])
        #expect(passages.count == 1)
        #expect(passages.first?["start_verse"] as? Int == 43_001_014)
        #expect(passages.first?["end_verse"] as? Int == 43_001_016)
        #expect(object["series"] is NSNull, "No series goes up as null")
        #expect(object["preached_at"] is String)
        #expect(object["is_favourite"] as? Bool == false)
        #expect(object["church"] as? String == "Grace Chapel")
        #expect(!object.keys.contains("deleted_at"))
    }

    @Test func roundTrip() throws {
        let (sermon, container) = try makeSermon()
        _ = container
        sermon.series = "John"
        sermon.isFavourite = true
        let encoded = try SupabaseCoding.encoder().encode(RemoteSermon(sermon, userID: userID))
        let decoded = try SupabaseCoding.decoder().decode(RemoteSermon.self, from: encoded)
        let passages = decoded.sermonPassages
        #expect(passages == sermon.passages)
        #expect(decoded.title == "Grace upon grace")
        #expect(decoded.series == "John")
        #expect(decoded.isFavourite)
        #expect(decoded.body == sermon.body)
        let preached = decoded.preachedAt.timeIntervalSince1970
        #expect(abs(preached - 1_791_000_000) < 0.001)
    }

    @Test func rowsWithoutOptionalFieldsDecode() throws {
        let json = """
        {"id":"33333333-0000-0000-0000-000000000001","user_id":"\(userID.uuidString)",
         "created_at":"2026-10-04T15:00:00.000000+00:00","updated_at":"2026-10-04T16:00:00.000000+00:00",
         "server_updated_at":"2026-10-04T16:00:01.123456+00:00"}
        """
        let row = try SupabaseCoding.decoder().decode(RemoteSermon.self, from: Data(json.utf8))
        #expect(row.title.isEmpty)
        #expect(row.church.isEmpty)
        #expect(row.series == nil)
        #expect(row.passages.isEmpty)
        #expect(!row.isFavourite)
        #expect(row.deletedAt == nil)
        #expect(row.preachedAt == row.createdAt, "Falls back to when it was written")
    }

    @Test func passagesThatArentVerseIdsAreSkipped() throws {
        let json = """
        {"id":"33333333-0000-0000-0000-000000000002","user_id":"\(userID.uuidString)","title":"T","preacher":"","church":"",
         "preached_at":"2026-10-04T15:00:00.000000+00:00","series":null,"body":"","is_favourite":true,
         "passages":[{"start_verse":43003016,"end_verse":43003016},{"start_verse":5,"end_verse":5}],
         "created_at":"2026-10-04T15:00:00.000000+00:00","updated_at":"2026-10-04T16:00:00.000000+00:00",
         "deleted_at":null,"server_updated_at":"2026-10-04T16:00:01.123456+00:00"}
        """
        let row = try SupabaseCoding.decoder().decode(RemoteSermon.self, from: Data(json.utf8))
        let ids = row.sermonPassages.map(\.id)
        #expect(ids == ["43003016-43003016"])
        #expect(row.isFavourite)
    }

    @Test func storeKeepsPassagesOnceAndDeletesWithATombstone() throws {
        let (sermon, container) = try makeSermon()
        let context = container.mainContext
        let store = StudyStore(context: context)
        let extra = PrayerPassage(start: VerseID(rawValue: 43_003_016), end: VerseID(rawValue: 43_003_016))
        store.attach(extra, to: sermon)
        store.attach(extra, to: sermon)
        #expect(sermon.passages.count == 2, "Each passage once")
        store.toggleFavourite(sermon)
        #expect(sermon.isFavourite)
        let count = store.sermonCount()
        #expect(count == 1)

        let id = sermon.id
        store.delete(sermon)
        let tombstones = try context.fetch(FetchDescriptor<Tombstone>())
        #expect(tombstones.count == 1)
        #expect(tombstones.first?.recordID == id)
        #expect(tombstones.first?.table == "sermons")
        let remaining = try context.fetchCount(FetchDescriptor<Sermon>())
        #expect(remaining == 0)
    }
}
