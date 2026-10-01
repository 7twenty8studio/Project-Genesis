import Foundation

/// One group's page: today's reading, prayer requests, discussion,
/// announcements and members.
@MainActor
@Observable
final class GroupDetailModel {
    let groupID: UUID
    private(set) var members: [GroupMember] = []
    private(set) var prayers: [GroupPrayer] = []
    private(set) var prayedFor: Set<UUID> = []
    private(set) var posts: [GroupPost] = []
    private(set) var announcements: [GroupAnnouncement] = []
    /// Who has read today's plan day.
    private(set) var readToday: Set<UUID> = []
    private(set) var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let store: CommunityStore
    private var backend: CommunityBackend { store.backend }

    init(groupID: UUID, store: CommunityStore) {
        self.groupID = groupID
        self.store = store
    }

    var group: GroupSummary? { store.group(groupID) }
    var today: Int? { group?.planDay() }

    var hasReadToday: Bool {
        guard let me = store.userID else { return false }
        return readToday.contains(me)
    }

    /// Hides people you've blocked.
    private func visible<T>(_ items: [T], author: (T) -> UUID) -> [T] {
        items.filter { !store.blocked.contains(author($0)) }
    }

    var visiblePrayers: [GroupPrayer] { visible(prayers, author: \.userID) }
    var visibleAnnouncements: [GroupAnnouncement] { visible(announcements, author: \.userID) }

    func posts(forDay day: Int?) -> [GroupPost] {
        visible(posts.filter { $0.day == day }, author: \.userID)
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let backend = self.backend
        let groupID = self.groupID
        do {
            async let members = backend.members(of: groupID)
            async let prayers = backend.prayers(in: groupID)
            async let posts = backend.posts(in: groupID)
            async let announcements = backend.announcements(in: groupID)
            self.members = try await members
            self.prayers = try await prayers
            self.posts = try await posts
            self.announcements = try await announcements
            prayedFor = try await backend.myPrayerMarks(self.prayers.map(\.id))
            if let today, today > 0 {
                readToday = Set(try await backend.progress(in: groupID, day: today).map(\.userID))
            }
            errorMessage = nil
        } catch {
            errorMessage = CommunityError.from(error).localizedDescription
        }
    }

    @discardableResult
    private func run(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            errorMessage = nil
            return true
        } catch {
            errorMessage = CommunityError.from(error).localizedDescription
            return false
        }
    }

    // MARK: Reading

    func setReadToday(_ done: Bool) async {
        guard let today, today > 0, let me = store.userID else { return }
        // Show it straight away; put it back if saving fails.
        if done { readToday.insert(me) } else { readToday.remove(me) }
        let saved = await run { try await backend.setDayDone(done, day: today, in: groupID) }
        if !saved {
            if done { readToday.remove(me) } else { readToday.insert(me) }
        }
    }

    // MARK: Prayer

    func addPrayer(_ body: String) async -> Bool {
        await run {
            try await backend.addPrayer(body.trimmingCharacters(in: .whitespacesAndNewlines), to: groupID)
            prayers = try await backend.prayers(in: groupID)
        }
    }

    func setPrayed(_ prayed: Bool, for prayer: GroupPrayer) async {
        guard let index = prayers.firstIndex(where: { $0.id == prayer.id }) else { return }
        let wasPrayed = prayedFor.contains(prayer.id)
        guard wasPrayed != prayed else { return }
        if prayed { prayedFor.insert(prayer.id) } else { prayedFor.remove(prayer.id) }
        prayers[index].prayedCount += prayed ? 1 : -1
        let saved = await run { try await backend.setPrayed(prayed, prayer: prayer.id) }
        if !saved {
            if prayed { prayedFor.remove(prayer.id) } else { prayedFor.insert(prayer.id) }
            if let index = prayers.firstIndex(where: { $0.id == prayer.id }) { prayers[index].prayedCount += prayed ? -1 : 1 }
        }
    }

    func setAnswered(_ answered: Bool, for prayer: GroupPrayer) async {
        await run {
            try await backend.setAnswered(answered, prayer: prayer.id)
            prayers = try await backend.prayers(in: groupID)
        }
    }

    // MARK: Discussion and announcements

    func addPost(_ body: String, day: Int?) async -> Bool {
        await run {
            try await backend.addPost(body.trimmingCharacters(in: .whitespacesAndNewlines), day: day, to: groupID)
            posts = try await backend.posts(in: groupID)
        }
    }

    func addAnnouncement(title: String, body: String) async -> Bool {
        await run {
            try await backend.addAnnouncement(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: body.trimmingCharacters(in: .whitespacesAndNewlines),
                to: groupID
            )
            announcements = try await backend.announcements(in: groupID)
        }
    }

    func remove(_ kind: ContentKind, id: UUID) async {
        await run {
            try await backend.remove(kind, id: id)
            prayers.removeAll { $0.id == id }
            posts.removeAll { $0.id == id }
            announcements.removeAll { $0.id == id }
        }
    }

    /// Reported content disappears for the person who reported it.
    func hide(_ id: UUID) {
        prayers.removeAll { $0.id == id }
        posts.removeAll { $0.id == id }
        announcements.removeAll { $0.id == id }
    }

    // MARK: Members

    func setRole(_ role: GroupRole, for member: GroupMember) async {
        await run {
            try await backend.setRole(role, for: member.userID, in: groupID)
            members = try await backend.members(of: groupID)
        }
        await store.refresh()
    }

    func remove(_ member: GroupMember) async {
        await run {
            try await backend.removeMember(member.userID, from: groupID)
            members.removeAll { $0.userID == member.userID }
        }
    }
}
