import Foundation
import Testing
@testable import Genesis

/// A church's roles (Owner, Admin, Preacher, Member) against the in-memory
/// backend, which follows set_church_role
/// (supabase/migrations/20261126000000_church_preachers.sql).
@Suite("Church roles")
@MainActor
struct ChurchRolesTests {
    private let owner = UUID()
    private let admin = UUID()
    private let preacher = UUID()
    private let member = UUID()

    private func refused(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            return false
        } catch {
            return true
        }
    }

    /// Olive owns a church; Ada is an admin, Pete a preacher, Meg a member.
    private func makeChurch() async throws -> (InMemoryCommunityBackend, UUID) {
        let backend = InMemoryCommunityBackend()
        await backend.actAs(owner, name: "Olive")
        var draft = GroupDraft()
        draft.name = "Grace Church"
        let group = try await backend.createGroup(draft)
        await backend.makeChurch(group)
        let groups = try await backend.myGroups()
        let code = try #require(groups.first { $0.id == group }?.inviteCode)
        let people: [(UUID, String)] = [(admin, "Ada"), (preacher, "Pete"), (member, "Meg")]
        for (user, name) in people {
            await backend.actAs(user, name: name)
            _ = try await backend.requestToJoin(code: code)
        }
        await backend.actAs(owner, name: "Olive")
        try await backend.setChurchRole(.admin, for: admin, in: group)
        try await backend.setChurchRole(.preacher, for: preacher, in: group)
        return (backend, group)
    }

    private func row(_ user: UUID, _ backend: InMemoryCommunityBackend, _ group: UUID) async throws -> GroupMember? {
        let members = try await backend.members(of: group)
        return members.first { $0.userID == user }
    }

    @Test func theOwnerSetsAdminsAndPreachers() async throws {
        let (backend, group) = try await makeChurch()
        let ada = try #require(try await row(admin, backend, group))
        let pete = try #require(try await row(preacher, backend, group))
        #expect(ada.role == .leader)
        #expect(!ada.isPreacher)
        #expect(pete.role == .member)
        #expect(pete.isPreacher)
        let refusedOwnRole = await refused { try await backend.setChurchRole(.member, for: owner, in: group) }
        #expect(refusedOwnRole, "Nobody changes the owner's role")
    }

    @Test func adminsChoosePreachersOnly() async throws {
        let (backend, group) = try await makeChurch()
        await backend.actAs(admin, name: "Ada")
        try await backend.setChurchRole(.preacher, for: member, in: group)
        let meg = try #require(try await row(member, backend, group))
        #expect(meg.isPreacher)
        try await backend.setChurchRole(.member, for: member, in: group)
        let megAgain = try #require(try await row(member, backend, group))
        #expect(!megAgain.isPreacher)
        let madeAdmin = await refused { try await backend.setChurchRole(.admin, for: member, in: group) }
        #expect(madeAdmin, "Only the owner chooses admins")
    }

    @Test func aPreacherCanOnlyStepDown() async throws {
        let (backend, group) = try await makeChurch()
        await backend.actAs(preacher, name: "Pete")
        let madeOther = await refused { try await backend.setChurchRole(.preacher, for: member, in: group) }
        #expect(madeOther)
        let groups = try await backend.myGroups()
        let mine = try #require(groups.first { $0.id == group })
        #expect(mine.standing == .preacher)
        try await backend.setChurchRole(.member, for: preacher, in: group)
        let pete = try #require(try await row(preacher, backend, group))
        #expect(!pete.isPreacher)
        let again = await refused { try await backend.setChurchRole(.preacher, for: preacher, in: group) }
        #expect(again, "A member can't make themselves a preacher")
    }

    @Test func onlyChurchesHavePreachers() async throws {
        let backend = InMemoryCommunityBackend()
        await backend.actAs(owner, name: "Olive")
        var draft = GroupDraft()
        draft.name = "Home Group"
        let group = try await backend.createGroup(draft)
        let notChurch = await refused { try await backend.setChurchRole(.preacher, for: owner, in: group) }
        #expect(notChurch)
    }

    @Test func permissionsAndNames() {
        let me = UUID()
        let ownerID = UUID()
        let church = UUID()
        let anAdmin = GroupMember(groupID: church, userID: UUID(), role: .leader, displayName: "A", joinedAt: .now)
        let aPreacher = GroupMember(groupID: church, userID: UUID(), role: .member, displayName: "P", joinedAt: .now, preacher: true)
        let aMember = GroupMember(groupID: church, userID: UUID(), role: .member, displayName: "M", joinedAt: .now)
        let theOwner = GroupMember(groupID: church, userID: ownerID, role: .leader, displayName: "O", joinedAt: .now)

        let asAdmin = GroupPermissions(me: me, ownerID: ownerID, myRole: .leader, isChurch: true)
        #expect(asAdmin.canChoosePreacher(of: aMember))
        #expect(asAdmin.canChoosePreacher(of: aPreacher))
        #expect(!asAdmin.canChoosePreacher(of: anAdmin))
        #expect(!asAdmin.canChoosePreacher(of: theOwner))
        #expect(!asAdmin.canChooseRole(of: aMember), "Only the owner chooses admins")
        #expect(asAdmin.standing(of: aPreacher) == .preacher)
        #expect(asAdmin.standing(of: anAdmin) == .moderator)

        let asMember = GroupPermissions(me: me, ownerID: ownerID, myRole: .member, isChurch: true)
        #expect(!asMember.canChoosePreacher(of: aMember))
        let myRow = GroupMember(groupID: church, userID: me, role: .member, displayName: "Me", joinedAt: .now, preacher: true)
        #expect(asMember.canStepDown(myRow))
        #expect(!asMember.canStepDown(aPreacher))

        let notChurch = GroupPermissions(me: me, ownerID: ownerID, myRole: .leader)
        #expect(!notChurch.canChoosePreacher(of: aMember))
        #expect(notChurch.standing(of: aPreacher) == .member)

        #expect(GroupStanding.moderator.title(inChurch: true) == String(localized: "Admin"))
        #expect(GroupStanding.moderator.title(inChurch: false) == String(localized: "Moderator"))
    }
}
