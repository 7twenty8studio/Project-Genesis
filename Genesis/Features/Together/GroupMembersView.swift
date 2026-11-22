import SwiftUI

/// Members, the invite code, notifications, and leaving or closing the
/// group. Moderation is the navigation bar's button (GroupModerationToolbar).
struct GroupMembersView: View {
    let model: GroupDetailModel
    let group: GroupSummary

    @Environment(CommunityStore.self) private var community
    @Environment(FeaturePreferences.self) private var features
    @Environment(FeatureFlagService.self) private var flags
    @Environment(\.palette) private var palette
    @State private var editing = false
    @State private var confirmingLeave = false
    @State private var confirmingDelete = false
    @State private var removing: GroupMember?
    @State private var banning: GroupMember?
    @State private var newOwner: GroupMember?
    @State private var confirmingStepDown = false

    /// The signed-in person's own row, while they're one of the church's preachers.
    private var myPreacherRow: GroupMember? {
        model.members.first { community.isMine($0.userID) && model.permissions.canStepDown($0) }
    }

    var body: some View {
        List {
            ThemedRows {
                inviteSection
                Section {
                    ForEach(model.members) { member in
                        GroupMemberRow(model: model, member: member, removing: $removing, banning: $banning, newOwner: $newOwner)
                    }
                } header: {
                    Text("Members")
                } footer: {
                    if features.shows(.nudges, flags: flags), model.members.count > 1 {
                        Text("Tap the wave to send someone a friendly nudge: \(nudgePreview)")
                    }
                }
                .listRowBackground(palette.surface)
                settingsSection
            }
        }
        .sheet(isPresented: $editing) {
            GroupFormView(existing: group) { _ in }
        }
        .modifier(GroupLeaveAndCloseDialogs(group: group, confirmingLeave: $confirmingLeave, confirmingDelete: $confirmingDelete))
        .modifier(GroupMemberDialogs(model: model, removing: $removing, banning: $banning, newOwner: $newOwner))
        .confirmationDialog("Step down as preacher?", isPresented: $confirmingStepDown, titleVisibility: .visible) {
            Button("Step Down", role: .destructive) {
                if let me = myPreacherRow { Task { await model.setChurchRole(.member, for: me) } }
            }
        } message: {
            Text("Your sermons stay with the church, and its admins can hand them to someone else. You stay a member.")
        }
    }

    /// What a nudge says. The push uses this same sentence (group-notify's
    /// loc-key), so it's read in the receiver's language.
    private var nudgePreview: String {
        let name = model.members.first { community.isMine($0.userID) }?.displayName ?? String(localized: "A friend")
        return String(localized: "\(name) is praying for you. Read with me today?", comment: "Group nudge; also the push notification's text (group-notify NUDGE_BODY_KEY)")
    }

    private var inviteFooter: String {
        if !group.isLeader { return String(localized: "Share the code with people you'd like to join.") }
        if group.requiresApproval {
            return group.isChurch
                ? String(localized: "Anyone with the code can ask to join, and an admin lets them in.")
                : String(localized: "Anyone with the code can ask to join, and a moderator lets them in.")
        }
        return String(localized: "Anyone with the code can join. Make a new code to stop the old one working.")
    }

