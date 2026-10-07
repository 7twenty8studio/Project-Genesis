import SwiftUI

/// Moderation for a group's owner and moderators: whether new members need
/// approving, people asking to join, reported content, and banned people.
struct GroupModerationView: View {
    let model: GroupModerationModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            List {
                ThemedRows {
                    if let error = model.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    ModerationApprovalSection(model: model)
                    ModerationRequestsSection(model: model)
                    ModerationReportsSection(model: model)
                    ModerationBansSection(model: model)
                }
            }
            .buttonStyle(.borderless)
            .themedScreen()
            .navigationTitle("Moderation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("moderation.done")
                }
            }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
        }
    }
}

/// "Approve new members" (set_group_approval).
private struct ModerationApprovalSection: View {
    let model: GroupModerationModel

    @Environment(\.palette) private var palette

    private var approval: Binding<Bool> {
        Binding(
            get: { model.group?.requiresApproval ?? false },
            set: { on in Task { await model.setRequiresApproval(on) } }
        )
    }

    var body: some View {
        Section {
            Toggle("Approve New Members", isOn: approval)
                .accessibilityIdentifier("moderation.approval")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("When this is on, people with the invite code ask to join and a moderator lets them in.")
                Text("Turning this off lets in everyone waiting.")
            }
        }
        .listRowBackground(palette.surface)
    }
}

/// People asking to join: approve, decline, or ban.
private struct ModerationRequestsSection: View {
    let model: GroupModerationModel

    @Environment(\.palette) private var palette

    var body: some View {
        Section {
            if model.requests.isEmpty {
                Text("No one is waiting to join.")
                    .foregroundStyle(palette.secondaryText)
            }
            ForEach(model.requests) { request in
                row(request)
            }
        } header: {
            Text("Join Requests")
        }
        .listRowBackground(palette.surface)
    }

    private func row(_ request: GroupJoinRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.text)
            Text("Asked \(request.createdAt.formatted(.relative(presentation: .named))).")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
            HStack(spacing: 18) {
                Button("Approve", systemImage: "checkmark.circle") {
                    Task { await model.answer(request, accept: true) }
                }
                .accessibilityIdentifier("moderation.approve")
                Button("Decline", systemImage: "xmark.circle") {
                    Task { await model.answer(request, accept: false) }
                }
                .accessibilityIdentifier("moderation.decline")
                Spacer()
                Menu {
                    Button("Ban", systemImage: "nosign", role: .destructive) {
                        Task { await model.ban(request) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More")
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

/// Reported posts, prayer requests and announcements: remove or keep.
private struct ModerationReportsSection: View {
    let model: GroupModerationModel

    @Environment(\.palette) private var palette

    var body: some View {
        Section {
            if model.reports.isEmpty {
                Text("Nothing has been reported.")
                    .foregroundStyle(palette.secondaryText)
            }
            ForEach(model.reports) { report in
                ModerationReportRow(model: model, report: report)
            }
        } header: {
            Text("Reports")
        } footer: {
            Text("Three reports hide something from everyone but its author and the moderators until it's reviewed.")
        }
        .listRowBackground(palette.surface)
    }
}

private struct ModerationReportRow: View {
    let model: GroupModerationModel
    let report: GroupReport

    @Environment(\.palette) private var palette

    private var kindTitle: String {
        guard let kind = report.kind else { return String(localized: "Group post") }
        switch kind {
        case .groupPrayer: return String(localized: "Prayer request")
        case .groupPost: return String(localized: "Discussion message")
        case .groupAnnouncement: return String(localized: "Announcement")
        case .communityPost, .communityComment: return String(localized: "Group post")
        }
    }

    private var countText: String {
        report.reportCount == 1
            ? String(localized: "Reported once")
            : String(localized: "Reported \(report.reportCount) times")
    }

    /// The reasons people chose, in the app's language.
    private var reasonsText: String {
        let titles = report.reasons.map { reason in
            ContentActions.reasons.first { $0.value == reason }?.title ?? reason
        }
        return Array(Set(titles)).sorted().formatted(.list(type: .and))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(report.authorName) · \(kindTitle)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.text)
            Text(report.body)
                .foregroundStyle(palette.text)
                .lineLimit(6)
            Text(countText)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .accessibilityIdentifier("moderation.reportCount")
            if !report.reasons.isEmpty {
                Text(reasonsText)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            if report.hidden {
                HiddenForReviewLabel()
            }
            actions
        }
        .padding(.vertical, 4)
    }

    private var actions: some View {
        HStack(spacing: 18) {
            Button("Remove", systemImage: "trash", role: .destructive) {
                Task { await model.review(report, action: .remove) }
            }
            .accessibilityIdentifier("moderation.remove")
            Button("Keep", systemImage: "checkmark.circle") {
                Task { await model.review(report, action: .keep) }
            }
            .accessibilityIdentifier("moderation.keep")
        }
        .font(.subheadline)
        .padding(.top, 2)
    }
}

/// People kept out of the group: unban.
private struct ModerationBansSection: View {
    let model: GroupModerationModel

    @Environment(\.palette) private var palette

    var body: some View {
        Section {
            if model.bans.isEmpty {
                Text("No one is banned.")
                    .foregroundStyle(palette.secondaryText)
            }
            ForEach(model.bans) { ban in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ban.displayName)
                            .foregroundStyle(palette.text)
                        if !ban.reason.isEmpty {
                            Text(ban.reason)
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    Spacer()
                    Button("Unban") {
                        Task { await model.unban(ban) }
                    }
                    .accessibilityIdentifier("moderation.unban")
                }
            }
        } header: {
            Text("Banned")
        } footer: {
            Text("Banned people can't rejoin with any invite code.")
        }
        .listRowBackground(palette.surface)
    }
}

/// The group's Moderation button in the navigation bar, with a count of
/// reports and join requests waiting, for the owner and moderators.
struct GroupModerationToolbar: ViewModifier {
    let model: GroupDetailModel

    @State private var showing = false

    private var count: Int { model.moderation.pendingCount }

    private var accessibilityText: String {
        count > 0 ? String(localized: "Moderation, \(count) to review") : String(localized: "Moderation")
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if model.group?.isLeader == true {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showing = true
                        } label: {
                            ModerationBadgeIcon(count: count)
                        }
                        .accessibilityLabel(Text(accessibilityText))
                        .accessibilityIdentifier("group.moderationButton")
                    }
                }
            }
            .sheet(isPresented: $showing, onDismiss: { Task { await model.refresh() } }) {
                GroupModerationView(model: model.moderation)
            }
    }
}

private struct ModerationBadgeIcon: View {
    let count: Int

    @Environment(\.palette) private var palette

    var body: some View {
        Image(systemName: "shield.lefthalf.filled")
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(count, format: .number)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(palette.accent, in: Capsule())
                        .offset(x: 8, y: -8)
                }
            }
    }
}

/// On a post or prayer request that's hidden after three reports (seen only
/// by its author and the moderators).
struct HiddenForReviewLabel: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Label("Hidden while it's reviewed", systemImage: "eye.slash")
            .font(.caption)
            .foregroundStyle(palette.secondaryText)
            .accessibilityIdentifier("content.hiddenForReview")
    }
}

/// In place of a group's composer while the signed-in person is muted.
struct MutedComposerNotice: View {
    let until: Date

    @Environment(\.palette) private var palette

    var body: some View {
        Label(GroupDetailModel.mutedMessage(until: until), systemImage: "speaker.slash")
            .font(.subheadline)
            .foregroundStyle(palette.secondaryText)
            .accessibilityIdentifier("group.muted")
    }
}
