import Foundation
import Testing
@testable import Genesis

/// Group owners and moderators against the in-memory backend, which follows
/// the server's rules (supabase/migrations/20261011000000_group_moderation_challenges.sql).
@Suite("Group moderation")
@MainActor
struct GroupModerationTests {
    private let owner = UUID()
    private let moderator = UUID()
    private let otherModerator = UUID()
    private let member = UUID()

    /// True if the action was refused (threw).
    private func refused(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            return false
        } catch {
            return true
        }
    }

    /// The message an action failed with, if it failed.
    private func failure(_ action: () async throws -> Void) async -> String? {
        do {
            try await action()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private struct Fixture {
        let backend: InMemoryCommunityBackend
        let group: UUID
        let code: String
    }

    /// Olive owns a group; Mo and Max moderate it; Meg is a member.
    private func makeGroup() async throws -> Fixture {
        let backend = InMemoryCommunityBackend()
        await backend.actAs(owner, name: "Olive")
        var draft = GroupDraft()
        draft.name = "Home Group"
        let group = try await backend.createGroup(draft)
        let groups = try await backend.myGroups()
        let found = groups.first { $0.id == group }
        let code = try #require(found?.inviteCode)
        let people: [(UUID, String)] = [(moderator, "Mo"), (otherModerator, "Max"), (member, "Meg")]
        for (user, name) in people {
            await backend.actAs(user, name: name)
            _ = try await backend.requestToJoin(code: code)
        }
        await backend.actAs(owner, name: "Olive")
        try await backend.setRole(.leader, for: moderator, in: group)
        try await backend.setRole(.leader, for: otherModerator, in: group)
        return Fixture(backend: backend, group: group, code: code)
    }

    private func memberIDs(_ fixture: Fixture) async throws -> Set<UUID> {
        let members = try await fixture.backend.members(of: fixture.group)
        return Set(members.map(\.userID))
    }

    private func myGroup(_ fixture: Fixture) async throws -> GroupSummary? {
        let groups = try await fixture.backend.myGroups()
        return groups.first { $0.id == fixture.group }
    }

    // MARK: Permissions

    @Test func permissionsFollowTheServer() {
        let me = UUID()
        let someoneElse = UUID()
        let group = UUID()
        let plainMember = GroupMember(groupID: group, userID: someoneElse, role: .member, displayName: "A", joinedAt: .now)
        let aModerator = GroupMember(groupID: group, userID: UUID(), role: .leader, displayName: "B", joinedAt: .now)
        let theOwner = GroupMember(groupID: group, userID: me, role: .leader, displayName: "C", joinedAt: .now)

        let asOwner = GroupPermissions(me: me, ownerID: me, myRole: .leader)
        #expect(asOwner.isOwner)
        #expect(asOwner.canModerate(plainMember))
        #expect(asOwner.canModerate(aModerator), "The owner acts on moderators")
        #expect(!asOwner.canModerate(theOwner), "Nobody acts on themselves")
        #expect(asOwner.canChooseRole(of: aModerator))
        #expect(asOwner.standing(of: theOwner) == .owner)
        #expect(asOwner.standing(of: aModerator) == .moderator)
        #expect(asOwner.standing(of: plainMember) == .member)

        let ownerMember = GroupMember(groupID: group, userID: UUID(), role: .leader, displayName: "D", joinedAt: .now)
        let asModerator = GroupPermissions(me: me, ownerID: ownerMember.userID, myRole: .leader)
        #expect(!asModerator.isOwner)
        #expect(asModerator.canModerate(plainMember))
        #expect(!asModerator.canModerate(aModerator), "Moderators don't act on moderators")
        #expect(!asModerator.canModerate(ownerMember), "Nobody acts on the owner")
        #expect(!asModerator.canChooseRole(of: plainMember), "Only the owner chooses moderators")
        #expect(!asModerator.canMakeOwner(plainMember))

        let asMember = GroupPermissions(me: me, ownerID: ownerMember.userID, myRole: .member)
        #expect(!asMember.canModerate(plainMember))
    }

    @Test func moderationErrorsReadNicely() {
        let banned = CommunityError.from(SupabaseError.http(status: 400, message: "banned")).localizedDescription
        #expect(banned == String(localized: "You can't join this group."))
        let ownerOnly = CommunityError.from(SupabaseError.http(status: 400, message: "owner_only")).localizedDescription
        #expect(ownerOnly == String(localized: "Only the group's owner can do that."))
    }

    @Test func moderatorsActOnMembersButNotOnModeratorsOrTheOwner() async throws {
        let fixture = try await makeGroup()
        let backend = fixture.backend
        let group = fixture.group
        let otherModerator = self.otherModerator
        let owner = self.owner
        let member = self.member

        await backend.actAs(moderator, name: "Mo")
        let removeModerator = await refused { try await backend.removeMember(otherModerator, from: group) }
        #expect(removeModerator)
        let banOwner = await refused { try await backend.banMember(owner, from: group, reason: "") }
        #expect(banOwner)
        let muteOwner = await refused { try await backend.muteMember(owner, in: group, hours: 1) }
        #expect(muteOwner)
        let chooseRole = await refused { try await backend.setRole(.leader, for: member, in: group) }
        #expect(chooseRole, "Only the owner chooses moderators")
        let deleteGroup = await refused { try await backend.deleteGroup(group) }
        #expect(deleteGroup, "Only the owner closes the group")
        let muteMember = await refused { try await backend.muteMember(member, in: group, hours: 1) }
        #expect(!muteMember)
        let members = try await backend.members(of: group)
        let meg = members.first { $0.userID == member }
        #expect(meg?.isMuted() == true)

        await backend.actAs(owner, name: "Olive")
        let removeAsOwner = await refused { try await backend.removeMember(otherModerator, from: group) }
        #expect(!removeAsOwner, "The owner acts on moderators")
        let ids = try await memberIDs(fixture)
        #expect(!ids.contains(otherModerator))
        let removeSelf = await refused { try await backend.removeMember(owner, from: group) }
        #expect(removeSelf, "Nobody removes themselves; they leave")
    }

    @Test func aBanKeepsSomeoneOutUntilUnbanned() async throws {
        let fixture = try await makeGroup()
        let backend = fixture.backend
        let group = fixture.group
        let code = fixture.code
        let member = self.member

        await backend.actAs(moderator, name: "Mo")
        try await backend.banMember(member, from: group, reason: "Spam")
        let bans = try await backend.bans(in: group)
        let bannedIDs = bans.map(\.userID)
        #expect(bannedIDs == [member])
        #expect(bans.first?.reason == "Spam")
        let ids = try await memberIDs(fixture)
        #expect(!ids.contains(member))

        await backend.actAs(member, name: "Meg")
        let message = await failure { _ = try await backend.requestToJoin(code: code) }
        #expect(message == String(localized: "You can't join this group."))
        let theirView = try await backend.bans(in: group)
        #expect(theirView.isEmpty, "Only moderators see the banned list")

        await backend.actAs(moderator, name: "Mo")
        try await backend.unbanMember(member, from: group)
        await backend.actAs(member, name: "Meg")
        let outcome = try await backend.requestToJoin(code: code)
        #expect(outcome.status == .joined)
    }

    @Test func groupsThatApproveMembersTakeRequests() async throws {
        let fixture = try await makeGroup()
        let backend = fixture.backend
        let group = fixture.group
        let code = fixture.code
        let newcomer = UUID()
        let second = UUID()
        let third = UUID()

        await backend.actAs(owner, name: "Olive")
        try await backend.setRequiresApproval(true, for: group)
        let summary = try await myGroup(fixture)
        #expect(summary?.requiresApproval == true)

        await backend.actAs(newcomer, name: "Nia")
        let asked = try await backend.requestToJoin(code: code)
        #expect(asked.status == .requested)
        #expect(asked.name == "Home Group")
        let mine = try await backend.myJoinRequests()
        let requestedGroups = mine.map(\.groupID)
        #expect(requestedGroups == [group])
        let idsBefore = try await memberIDs(fixture)
        #expect(!idsBefore.contains(newcomer), "Not in until a moderator says so")

        await backend.actAs(member, name: "Meg")
        let memberView = try await backend.joinRequests(in: group)
        #expect(memberView.isEmpty, "Members don't see others' requests")
        let memberAnswer = await refused { try await backend.answerJoinRequest(from: newcomer, in: group, accept: true) }
        #expect(memberAnswer)

        await backend.actAs(moderator, name: "Mo")
        let waiting = try await backend.joinRequests(in: group)
        let waitingIDs = waiting.map(\.userID)
        #expect(waitingIDs == [newcomer])
        try await backend.answerJoinRequest(from: newcomer, in: group, accept: true)
        let idsAfter = try await memberIDs(fixture)
        #expect(idsAfter.contains(newcomer))

        await backend.actAs(second, name: "Sol")
        _ = try await backend.requestToJoin(code: code)
        await backend.actAs(moderator, name: "Mo")
        try await backend.answerJoinRequest(from: second, in: group, accept: false)
        let declined = try await memberIDs(fixture)
        #expect(!declined.contains(second))
        let afterDecline = try await backend.joinRequests(in: group)
        #expect(afterDecline.isEmpty)

        // A request can be withdrawn, or turned down with a ban.
        await backend.actAs(third, name: "Tam")
        _ = try await backend.requestToJoin(code: code)
        try await backend.withdrawJoinRequest(to: group)
        let withdrawn = try await backend.myJoinRequests()
        #expect(withdrawn.isEmpty)
        _ = try await backend.requestToJoin(code: code)
        await backend.actAs(moderator, name: "Mo")
        try await backend.banMember(third, from: group, reason: "")
        let banned = try await backend.bans(in: group)
        let bannedIDs = banned.map(\.userID)
        #expect(bannedIDs == [third])
        let afterBan = try await backend.joinRequests(in: group)
        #expect(afterBan.isEmpty)
    }

    @Test func turningApprovalOffLetsEveryoneWaitingIn() async throws {
        let fixture = try await makeGroup()
        let backend = fixture.backend
        let group = fixture.group
        let first = UUID()
        let second = UUID()

        await backend.actAs(owner, name: "Olive")
        try await backend.setRequiresApproval(true, for: group)
        await backend.actAs(first, name: "Ann")
        _ = try await backend.requestToJoin(code: fixture.code)
        await backend.actAs(second, name: "Ben")
        _ = try await backend.requestToJoin(code: fixture.code)

        await backend.actAs(moderator, name: "Mo")
        try await backend.setRequiresApproval(false, for: group)
        let ids = try await memberIDs(fixture)
        #expect(ids.contains(first))
        #expect(ids.contains(second))
        let waiting = try await backend.joinRequests(in: group)
        #expect(waiting.isEmpty)
    }

    @Test func askingAgainIsFineAtTheRequestLimit() async throws {
        let backend = InMemoryCommunityBackend()
        await backend.actAs(owner, name: "Olive")
        var codes: [String] = []
        for index in 1...21 {
            var draft = GroupDraft()
            draft.name = "Group \(index)"
            let group = try await backend.createGroup(draft)
            try await backend.setRequiresApproval(true, for: group)
            let groups = try await backend.myGroups()
            let found = groups.first { $0.id == group }
            let code = try #require(found?.inviteCode)
            codes.append(code)
        }
        await backend.actAs(member, name: "Meg")
        for code in codes.prefix(20) {
            _ = try await backend.requestToJoin(code: code)
        }
        let again = try await backend.requestToJoin(code: codes[0])
        #expect(again.status == .requested, "An existing request comes back, whatever the limit")
        let lastCode = codes[20]
        let tooMany = await refused { _ = try await backend.requestToJoin(code: lastCode) }
        #expect(tooMany)
        let mine = try await backend.myJoinRequests()
        #expect(mine.count == 20)
        let firstName = mine.last?.groupName
        #expect(firstName == "Group 1", "Requests carry the group's name")
    }

    @Test func theStoreShowsRequestsWaiting() async throws {
        let fixture = try await makeGroup()
        await fixture.backend.actAs(owner, name: "Olive")
        try await fixture.backend.setRequiresApproval(true, for: fixture.group)
        await fixture.backend.actAs(UUID(), name: "Nia")

        let store = CommunityStore(backend: fixture.backend)
        await store.refresh()
        let outcome = await store.requestToJoin(code: fixture.code)
        #expect(outcome?.status == .requested)
        let joinedID = await store.joinGroup(code: fixture.code)
        #expect(joinedID == nil, "Still waiting")
        #expect(store.groups.isEmpty)
        let request = try #require(store.joinRequests.first)
        #expect(store.requestedGroupName(request) == "Home Group")
        await store.withdrawJoinRequest(request)
        #expect(store.joinRequests.isEmpty)
    }

    @Test func mutedMembersCantPost() async throws {
        let fixture = try await makeGroup()
        let backend = fixture.backend
        let group = fixture.group
        let member = self.member

        await backend.actAs(moderator, name: "Mo")
        try await backend.muteMember(member, in: group, hours: 24)

        await backend.actAs(member, name: "Meg")
        let store = CommunityStore(backend: backend)
        await store.refresh()
        let detail = GroupDetailModel(groupID: group, store: store)
        await detail.refresh()
        let until = try #require(detail.myMutedUntil)
        let aDayAway = Date.now.addingTimeInterval(23 * 3_600)
        #expect(until > aDayAway)
        let posted = await detail.addPost("Hello", day: nil)
        #expect(!posted)
        #expect(detail.errorMessage == GroupDetailModel.mutedMessage(until: until))
        let prayed = await detail.addPrayer("Please pray")
        #expect(!prayed)
        let direct = await refused { try await backend.addPost("Hello", day: nil, to: group) }
        #expect(direct, "The backend refuses too")

        await backend.actAs(moderator, name: "Mo")
        try await backend.muteMember(member, in: group, hours: 0)
        await backend.actAs(member, name: "Meg")
        await detail.refresh()
        #expect(detail.myMutedUntil == nil)
        let postedAgain = await detail.addPost("Hello again", day: nil)
        #expect(postedAgain)
    }

    @Test func ownershipCanBeHandedOn() async throws {
        let fixture = try await makeGroup()
        let backend = fixture.backend
        let group = fixture.group
        let owner = self.owner
        let member = self.member

        await backend.actAs(moderator, name: "Mo")
        let moderatorTransfer = await refused { try await backend.transferOwnership(of: group, to: member) }
        #expect(moderatorTransfer, "Only the owner hands the group on")

        await backend.actAs(owner, name: "Olive")
        try await backend.transferOwnership(of: group, to: member)
        let oldOwnerView = try await myGroup(fixture)
        #expect(oldOwnerView?.isOwner == false)
        #expect(oldOwnerView?.role == .leader, "The old owner stays a moderator")
        let deleteGroup = await refused { try await backend.deleteGroup(group) }
        #expect(deleteGroup)

        await backend.actAs(member, name: "Meg")
        let newOwnerView = try await myGroup(fixture)
        #expect(newOwnerView?.isOwner == true)
        #expect(newOwnerView?.standing == .owner)
        let demote = await refused { try await backend.setRole(.member, for: owner, in: group) }
        #expect(!demote, "The new owner chooses moderators")
    }

    @Test func whenTheOwnerLeavesTheLongestStandingModeratorTakesOver() async throws {
        let fixture = try await makeGroup()
        let backend = fixture.backend

        await backend.actAs(owner, name: "Olive")
        try await backend.leaveGroup(fixture.group)
        await backend.actAs(moderator, name: "Mo")
        let view = try await myGroup(fixture)
        #expect(view?.isOwner == true, "Mo became a moderator before Max")
    }

    @Test func withoutModeratorsTheLongestStandingMemberTakesOver() async throws {
        let backend = InMemoryCommunityBackend()
        let first = UUID()
        let second = UUID()
        await backend.actAs(owner, name: "Olive")
        var draft = GroupDraft()
        draft.name = "Small Group"
        let group = try await backend.createGroup(draft)
        let groups = try await backend.myGroups()
        let found = groups.first { $0.id == group }
        let code = try #require(found?.inviteCode)
        await backend.actAs(first, name: "Ann")
        _ = try await backend.requestToJoin(code: code)
        await backend.actAs(second, name: "Ben")
        _ = try await backend.requestToJoin(code: code)

        await backend.actAs(owner, name: "Olive")
        try await backend.leaveGroup(group)
        await backend.actAs(first, name: "Ann")
        let annGroups = try await backend.myGroups()
        let annView = annGroups.first { $0.id == group }
        #expect(annView?.isOwner == true)
        #expect(annView?.role == .leader)

        // The last person out closes the group.
        try await backend.leaveGroup(group)
        await backend.actAs(second, name: "Ben")
        try await backend.leaveGroup(group)
        let left = try await backend.members(of: group)
        #expect(left.isEmpty)
    }

    @Test func reportsHideAfterThreeAndModeratorsReviewThem() async throws {
        let fixture = try await makeGroup()
        let backend = fixture.backend
        let group = fixture.group
        let bystander = UUID()

        await backend.actAs(bystander, name: "Ned")
        _ = try await backend.requestToJoin(code: fixture.code)
        await backend.actAs(member, name: "Meg")
        try await backend.addPost("Buy my stuff", day: nil, to: group)
        let posts = try await backend.posts(in: group)
        let post = try #require(posts.first)

        for reporter in [owner, moderator, otherModerator] {
            await backend.actAs(reporter, name: "Reporter")
            try await backend.report(.groupPost, id: post.id, reason: "Spam or advertising")
        }

        await backend.actAs(bystander, name: "Ned")
        let hiddenFromOthers = try await backend.posts(in: group)
        #expect(hiddenFromOthers.isEmpty, "Hidden from everyone else")
        let bystanderReview = await refused { _ = try await backend.reports(in: group) }
        #expect(bystanderReview, "Only moderators see reports")

        await backend.actAs(member, name: "Meg")
        let authorView = try await backend.posts(in: group)
        #expect(authorView.first?.hiddenAt != nil, "Its author still sees it, marked hidden")

        await backend.actAs(moderator, name: "Mo")
        let reports = try await backend.reports(in: group)
        let report = try #require(reports.first)
        #expect(report.reportCount == 3)
        #expect(report.hidden)
        #expect(report.authorName == "Meg")
        let hasReason = report.reasons.contains("Spam or advertising")
        #expect(hasReason)
        try await backend.reviewReport(.groupPost, id: post.id, action: .keep)
        let afterKeep = try await backend.reports(in: group)
        #expect(afterKeep.isEmpty)

        await backend.actAs(bystander, name: "Ned")
        let shownAgain = try await backend.posts(in: group)
        #expect(shownAgain.first?.hiddenAt == nil)
        #expect(shownAgain.count == 1, "Kept: shown to everyone again")

        // Kept reports are cleared, so the same person can report it again.
        await backend.actAs(owner, name: "Olive")
        try await backend.report(.groupPost, id: post.id, reason: "Spam or advertising")
        let reportedAgain = try await backend.reports(in: group)
        #expect(reportedAgain.first?.reportCount == 1)
        try await backend.reviewReport(.groupPost, id: post.id, action: .keep)

        // A report a moderator removes takes the prayer down.
        await backend.actAs(member, name: "Meg")
        try await backend.addPrayer("Something unkind", to: group)
        let prayers = try await backend.prayers(in: group)
        let prayer = try #require(prayers.first)
        await backend.actAs(bystander, name: "Ned")
        try await backend.report(.groupPrayer, id: prayer.id, reason: "Abusive or hateful")
        await backend.actAs(otherModerator, name: "Max")
        let openReports = try await backend.reports(in: group)
        #expect(openReports.first?.hidden == false, "One report doesn't hide it")
        try await backend.reviewReport(.groupPrayer, id: prayer.id, action: .remove)
        let remaining = try await backend.prayers(in: group)
        #expect(remaining.isEmpty)
    }

    @Test func theModerationModelCountsWhatsWaiting() async throws {
        let fixture = try await makeGroup()
        let backend = fixture.backend
        await backend.actAs(owner, name: "Olive")
        try await backend.setRequiresApproval(true, for: fixture.group)
        await backend.actAs(UUID(), name: "Nia")
        _ = try await backend.requestToJoin(code: fixture.code)

        await backend.actAs(owner, name: "Olive")
        let store = CommunityStore(backend: backend)
        await store.refresh()
        let detail = GroupDetailModel(groupID: fixture.group, store: store)
        await detail.refresh()
        #expect(detail.permissions.isOwner)
        #expect(detail.moderation.pendingCount == 1)
        let request = try #require(detail.moderation.requests.first)
        await detail.moderation.answer(request, accept: true)
        #expect(detail.moderation.pendingCount == 0)
        await detail.refresh()
        #expect(detail.members.count == 5)
    }
}
