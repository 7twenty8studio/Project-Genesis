import Foundation

/// Who you are in groups and the community: your display name, guidelines,
/// the people you've blocked, and your groups.
@MainActor
@Observable
final class CommunityStore {
    private(set) var userID: UUID?
    private(set) var profile: CommunityProfile?
    private(set) var blocked: Set<UUID> = []
    private(set) var groups: [GroupSummary] = []
    private(set) var hasLoaded = false
    /// True once the profile has actually been read (not just attempted).
    private(set) var profileLoaded = false
    private(set) var isLoading = false
    var errorMessage: String?

    @ObservationIgnored let backend: CommunityBackend

    init(backend: CommunityBackend) {
        self.backend = backend
    }

    var isSignedIn: Bool { userID != nil }
    var needsDisplayName: Bool { isSignedIn && profileLoaded && profile == nil }

    func isMine(_ user: UUID) -> Bool { user == userID }

    /// Reloads everything. Quietly does nothing useful when signed out.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        userID = await backend.currentUserID()
        guard userID != nil else {
            profile = nil
            groups = []
            blocked = []
            profileLoaded = false
            hasLoaded = true
            return
        }
        do {
            async let profile = backend.profile()
            async let blocked = backend.blockedUsers()
            async let groups = backend.myGroups()
            self.profile = try await profile
            profileLoaded = true
            self.blocked = try await blocked
            self.groups = try await groups
            errorMessage = nil
        } catch {
            errorMessage = CommunityError.from(error).localizedDescription
        }
        hasLoaded = true
    }

    /// Runs an action, showing its error; returns false if it failed.
    @discardableResult
    func perform(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            errorMessage = nil
            return true
        } catch {
            errorMessage = CommunityError.from(error).localizedDescription
            return false
        }
    }

    // MARK: Profile

    func setDisplayName(_ name: String) async -> Bool {
        await perform {
            try await backend.setDisplayName(name)
            profile = try await backend.profile()
            groups = try await backend.myGroups()
        }
    }

    func acceptCommunityTerms() async -> Bool {
        await perform {
            try await backend.acceptCommunityTerms()
            profile = try await backend.profile()
        }
    }

    // MARK: Safety

    func block(_ user: UUID) async {
        await perform {
            try await backend.block(user)
            blocked.insert(user)
        }
    }

    /// Blocks whoever wrote a community post (works for anonymous posts too).
    func blockAuthor(ofPost post: UUID) async -> Bool {
        await perform {
            try await backend.blockAuthor(ofPost: post)
            blocked = try await backend.blockedUsers()
        }
    }

    func unblock(_ user: UUID) async {
        await perform {
            try await backend.unblock(user)
            blocked.remove(user)
        }
    }

    func report(_ kind: ContentKind, id: UUID, reason: String) async -> Bool {
        await perform { try await backend.report(kind, id: id, reason: reason) }
    }

    // MARK: Groups

    func group(_ id: UUID) -> GroupSummary? {
        groups.first { $0.id == id }
    }

    func createGroup(_ draft: GroupDraft) async -> UUID? {
        var created: UUID?
        await perform {
            created = try await backend.createGroup(draft)
            groups = try await backend.myGroups()
        }
        return created
    }

    func joinGroup(code: String) async -> UUID? {
        var joined: UUID?
        await perform {
            joined = try await backend.joinGroup(code: code)
            groups = try await backend.myGroups()
        }
        return joined
    }

    func updateGroup(_ id: UUID, draft: GroupDraft) async -> Bool {
        await perform {
            try await backend.updateGroup(id, draft: draft)
            groups = try await backend.myGroups()
        }
    }

    func newInviteCode(_ id: UUID) async {
        await perform {
            _ = try await backend.newInviteCode(id)
            groups = try await backend.myGroups()
        }
    }

    func setNotifications(_ on: Bool, for id: UUID) async {
        await perform {
            try await backend.setNotifications(on, for: id)
            if let index = groups.firstIndex(where: { $0.id == id }) { groups[index].notifications = on }
        }
    }

    func leaveGroup(_ id: UUID) async -> Bool {
        await perform {
            try await backend.leaveGroup(id)
            groups.removeAll { $0.id == id }
        }
    }

    func deleteGroup(_ id: UUID) async -> Bool {
        await perform {
            try await backend.deleteGroup(id)
            groups.removeAll { $0.id == id }
        }
    }
}
