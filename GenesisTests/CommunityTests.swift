import Foundation
import Testing
@testable import Genesis

@Suite("Groups and community")
@MainActor
struct CommunityTests {
    private func group(planStart: Date?, planID: String? = ReadingPlan.gospelsID) -> GroupSummary {
        GroupSummary(
            id: UUID(), name: "Test", description: "", inviteCode: "ABCDE12345",
            planID: planID, planTitle: nil, planBooks: nil, planDays: nil,
            planStart: planStart, role: .member, notifications: true
        )
    }

    @Test func planDayCountsFromTheStart() {
        let calendar = Calendar(identifier: .gregorian)
        func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
        }
        let start = day(2026, 10, 1, 9)
        let sameDay = day(2026, 10, 1, 23)
        let third = day(2026, 10, 3, 1)
        let before = day(2026, 9, 30)
        let long = day(2027, 6, 1)
        let plan = group(planStart: start)
        #expect(plan.planDay(on: sameDay, calendar: calendar) == 1)
        #expect(plan.planDay(on: third, calendar: calendar) == 3)
        #expect(plan.planDay(on: before, calendar: calendar) == 0, "Not started yet")
        let dayCount = ReadingPlan.builtIn(id: ReadingPlan.gospelsID)?.dayCount
        #expect(plan.planDay(on: long, calendar: calendar) == dayCount, "Stays on the last day")
        let noPlan = group(planStart: nil, planID: nil).planDay()
        #expect(noPlan == nil, "No plan")
    }

    @Test func inviteCodesAreReadable() {
        #expect(group(planStart: nil).formattedInviteCode == "ABCDE-12345")
    }

    @Test func postReferences() {
        func post(_ start: Int?, _ end: Int?) -> CommunityPost {
            CommunityPost(id: UUID(), authorID: UUID(), isMine: false, kind: .reflection, body: "", startVerse: start, endVerse: end, displayName: "", reactionCount: 0, commentCount: 0, createdAt: .now, hiddenAt: nil)
        }
        #expect(post(43_003_016, 43_003_018).reference?.description == "John 3:16\u{2013}18")
        #expect(post(19_023_000, nil).reference?.description == "Psalms 23", "Verse 0 is the whole chapter")
        #expect(post(nil, nil).reference == nil)
        #expect(post(99_001_001, nil).reference == nil, "Nonsense from the server is ignored")
    }

    @Test func databaseErrorsReadNicely() {
        #expect(CommunityError.from(SupabaseError.http(status: 400, message: "objectionable_content")).localizedDescription.contains("rephrase"))
        #expect(CommunityError.from(SupabaseError.http(status: 409, message: "duplicate key value")) == .duplicate)
        #expect(CommunityError.from(SupabaseError.http(status: 401, message: "JWT expired")) == .signInRequired)
        #expect(CommunityError.from(URLError(.notConnectedToInternet)) == .offline)
    }

    @Test func createJoinAndBlock() async throws {
        let store = CommunityStore(backend: InMemoryCommunityBackend())
        await store.refresh()
        #expect(store.isSignedIn)
        #expect(store.needsDisplayName)
        let tooEarly = await store.joinGroup(code: InMemoryCommunityBackend.sampleInviteCode)
        #expect(tooEarly == nil, "A name comes first")

        let named = await store.setDisplayName("Sam")
        #expect(named)
        let joinedID = await store.joinGroup(code: "grace-12345")
        let joined = try #require(joinedID)
        #expect(store.group(joined)?.role == .member)

        var draft = GroupDraft()
        draft.name = "Home Group"
        draft.plan = ReadingPlan.builtIn(id: ReadingPlan.psalmsID)
        let createdID = await store.createGroup(draft)
        let created = try #require(createdID)
        #expect(store.group(created)?.isLeader == true)
        #expect(store.groups.count == 2)

        // The leader of the joined group posted a welcome; blocking hides it.
        let detail = GroupDetailModel(groupID: joined, store: store)
        await detail.refresh()
        let firstAuthor = detail.visibleAnnouncements.first?.userID
        let leader = try #require(firstAuthor)
        await store.block(leader)
        #expect(detail.visibleAnnouncements.isEmpty)
    }

    @Test func prayingIsCountedOnce() async throws {
        let store = CommunityStore(backend: InMemoryCommunityBackend())
        await store.refresh()
        _ = await store.setDisplayName("Sam")
        let joinedID = await store.joinGroup(code: InMemoryCommunityBackend.sampleInviteCode)
        let id = try #require(joinedID)
        let detail = GroupDetailModel(groupID: id, store: store)
        await detail.refresh()
        let added = await detail.addPrayer("  Healing for Mum  ")
        #expect(added)
        let first = detail.prayers.first
        let prayer = try #require(first)
        #expect(prayer.body == "Healing for Mum")
        await detail.setPrayed(true, for: prayer)
        await detail.setPrayed(true, for: prayer)
        #expect(detail.prayers.first?.prayedCount == 1)
        await detail.setPrayed(false, for: prayer)
        #expect(detail.prayers.first?.prayedCount == 0)
        let refused = await detail.addPrayer("this is shit")
        #expect(!refused, "Blocked words are refused")
    }

    @Test func membersCannotAnnounce() async throws {
        let store = CommunityStore(backend: InMemoryCommunityBackend())
        await store.refresh()
        _ = await store.setDisplayName("Sam")
        let joinedID = await store.joinGroup(code: InMemoryCommunityBackend.sampleInviteCode)
        let id = try #require(joinedID)
        let detail = GroupDetailModel(groupID: id, store: store)
        let posted = await detail.addAnnouncement(title: "Hi", body: "")
        #expect(!posted)
        #expect(detail.errorMessage != nil)
    }
}
