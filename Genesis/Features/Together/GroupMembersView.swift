import SwiftUI

/// Members, the invite code, notifications, and leaving or closing the group.
struct GroupMembersView: View {
    let model: GroupDetailModel
    let group: GroupSummary

    @Environment(CommunityStore.self) private var community
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @State private var editing = false
    @State private var confirmingLeave = false
    @State private var confirmingDelete = false
    @State private var removing: GroupMember?

    var body: some View {
        List {
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
                Text(group.isLeader ? "Anyone with the code can join. Make a new code to stop the old one working." : "Share the code with people you'd like to join.")
            }
            .listRowBackground(palette.surface)

            Section("Members") {
                ForEach(model.members) { member in
                    memberRow(member)
                }
            }
            .listRowBackground(palette.surface)

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
                if group.isLeader {
                    Button("Close Group", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
            .listRowBackground(palette.surface)
        }
        .sheet(isPresented: $editing) {
            GroupFormView(existing: group) { _ in }
        }
        .confirmationDialog("Leave \(group.name)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task {
                    if await community.leaveGroup(group.id) { router.togetherPath.removeAll() }
                }
            }
        } message: {
            Text("You can join again with the invite code.")
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
        .confirmationDialog("Remove \(removing?.displayName ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let member = removing { Task { await model.remove(member) } }
            }
        }
    }

    private var inviteMessage: String {
        "Join \(group.name) on Genesis to read and pray together. Open Together › Join with an Invite Code and enter \(group.formattedInviteCode)."
    }

    private func memberRow(_ member: GroupMember) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName + (community.isMine(member.userID) ? " (you)" : ""))
                    .foregroundStyle(palette.text)
                if member.role == .leader {
                    Text("Leader").font(.caption).foregroundStyle(palette.accent)
                }
            }
            Spacer()
            if group.isLeader, !community.isMine(member.userID) {
                Menu {
                    if member.role == .member {
                        Button("Make Leader", systemImage: "star") { Task { await model.setRole(.leader, for: member) } }
                    } else {
                        Button("Make Member", systemImage: "star.slash") { Task { await model.setRole(.member, for: member) } }
                    }
                    Button("Remove from Group", systemImage: "person.badge.minus", role: .destructive) { removing = member }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Manage \(member.displayName)")
            } else if !community.isMine(member.userID) {
                Menu {
                    if community.blocked.contains(member.userID) {
                        Button("Unblock", systemImage: "hand.raised.slash") { Task { await community.unblock(member.userID) } }
                    } else {
                        Button("Block", systemImage: "hand.raised") { Task { await community.block(member.userID) } }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Options for \(member.displayName)")
            }
        }
    }
}