    private var inviteSection: some View {
        Section {
            LabeledContent("Invite code") {
                Text(group.formattedInviteCode)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("group.inviteCode")
            }
            ShareLink(item: inviteMessage) {
                Label("Invite People", systemImage: "square.and.arrow.up")
            }
            if group.isLeader {
                Button("New Code", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await community.newInviteCode(group.id) }
                }
            }
        } footer: {
            Text(inviteFooter)
        }
        .listRowBackground(palette.surface)
    }

    private var settingsSection: some View {
        Section {
            Toggle("Announcement Notifications", isOn: Binding(
                get: { community.group(group.id)?.notifications ?? true },
                set: { on in
                    Task {
                        await community.setNotifications(on, for: group.id)
                        if on { await PushNotifications.shared.enable() }
                    }
                }
            ))
            .accessibilityIdentifier("group.notifications")
            if group.isLeader {
                Button("Edit Group", systemImage: "pencil") { editing = true }
            }
            if myPreacherRow != nil {
                Button("Step Down as Preacher", systemImage: "person.crop.circle.badge.minus") { confirmingStepDown = true }
                    .accessibilityIdentifier("group.stepDown")
            }
            Button("Leave Group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmingLeave = true }
                .accessibilityIdentifier("group.leave")
            if group.isOwner {
                Button("Close Group", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .accessibilityIdentifier("group.close")
            }
        }
        .listRowBackground(palette.surface)
    }

    private var inviteMessage: String {
        String(localized: "Join \(group.name) on Versely to read and pray together. Open Together › Join with an Invite Code and enter \(group.formattedInviteCode).")
    }
}

/// One member: their name, role (Owner, Moderator or Member; in a church
/// Owner, Admin, Preacher or Member), whether
/// they're muted, and what the signed-in person may do about them.
private struct GroupMemberRow: View {
    let model: GroupDetailModel
    let member: GroupMember
    @Binding var removing: GroupMember?
    @Binding var banning: GroupMember?
    @Binding var newOwner: GroupMember?

    @Environment(CommunityStore.self) private var community
    @Environment(FeaturePreferences.self) private var features
    @Environment(FeatureFlagService.self) private var flags
    @Environment(\.palette) private var palette

    private var isMe: Bool { community.isMine(member.userID) }
    private var canNudge: Bool {
        !isMe && features.shows(.nudges, flags: flags) && !community.blocked.contains(member.userID)
    }
    private var standing: GroupStanding { model.permissions.standing(of: member) }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? String(localized: "\(member.displayName) (you)") : member.displayName)
                    .foregroundStyle(palette.text)
                details
            }
            Spacer()
            if canNudge {
                nudgeButton
            }
            if !isMe {
                Menu {
                    GroupMemberActions(model: model, member: member, removing: $removing, banning: $banning, newOwner: $newOwner)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Options for \(member.displayName)")
                .accessibilityIdentifier("member.options")
            }
        }
    }

    @ViewBuilder
    private var nudgeButton: some View {
        if model.nudged.contains(member.userID) {
            Label("Nudged", systemImage: "checkmark")
                .labelStyle(.iconOnly)
                .foregroundStyle(palette.secondaryText)
                .accessibilityLabel("Nudged \(member.displayName)")
                .accessibilityIdentifier("member.nudged")
        } else {
            Button {
                Task { await model.nudge(member) }
            } label: {
                Image(systemName: "hand.wave")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Nudge \(member.displayName) to read today")
            .accessibilityIdentifier("member.nudge")
        }
    }

    private var details: some View {
        HStack(spacing: 8) {
            Text(standing.title(inChurch: model.permissions.isChurch))
                .font(.caption)
                .foregroundStyle(standing == .member ? palette.secondaryText : palette.accent)
                .accessibilityIdentifier("member.role")
            if member.isMuted() {
                Label("Muted", systemImage: "speaker.slash")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityIdentifier("member.muted")
            }
        }
    }
}

/// The menu for one member, offering only what the signed-in person may do:
/// the owner chooses moderators (a church's admins) and can hand the group
/// on; a church's owner and admins choose its preachers; moderators mute,
/// remove and ban members (and the owner can do that to moderators too).
private struct GroupMemberActions: View {
    let model: GroupDetailModel
    let member: GroupMember
    @Binding var removing: GroupMember?
    @Binding var banning: GroupMember?
    @Binding var newOwner: GroupMember?

    @Environment(CommunityStore.self) private var community

    var body: some View {
        let permissions = model.permissions
        if permissions.canChooseRole(of: member) {
            if permissions.isChurch { churchAdminButtons } else { roleButtons }
        }
        if permissions.canChoosePreacher(of: member) {
            preacherButtons
        }
        if permissions.canModerate(member) {
            moderationButtons
        }
        if community.blocked.contains(member.userID) {
            Button("Unblock", systemImage: "hand.raised.slash") { Task { await community.unblock(member.userID) } }
        } else {
            Button("Block", systemImage: "hand.raised") { Task { await community.block(member.userID) } }
        }
    }

    @ViewBuilder
    private var roleButtons: some View {
        if member.role == .member {
            Button("Make Moderator", systemImage: "star") { Task { await model.setRole(.leader, for: member) } }
        } else {
            Button("Remove as Moderator", systemImage: "star.slash") { Task { await model.setRole(.member, for: member) } }
        }
        Button("Make Owner…", systemImage: "crown") { newOwner = member }
    }

    /// A church's owner: admins instead of moderators.
    @ViewBuilder
    private var churchAdminButtons: some View {
        if member.role == .member {
            Button("Make Admin", systemImage: "star") { Task { await model.setChurchRole(.admin, for: member) } }
        } else {
            Button("Remove as Admin", systemImage: "star.slash") { Task { await model.setChurchRole(.member, for: member) } }
        }
        Button("Make Owner…", systemImage: "crown") { newOwner = member }
    }

