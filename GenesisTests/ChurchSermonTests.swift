import Foundation
import SwiftData
import Testing
@testable import Genesis

/// Church sermons in the app (VRS-18): reading what the database functions
/// return, the outline's helpers (the same as the guest page's), links, verse
/// numbering, the in-memory server's rules and the person's own notes.
struct ChurchSermonWireTests {
    private let sermonJSON = """
    {"status":"ok","id":"5b7a1c9e-0000-4000-8000-000000000001","slug":"abcde12345",
     "group_id":"00000000-0000-0000-0000-00000000c0de","church":"Grace Fellowship",
     "title":"Rest for the Weary","speaker":"Ana","series":"Come to Me","preached_on":"2026-11-15",
     "time_zone":"America/Chicago","location":"Main hall","language":"en",
     "cover":{"id":"9","path":"g/s/c.jpg","alt":"A lake","decorative":false},
     "audience":"members","revision":2,"published_at":"2026-11-15T15:00:00+00:00",
     "blocks":[
       {"id":"a","kind":"paragraph","text":"Welcome."},
       {"id":"h1","kind":"heading","text":"Rest","level":2},
       {"id":"s","kind":"scripture","ref":{"raw":"Mt 11:28-30","start":40011028,"end":40011030,"status":"verified","label":"KJV","translation":"KJV","quote_withheld":false}},
       {"id":"n","kind":"scripture","ref":{"raw":"Rom 8:28","start":45008028,"end":null,"status":"verified","label":"NIV","translation":"NIV","quote_withheld":true}},
       {"id":"x","kind":"poll","question":"From a later version"},
       {"id":"u","kind":"scripture","ref":{"raw":"Jo 99:99","start":null,"end":null,"status":"unlinked","label":null,"translation":null,"quote_withheld":false}},
       {"id":"l","kind":"list","items":["Come","Learn"],"ordered":true}
     ],
     "previous":null,
     "next":{"slug":"fghij67890","title":"The Good Shepherd","speaker":"Ana","series":"Come to Me","preached_on":"2026-11-22","audience":"link","published_at":"2026-11-22T15:00:00+00:00"},
     "is_member":true,
     "locations":[{"name":"Main Campus","address":"1 Hill Rd, Austin, TX","times":"Sundays 9:00 and 11:00 AM\\n\\nWednesdays 7:00 PM"},
                  {"name":"  ","address":"","times":""},
                  {"name":"Online","address":"","times":""},
                  {"name":"Lancaster","street":"2827 Saint Martin Dr.","city":"Lancaster","region":"TX","postal_code":"75146","country":"United States",
                   "address":"2827 Saint Martin Dr., Lancaster, TX 75146, United States","times":"",
                   "gatherings":[{"day":"sun","time":"11:00","note":""},{"day":"wed","time":"19:00","note":"Bible study"},{"day":"sun","time":"09:00","note":""},
                                 {"date":"2026-11-26","time":"18:00","note":"Thanksgiving"},{"date":"2026-11-01","time":"18:00","note":""},
                                 {"day":"someday","time":"09:00"},{"day":"sun","time":"9am"}]}]}
    """

    private func decoded() throws -> PublishedSermon {
        let lookup = try ChurchSermonWire.lookup(from: Data(sermonJSON.utf8))
        guard case let .sermon(sermon) = lookup else {
            Issue.record("Expected a sermon")
            throw CancellationError()
        }
        return sermon
    }

    @Test func readsThePublishedSermon() throws {
        let sermon = try decoded()
        #expect(sermon.slug == "abcde12345")
        #expect(sermon.church == "Grace Fellowship")
        #expect(sermon.audience == .members)
        #expect(sermon.series == "Come to Me")
        #expect(sermon.cover?.path == "g/s/c.jpg")
        #expect(sermon.isMember)
        #expect(sermon.next?.slug == "fghij67890")
        #expect(sermon.previous == nil)
        // The poll from a later version is skipped; everything else stays.
        #expect(sermon.blocks.map { $0.id } == ["a", "h1", "s", "n", "u", "l"])
    }

    @Test func readsTheChurchsLocationsAndTimes() throws {
        let locations = try decoded().locations
        // A place without a name is left out; the rest keep the church's words.
        #expect(locations.map(\.name) == ["Main Campus", "Online", "Lancaster"])
        #expect(locations[0].timeLines == ["Sundays 9:00 and 11:00 AM", "Wednesdays 7:00 PM"])
        #expect(locations[0].mapsURL?.absoluteString == "https://maps.apple.com/?q=1%20Hill%20Rd,%20Austin,%20TX")
        #expect(locations[1].mapsURL == nil)
        #expect(locations[1].timeLines.isEmpty)
    }

