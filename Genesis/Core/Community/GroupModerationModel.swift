import Foundation

/// A group's moderation, for its owner and moderators: reported content,
/// people asking to join, and people who are banned.
@MainActor
@Observable
final class GroupModerationModel {
    let groupID: UUID
    private(set) var reports: [GroupReport] = []
    private(set) var requests: [GroupJoinRequest] = []
    private(set) var bans: [GroupBan] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    @ObservationIgnored private let store: CommunityStore
    private var backend: CommunityBackend { store.backend }

    init(groupID: UUID, store: CommunityStore) {
        self.groupID = groupID
        self.store = store
    }

    var group: GroupSummary? { store.group(groupID) }

    /// Reports and join requests waiting for someone to look at them.
    var pendingCount: Int { reports.count + requests.count }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let backend = self.backend
        let groupID = self.groupID
        do {
            async let reports = backend.reports(in: groupID)
            async let requests = backend.joinRequests(in: groupID)
            async let bans = backend.bans(in: groupID)
            self.reports = try await reports
            self.requests = try await requests
            self.bans = try await bans
            errorMessage = nil
        } catch {
            errorMessage = CommunityError.from(error).localizedDescription
        }
        hasLoaded = true
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

    // MARK: Join requests

    func setRequiresApproval(_ required: Bool) async {
        let saved = await store.setRequiresApproval(required, for: groupID)
        errorMessage = saved ? nil : store.errorMessage
        // Turning approval off lets in everyone waiting.
        if saved, !required { await refresh() }
    }

    func answer(_ request: GroupJoinRequest, accept: Bool) async {
        await run {
            try await backend.answerJoinRequest(from: request.userID, in: groupID, accept: accept)
            requests.removeAll { $0.userID == request.userID }
        }
    }

    /// Turns someone down and keeps them from asking again.
    func ban(_ request: GroupJoinRequest) async {
        await run {
            try await backend.banMember(request.userID, from: groupID, reason: "")
            requests.removeAll { $0.userID == request.userID }
            bans = try await backend.bans(in: groupID)
        }
    }

    // MARK: Bans

    func unban(_ ban: GroupBan) async {
        await run {
            try await backend.unbanMember(ban.userID, from: groupID)
            bans.removeAll { $0.userID == ban.userID }
        }
    }

    // MARK: Reports

    func review(_ report: GroupReport, action: ReportAction) async {
        guard let kind = report.kind else { return }
        await run {
            try await backend.reviewReport(kind, id: report.contentID, action: action)
            reports.removeAll { $0.contentID == report.contentID }
        }
    }
}
