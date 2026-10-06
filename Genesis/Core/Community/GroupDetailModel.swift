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
    /// Each member's progress through the plan.
    private(set) var memberProgress: [UUID: MemberProgress] = [:]
    /// Who read each earlier day, loaded when that day is opened.
    private(set) var dayReaders: [Int: Set<UUID>] = [:]
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
                dayReaders[today] = readToday
            }
            if group?.plan != nil {
                let summary = try await backend.progressSummary(in: groupID)
                memberProgress = Dictionary(summary.map { ($0.userID, $0) }, uniquingKeysWith: { first, _ in first })
            }
            errorMessage = nil
            writeWidget()
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
        guard let today, today > 0 else { return }
        await setRead(done, day: today)
    }

    func hasRead(day: Int) -> Bool {
        guard let me = store.userID else { return false }
        return dayReaders[day]?.contains(me) ?? false
    }

    /// Marks any day of the plan read (or not), for catching up.
    func setRead(_ done: Bool, day: Int) async {
        guard let me = store.userID else { return }
        // Show it straight away; put it back if saving fails.
        let before = (dayReaders[day], readToday, memberProgress[me])
        apply(done, day: day, user: me)
        let saved = await run { try await backend.setDayDone(done, day: day, in: groupID) }
        if saved {
            writeWidget()
        } else {
            dayReaders[day] = before.0
            readToday = before.1
            memberProgress[me] = before.2
        }
    }

    private func apply(_ done: Bool, day: Int, user: UUID) {
        var readers = dayReaders[day] ?? []
        let changed = done ? readers.insert(user).inserted : readers.remove(user) != nil
        dayReaders[day] = readers
        if day == today { readToday = readers }
        guard changed else { return }
        let old = memberProgress[user] ?? MemberProgress(userID: user, daysDone: 0, lastDay: 0)
        memberProgress[user] = MemberProgress(
            userID: user,
            daysDone: max(0, old.daysDone + (done ? 1 : -1)),
            lastDay: done ? max(old.lastDay, day) : old.lastDay
        )
    }

    /// Who read a given day (for the plan's day pages).
    func loadReaders(day: Int) async {
        do {
            dayReaders[day] = Set(try await backend.progress(in: groupID, day: day).map(\.userID))
        } catch {
            errorMessage = CommunityError.from(error).localizedDescription
        }
    }

    /// Members with their progress, furthest along first.
    var progressRows: [(member: GroupMember, progress: MemberProgress)] {
        members
            .filter { !store.blocked.contains($0.userID) }
            .map { ($0, memberProgress[$0.userID] ?? MemberProgress(userID: $0.userID, daysDone: 0, lastDay: 0)) }
            .sorted { lhs, rhs in
                lhs.progress.daysDone == rhs.progress.daysDone
                    ? lhs.member.displayName.localizedCompare(rhs.member.displayName) == .orderedAscending
                    : lhs.progress.daysDone > rhs.progress.daysDone
            }
    }

    // MARK: Widget

    /// The group's progress for the Group Progress widget (the group opened
    /// most recently).
    private func writeWidget() {
        guard let group, let plan = group.plan, let day = today else { return }
        let me = store.userID
        let rows = progressRows.prefix(8).map { row in
            GroupWidgetSnapshot.Member(
                name: row.member.userID == me ? String(localized: "You") : row.member.displayName,
                fraction: plan.dayCount > 0 ? min(1, Double(row.progress.daysDone) / Double(plan.dayCount)) : 0,
                readToday: readToday.contains(row.member.userID)
            )
        }
        let snapshot = GroupWidgetSnapshot(
            groupID: group.id,
            groupName: group.name,
            planTitle: plan.title,
            day: day,
            dayCount: plan.dayCount,
            dayTitle: day > 0 && day <= plan.days.count ? plan.days[day - 1].title : nil,
            readTodayCount: readToday.count,
            memberCount: members.count,
            members: Array(rows),
            updatedAt: .now
        )
        try? snapshot.save()
        GroupWidgetSnapshot.reloadWidget()
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