    @Test func readsTheAddressInPartsAndTheGatherings() throws {
        let place = try decoded().locations[2]
        #expect(place.addressLines == ["2827 Saint Martin Dr.", "Lancaster, TX 75146", "United States"])
        let maps = place.mapsURL?.absoluteString ?? ""
        #expect(maps == "https://maps.apple.com/?q=2827%20Saint%20Martin%20Dr.,%20Lancaster,%20TX%2075146,%20United%20States")
        // Gatherings that aren't a weekday or a date at a clock time are left out.
        #expect(place.gatherings.count == 5)
        // iOS may put a narrow no-break space before "AM".
        let lines = place.scheduleLines(today: "2026-11-22", locale: Locale(identifier: "en_US"))
            .map { $0.replacingOccurrences(of: "\u{202F}", with: " ") }
        #expect(lines == [
            "Sundays · 9:00 AM, 11:00 AM",
            "Wednesdays · 7:00 PM (Bible study)",
            "Thursday, November 26, 2026 · 6:00 PM (Thanksgiving)",
        ])
        let later = place.scheduleLines(today: "2026-11-27", locale: Locale(identifier: "en_US"))
        #expect(later.count == 2)
    }

    @Test func aOneLineAddressStillShows() {
        let place = ChurchLocation(name: "Old", address: "1 Hill Rd, Austin", times: "Sundays 10 AM")
        #expect(place.addressLines == ["1 Hill Rd, Austin"])
        #expect(place.scheduleLines(today: "2026-11-22") == ["Sundays 10 AM"])
    }

    @Test func olderAnswersHaveNoLocations() throws {
        let json = sermonJSON.replacingOccurrences(of: "\"locations\":", with: "\"unused\":")
        guard case let .sermon(sermon) = try ChurchSermonWire.lookup(from: Data(json.utf8)) else {
            Issue.record("Expected a sermon")
            return
        }
        #expect(sermon.locations.isEmpty)
    }

    @Test func referencesKeepOnlyFreeQuotationCodes() throws {
        let sermon = try decoded()
        let references = sermon.blocks.compactMap { block -> SermonReference? in
            if case let .scripture(_, reference) = block { return reference }
            return nil
        }
        #expect(references.count == 3)
        #expect(references[0].translation == "KJV")
        #expect(references[0].range == StudyRange(start: VerseID(rawValue: 40_011_028), end: VerseID(rawValue: 40_011_030)))
        // NIV words are never published, and the code isn't one readers show.
        #expect(references[1].translation == nil)
        #expect(references[1].quoteWithheld)
        #expect(references[1].range == StudyRange(start: VerseID(rawValue: 45_008_028), end: VerseID(rawValue: 45_008_028)))
        // An unlinked reference doesn't link.
        #expect(references[2].range == nil)
    }

    @Test func passagesForNotesAreVerifiedIDsOnly() throws {
        let sermon = try decoded()
        #expect(sermon.passages.map { $0.id } == ["40011028-40011030", "45008028-45008028"])
    }

    @Test func membersOnlyAndNotFoundSayNothingElse() throws {
        #expect(try ChurchSermonWire.lookup(from: Data(#"{"status":"members_only"}"#.utf8)) == .membersOnly)
        #expect(try ChurchSermonWire.lookup(from: Data(#"{"status":"not_found"}"#.utf8)) == .notFound)
        #expect(try ChurchSermonWire.lookup(from: Data(#"{"status":"something_new"}"#.utf8)) == .notFound)
    }

    @Test func aLeadersArchiveKeepsOnlyWhatReadersGet() throws {
        let json = """
        [{"id":"1","slug":"aaaaaaaaa1","title":"Live","speaker":"","series":null,"preached_on":"2026-11-15","audience":"link","status":"published","live_audience":"link","hidden":false,"has_cover":false,"published_at":null,"draft_version":3,"unpublished_changes":false},
         {"id":"2","slug":"aaaaaaaaa2","title":"Draft","speaker":"","series":null,"preached_on":null,"audience":"link","status":"draft","live_audience":null,"hidden":false,"has_cover":false,"published_at":null,"draft_version":0,"unpublished_changes":false},
         {"id":"3","slug":"aaaaaaaaa3","title":"Hidden","speaker":"","series":null,"preached_on":null,"audience":"link","status":"published","live_audience":"link","hidden":true,"has_cover":false,"published_at":null,"draft_version":1,"unpublished_changes":false},
         {"id":"4","slug":"aaaaaaaaa4","title":"Members","speaker":"","series":"","preached_on":null,"audience":"link","status":"published","live_audience":"members","hidden":false,"has_cover":false,"published_at":null,"draft_version":1,"unpublished_changes":true}]
        """
        let sermons = try ChurchSermonWire.archive(from: Data(json.utf8))
        #expect(sermons.map { $0.slug } == ["aaaaaaaaa1", "aaaaaaaaa4"])
        // What readers get is the live audience, not the draft's.
        #expect(sermons.last?.audience == .members)
        #expect(sermons.last?.series == nil)
    }

    @Test func aMembersArchiveIsSummaries() throws {
        let json = #"[{"slug":"bbbbbbbbb1","title":"One","speaker":"Ana","series":"S","preached_on":"2026-11-15","audience":"members","published_at":"2026-11-15T15:00:00+00:00"},{"slug":"not a slug"}]"#
        let sermons = try ChurchSermonWire.archive(from: Data(json.utf8))
        #expect(sermons.map { $0.slug } == ["bbbbbbbbb1"])
        #expect(sermons.first?.audience == .members)
    }

    @Test func churchSearchResults() throws {
        let json = #"[{"group_id":"00000000-0000-0000-0000-00000000c1c1","name":"Riverside","sermons":[{"slug":"ccccccccc1","title":"Living Water","speaker":"Sam","series":null,"preached_on":null,"audience":"link","published_at":null}]}]"#
        let churches = try ChurchSermonWire.churches(from: Data(json.utf8))
        #expect(churches.count == 1)
        #expect(churches.first?.name == "Riverside")
        #expect(churches.first?.sermons.map { $0.slug } == ["ccccccccc1"])
    }
}