    /// Preachers write and publish the sermons they start in Church Studio.
    @ViewBuilder
    private var preacherButtons: some View {
        if member.isPreacher {
            Button("Remove as Preacher", systemImage: "text.book.closed") { Task { await model.setChurchRole(.member, for: member) } }
        } else {
            Button("Make Preacher", systemImage: "text.book.closed.fill") { Task { await model.setChurchRole(.preacher, for: member) } }
        }
    }

    @ViewBuilder
    private var moderationButtons: some View {
        if member.isMuted() {
            Button("Unmute", systemImage: "speaker.wave.2") { Task { await model.mute(member, for: nil) } }
        } else {
            Menu {
                ForEach(MuteDuration.allCases) { duration in
                    Button(duration.title) { Task { await model.mute(member, for: duration) } }
                }
            } label: {
                Label("Mute", systemImage: "speaker.slash")
            }
        }
        Button("Remove from Group", systemImage: "person.badge.minus", role: .destructive) { removing = member }
        Button("Ban…", systemImage: "nosign", role: .destructive) { banning = member }
    }
}

/// Leaving (the owner hears who takes over) and closing the group.
private struct GroupLeaveAndCloseDialogs: ViewModifier {
    let group: GroupSummary
    @Binding var confirmingLeave: Bool
    @Binding var confirmingDelete: Bool

    @Environment(CommunityStore.self) private var community
    @Environment(AppRouter.self) private var router

    private var leaveMessage: String {
        guard group.isOwner else { return String(localized: "You can join again with the invite code.") }
        return group.isChurch
            ? String(localized: "Your longest-standing admin becomes the owner, or your longest-standing member if there are no admins.")
            : String(localized: "Your longest-standing moderator becomes the owner, or your longest-standing member if there are no moderators.")
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Leave \(group.name)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) {
                    Task {
                        if await community.leaveGroup(group.id) { router.togetherPath.removeAll() }
                    }
                }
            } message: {
                Text(leaveMessage)
            }
            .confirmationDialog("Close \(group.name) for everyone?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Close Group", role: .destructive) {
                    Task {
                        if await community.deleteGroup(group.id) { router.togetherPath.removeAll() }
                    }
                }
            } message: {
                Text("Members lose access to its prayer requests, discussion and announcements.")
            }
    }
}

/// Confirmations for removing, banning (with an optional reason) and making
/// someone the owner.
private struct GroupMemberDialogs: ViewModifier {
    let model: GroupDetailModel
    @Binding var removing: GroupMember?
    @Binding var banning: GroupMember?
    @Binding var newOwner: GroupMember?

    @State private var reason = ""

    private var removingName: String { removing?.displayName ?? "" }
    private var banningName: String { banning?.displayName ?? "" }
    private var newOwnerName: String { newOwner?.displayName ?? "" }

    private var isRemoving: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    private var isBanning: Binding<Bool> {
        Binding(get: { banning != nil }, set: { if !$0 { banning = nil } })
    }

    private var isChoosingOwner: Binding<Bool> {
        Binding(get: { newOwner != nil }, set: { if !$0 { newOwner = nil } })
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Remove \(removingName)?", isPresented: isRemoving, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let member = removing { Task { await model.remove(member) } }
                }
            } message: {
                Text("They can rejoin only with the new invite code.")
            }
            .alert("Ban \(banningName)?", isPresented: isBanning) {
                TextField("Reason (optional)", text: $reason)
                Button("Ban", role: .destructive) {
                    let text = reason
                    reason = ""
                    if let member = banning { Task { await model.ban(member, reason: text) } }
                }
                Button("Cancel", role: .cancel) { reason = "" }
            } message: {
                Text("They're removed from the group and can't rejoin with any invite code.")
            }
            .confirmationDialog("Make \(newOwnerName) the owner?", isPresented: isChoosingOwner, titleVisibility: .visible) {
                Button("Make Owner") {
                    if let member = newOwner { Task { await model.makeOwner(member) } }
                }
            } message: {
                if model.permissions.isChurch {
                    Text("They'll choose admins and can close the group, and you'll stay on as an admin.")
                } else {
                    Text("They'll choose moderators and can close the group, and you'll stay on as a moderator.")
                }
            }
    }
}
