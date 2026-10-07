import SwiftUI

/// Members, the invite code, notifications, and leaving or closing the
/// group. Moderation is the navigation bar's button (GroupModerationToolbar).
struct GroupMembersView: View {
    let model: GroupDetailModel
    let group: GroupSummary

    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette
    @State private var editing = false
    @State private var confirmingLeave = false
    @State private var confirmingDelete = false
    @State private var removing: GroupMember?
    @State private var banning: GroupMember?
    @State private var newOwner: GroupMember?

    var body: some View {
        List {
            ThemedRows {
                inviteSection
                Section("Members") {
                    ForEach(model.members) { member in
                        GroupMemberRow(model: model, member: member, removing: $removing, banning: $banning, newOwner: $newOwner)
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
    }

    private var inviteFooter: String {
        if !group.isLeader { return String(localized: "Share the code with people you'd like to join.") }
        if group.requiresApproval { return String(localized: "Anyone with the code can ask to join, and a moderator lets them in.") }
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
        String(localized: "Join \(group.name) on Genesis to read and pray together. Open Together › Join with an Invite Code and enter \(group.formattedInviteCode).")
    }
}

/// One member: their name, role (Owner, Moderator or Member), whether
/// they're muted, and what the signed-in person may do about them.
private struct GroupMemberRow: View {
    let model: GroupDetailModel
    let member: GroupMember
    @Binding var removing: GroupMember?
    @Binding var banning: GroupMember?
    @Binding var newOwner: GroupMember?

    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette

    private var isMe: Bool { community.isMine(member.userID) }
    private var standing: GroupStanding { model.permissions.standing(of: member) }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? String(localized: "\(member.displayName) (you)") : member.displayName)
                    .foregroundStyle(palette.text)
                details
            }
            Spacer()
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

    private var details: some View {
        HStack(spacing: 8) {
            Text(standing.title)
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
/// the owner chooses moderators and can hand the group on; moderators mute,
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
            roleButtons
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
        group.isOwner
            ? String(localized: "Your longest-standing moderator becomes the owner, or your longest-standing member if there are no moderators.")
            : String(localized: "You can join again with the invite code.")
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
                Text("They'll choose moderators and can close the group, and you'll stay on as a moderator.")
            }
    }
}