/// The same cases as web/src/lib/outline.test.ts.
struct SermonOutlineTests {
    private let blocks: [SermonBlock] = [
        .paragraph(id: "a", text: "Welcome."),
        .heading(id: "h1", text: "Rest", level: 2),
        .scripture(id: "s", reference: SermonReference(raw: "Sl 23", start: VerseID(rawValue: 19_023_001), end: VerseID(rawValue: 19_023_006), status: .verified, label: "NVI", translation: nil, quoteWithheld: true)),
        .list(id: "l", items: ["Lie down", "Be led"], ordered: true),
        .heading(id: "h2", text: "Goodness", level: 2),
        .quote(id: "q", text: "Surely"),
    ]

    @Test func sectionsSplitAtHeadings() {
        let sections = SermonOutline.sections(blocks)
        #expect(sections.map { $0.id } == ["start", "h1", "h2"])
        #expect(sections.map { $0.title } == [nil, "Rest", "Goodness"])
        #expect(sections.map { $0.blocks.count } == [1, 3, 2])
    }

    @Test func copyGivesTheChurchsWordsAndNeverVerseText() {
        let sections = SermonOutline.sections(blocks)
        #expect(SermonOutline.copyText(sections[1].blocks) == "Rest\n\nSl 23 (NVI)\n\n1. Lie down\n2. Be led")
        #expect(SermonOutline.copyText([blocks[5]]) == "\u{201C}Surely\u{201D}")
        #expect(SermonOutline.copyText([.list(id: "u", items: ["x"], ordered: false)]) == "\u{2022} x")
    }
}

struct ChurchSermonLinkTests {
    @Test func readsTheSermonLinks() {
        #expect(ChurchSermonLink.slug(in: URL(string: "https://versely.7twenty8studio.com/s/abcde12345")!) == "abcde12345")
        #expect(ChurchSermonLink.slug(in: URL(string: "https://VERSELY.7twenty8studio.com/s/abcde12345?utm=qr")!) == "abcde12345")
        #expect(ChurchSermonLink.slug(in: URL(string: "versely://sermon/abcde12345")!) == "abcde12345")
        #expect(ChurchSermonLink.url(slug: "abcde12345").absoluteString == "https://versely.7twenty8studio.com/s/abcde12345")
    }

    @Test func leadersOpenTheirChurchInStudio() {
        let church = UUID(uuidString: "BEBA5C2F-8236-4897-90DC-052E6914069F")!
        let studio = ChurchSermonLink.studio(church: church).absoluteString
        #expect(studio == "https://versely.7twenty8studio.com/studio?church=beba5c2f-8236-4897-90dc-052e6914069f")
        #expect(ChurchSermonLink.slug(in: ChurchSermonLink.studio(church: church)) == nil)
    }

    @Test func ignoresEverythingElse() {
        #expect(ChurchSermonLink.slug(in: URL(string: "https://versely.7twenty8studio.com/studio")!) == nil)
        #expect(ChurchSermonLink.slug(in: URL(string: "https://example.com/s/abcde12345")!) == nil)
        #expect(ChurchSermonLink.slug(in: URL(string: "http://versely.7twenty8studio.com/s/abcde12345")!) == nil)
        #expect(ChurchSermonLink.slug(in: URL(string: "https://versely.7twenty8studio.com/s/ABCDE12345")!) == nil)
        #expect(ChurchSermonLink.slug(in: URL(string: "https://versely.7twenty8studio.com/s/abc")!) == nil)
        #expect(ChurchSermonLink.slug(in: URL(string: "versely://sermons")!) == nil)
        #expect(ChurchSermonLink.slug(in: URL(string: "versely://read/43003016")!) == nil)
    }

    @MainActor
    @Test func theRouterOpensASermonFromAnyTab() {
        let defaults = UserDefaults(suiteName: "ChurchSermonLinkTests-\(UUID())")!
        let router = AppRouter(reader: ReaderViewModel(library: BibleLibrary(defaults: defaults), progress: ReadingProgress(defaults: defaults)))
        router.tab = .explore
        router.handle(URL(string: "https://versely.7twenty8studio.com/s/abcde12345")!)
        #expect(router.sermonLink?.slug == "abcde12345")
        #expect(router.tab == .explore)
        router.sermonLink = nil
        router.handle(GenesisLink.sermon("fghij67890"))
        #expect(router.sermonLink?.slug == "fghij67890")
        // Opening a passage in the reader closes the sermon sheet.
        router.read(VerseID(rawValue: 43_003_016))
        #expect(router.sermonLink == nil)
        #expect(router.tab == .read)
    }
}

struct ChurchSermonVersificationTests {
    @Test func kjvNumberingLandsOnTheReinaValerasVerse() throws {
        // RV1909 Acts 19:40 holds KJV 19:40–41.
        let map = try #require(OriginalVersification.map(for: "RV1909"))
        let acts = map.ownRange(forKJV: VerseID(book: 44, chapter: 19, verse: 41), through: VerseID(book: 44, chapter: 19, verse: 41))
        #expect(acts.start == VerseID(book: 44, chapter: 19, verse: 40))
        #expect(acts.end == VerseID(book: 44, chapter: 19, verse: 40))
    }

    @Test func theWEBsDoxologyIsFoundInRomans14() {
        let map = OriginalVersification.parallelMap(for: .web)
        let doxology = map.ownRange(forKJV: VerseID(book: 45, chapter: 16, verse: 25), through: VerseID(book: 45, chapter: 16, verse: 27))
        #expect(doxology.start == VerseID(book: 45, chapter: 14, verse: 24))
        #expect(doxology.end == VerseID(book: 45, chapter: 14, verse: 26))
    }

    @Test func otherVersesKeepTheirNumbers() {
        let map = OriginalVersification.parallelMap(for: .kjv)
        let john = map.ownRange(forKJV: VerseID(rawValue: 43_003_016), through: VerseID(rawValue: 43_003_017))
        #expect(john.start == VerseID(rawValue: 43_003_016))
        #expect(john.end == VerseID(rawValue: 43_003_017))
    }
}

/// The in-memory server mirrors the database's rules.
struct InMemoryChurchSermonTests {
    private typealias Backend = InMemoryChurchSermonBackend

    /// Someone who joined the sample church's group with its invite code.
    private func joinedCommunity() async throws -> InMemoryCommunityBackend {
        let community = InMemoryCommunityBackend()
        try await community.setDisplayName("Jo")
        _ = try await community.joinGroup(code: InMemoryCommunityBackend.sampleInviteCode)
        return community
    }

    @Test func aLinkSermonIsForAnyoneAndAMembersSermonOnlyForMembers() async throws {
        let guest = Backend(community: SignedOutCommunityBackend())
        guard case let .sermon(sermon) = try await guest.sermon(slug: Backend.linkSlug) else {
            Issue.record("A link sermon opens for a guest")
            return
        }
        #expect(!sermon.isMember)
        // The members-only sermon in the series isn't offered as Next to a guest.
        #expect(sermon.next == nil)
        #expect(try await guest.sermon(slug: Backend.membersSlug) == .membersOnly)
        #expect(try await guest.sermon(slug: "zzzzzzzzzz") == .notFound)

        let member = Backend(community: try await joinedCommunity())
        guard case let .sermon(first) = try await member.sermon(slug: Backend.linkSlug) else {
            Issue.record("A member reads it")
            return
        }
        #expect(first.isMember)
        #expect(first.next?.slug == Backend.membersSlug)
        guard case let .sermon(second) = try await member.sermon(slug: Backend.membersSlug) else {
            Issue.record("A member reads the members-only sermon")
            return
        }
        #expect(second.previous?.slug == Backend.linkSlug)
        // Another church's members-only sermon stays closed.
        #expect(try await member.sermon(slug: Backend.otherMembersSlug) == .membersOnly)
    }

    @Test func theArchiveIsForMembersOnly() async throws {
        let member = Backend(community: try await joinedCommunity())
        let archive = try await member.archive(group: Backend.sampleChurchID)
        #expect(archive.map { $0.slug } == [Backend.membersSlug, Backend.linkSlug])
        await #expect(throws: CommunityError.self) {
            try await member.archive(group: Backend.otherChurchID)
        }
    }

    @Test func searchFindsListedChurchesWithTheirLinkSermons() async throws {
        let backend = Backend(community: SignedOutCommunityBackend())
        let found = try await backend.searchChurches("river")
        #expect(found.map { $0.name } == ["Riverside Church"])
        #expect(found.first?.sermons.map { $0.slug } == [Backend.otherLinkSlug])
        #expect(try await backend.searchChurches("r").isEmpty)
    }

    @Test func unpublishingOrTheSwitchClosesItAtOnce() async throws {
        let backend = Backend(community: try await joinedCommunity())
        await backend.unpublish(Backend.linkSlug)
        #expect(try await backend.sermon(slug: Backend.linkSlug) == .notFound)
        await backend.setSermonsOn(false)
        #expect(try await backend.sermon(slug: Backend.membersSlug) == .notFound)
        #expect(try await backend.searchChurches("grace").isEmpty)
    }

    @Test func threeReportsHideASermonAndGuestsCantReport() async throws {
        let community = InMemoryCommunityBackend()
        let backend = Backend(community: community)
        let guest = Backend(community: SignedOutCommunityBackend())
        await #expect(throws: CommunityError.self) {
            try await guest.report(slug: Backend.linkSlug, reason: "Spam or advertising")
        }
        try await backend.report(slug: Backend.linkSlug, reason: "Spam or advertising")
        // The same person twice counts once.
        try await backend.report(slug: Backend.linkSlug, reason: "Spam or advertising")
        await community.actAs(UUID(), name: "Two")
        try await backend.report(slug: Backend.linkSlug, reason: "Something else")
        let open = try await backend.sermon(slug: Backend.linkSlug)
        #expect(open != .notFound)
        await community.actAs(UUID(), name: "Three")
        try await backend.report(slug: Backend.linkSlug, reason: "Something else")
        #expect(try await backend.sermon(slug: Backend.linkSlug) == .notFound)
    }

    @Test func countsAreOnlyForLiveSermons() async {
        let backend = Backend(community: SignedOutCommunityBackend())
        await backend.count(.open, slug: Backend.linkSlug)
        await backend.count(.passage, slug: Backend.linkSlug)
        await backend.unpublish(Backend.linkSlug)
        await backend.count(.open, slug: Backend.linkSlug)
        #expect(await backend.count(of: .open, slug: Backend.linkSlug) == 1)
        #expect(await backend.count(of: .passage, slug: Backend.linkSlug) == 1)
    }

    @Test func coversFollowAccess() async throws {
        let backend = Backend(community: SignedOutCommunityBackend())
        guard case let .sermon(sermon) = try await backend.sermon(slug: Backend.linkSlug) else {
            Issue.record("A link sermon opens")
            return
        }
        let path = try #require(sermon.cover?.path)
        let data = try await backend.cover(path: path)
        #expect(data?.isEmpty == false)
        await backend.unpublish(Backend.linkSlug)
        #expect(try await backend.cover(path: path) == nil)
    }
}

@MainActor
struct ChurchSermonNotesTests {
    private func sample() throws -> PublishedSermon {
        PublishedSermon(
            id: UUID(), slug: "abcde12345", groupID: UUID(), church: "Grace Fellowship", title: "Rest for the Weary", speaker: "Ana",
            series: "Come to Me", preachedOn: "2026-11-15", location: "", language: "en", cover: nil, audience: .link,
            blocks: [
                .paragraph(id: "a", text: "Welcome."),
                .scripture(id: "s", reference: SermonReference(raw: "Mt 11:28", start: VerseID(rawValue: 40_011_028), end: nil, status: .verified, label: nil, translation: nil, quoteWithheld: false)),
                .scripture(id: "t", reference: SermonReference(raw: "Matthew 11:28", start: VerseID(rawValue: 40_011_028), end: nil, status: .verified, label: nil, translation: nil, quoteWithheld: false)),
            ],
            previous: nil, next: nil, isMember: false
        )
    }

    @Test func notesStartOnceWithTheDetailsAndPassagesButNotTheOutline() throws {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let sermon = try sample()
        let notes = ChurchSermonNotes.notes(for: sermon, in: context)
        #expect(notes.sourceSermonID == sermon.id)
        #expect(notes.title == "Rest for the Weary")
        #expect(notes.preacher == "Ana")
        #expect(notes.church == "Grace Fellowship")
        #expect(notes.series == "Come to Me")
        #expect(notes.body.isEmpty)
        #expect(notes.passages.map { $0.id } == ["40011028-40011028"])
        // Opening them again finds the same notes.
        notes.body = "My own thoughts"
        let again = ChurchSermonNotes.notes(for: sermon, in: context)
        #expect(again.id == notes.id)
        #expect(again.body == "My own thoughts")
    }

    @Test func theLinkGoesUpOnlyWhenSet() throws {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = StudyStore(context: container.mainContext)
        let plain = store.createSermon(church: "Grace Chapel")
        let user = UUID()
        let plainData = try SupabaseCoding.encoder().encode(RemoteSermon(plain, userID: user))
        let plainJSON = try JSONSerialization.jsonObject(with: plainData) as? [String: Any]
        let plainObject = try #require(plainJSON)
        // Notes of one's own never name the column (so pushes work before the migration).
        #expect(!plainObject.keys.contains("source_sermon_id"))

        let published = try sample()
        let linked = ChurchSermonNotes.notes(for: published, in: container.mainContext)
        let linkedData = try SupabaseCoding.encoder().encode(RemoteSermon(linked, userID: user))
        let linkedJSON = try JSONSerialization.jsonObject(with: linkedData) as? [String: Any]
        let linkedObject = try #require(linkedJSON)
        #expect(linkedObject["source_sermon_id"] as? String == linked.sourceSermonID?.uuidString)
        let decoded = try SupabaseCoding.decoder().decode(RemoteSermon.self, from: linkedData)
        #expect(decoded.sourceSermonId == linked.sourceSermonID)
    }
}

@MainActor
struct ChurchSermonFeatureTests {
    @Test func needsItsOwnSwitchAndGroups() {
        let features = FeaturePreferences(defaults: UserDefaults(suiteName: "ChurchSermonFeatureTests-\(UUID())")!, existingUser: true)
        #expect(features.isOn(.churchSermons))
        #expect(!features.shows(.churchSermons, flags: FeatureFlagService(client: nil, override: [.groups: true])))
        #expect(!features.shows(.churchSermons, flags: FeatureFlagService(client: nil, override: [.churchSermons: true])))
        #expect(features.shows(.churchSermons, flags: FeatureFlagService(client: nil, override: [.churchSermons: true, .groups: true])))
    }

    @Test func hiddenChurchesAreRemembered() {
        let defaults = UserDefaults(suiteName: "HiddenChurches-\(UUID())")!
        let church = UUID()
        HiddenChurches(defaults: defaults).set(church, hidden: true)
        #expect(HiddenChurches(defaults: defaults).isHidden(church))
        HiddenChurches(defaults: defaults).set(church, hidden: false)
        #expect(!HiddenChurches(defaults: defaults).isHidden(church))
    }

    @Test func theAnnouncementWaitsForTheSwitch() {
        #expect(WhatsNewCatalog.churchSermons.flag == .churchSermons)
        #expect(WhatsNewCatalog.all.last?.id == "church-sermons")
    }
}
