import SwiftUI

/// Your groups, with create and join.
struct GroupsListView: View {
    @Environment(CommunityStore.self) private var community
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case create, join
        var id: String { rawValue }
    }

    private var actions: some View {
        Section {
            Button {
                sheet = .join
            } label: {
                Label("Join with an Invite Code", systemImage: "ticket")
            }
            .accessibilityIdentifier("groups.join")
            Button {
                sheet = .create
            } label: {
                Label("Start a Group", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("groups.create")
        }
        .listRowBackground(palette.surface)
    }

    var body: some View {
        List {
            if let error = community.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .listRowBackground(Color.clear)
            }
            if community.groups.isEmpty {
                // Join and Start come first here: below the empty-state message
                // they fall off screen on a phone in landscape.
                actions
                QuietEmptyState(
                    systemImage: "person.3",
                    title: String(localized: "No groups yet"),
                    message: String(localized: "Ask your group leader for an invite code, or start a group for your church, small group or family.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(community.groups) { group in
                        NavigationLink(value: TogetherRoute.group(group.id)) {
                            GroupRow(group: group)
                        }
                        .listRowBackground(palette.surface)
                        .accessibilityIdentifier("groups.row")
                    }
                }
                actions
            }
        }
        .refreshable { await community.refresh() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .create:
                GroupFormView(existing: nil) { id in
                    self.sheet = nil
                    router.togetherPath.append(.group(id))
                }
            case .join:
                JoinGroupView { id in
                    self.sheet = nil
                    router.togetherPath.append(.group(id))
                }
            }
        }
    }
}

private struct GroupRow: View {
    let group: GroupSummary
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(palette.text)
                if group.isLeader {
                    Text("Leader")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(palette.accent.opacity(0.15), in: Capsule())
                        .foregroundStyle(palette.accent)
                }
            }
            if let plan = group.plan, let day = group.planDay() {
                Text(day == 0 ? "\(plan.title) · starts soon" : "\(plan.title) · day \(day) of \(plan.dayCount)")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            } else if !group.description.isEmpty {
                Text(group.description)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Create a group, or edit one you lead.
struct GroupFormView: View {
    let existing: GroupSummary?
    let onSaved: (UUID) -> Void

    @Environment(CommunityStore.self) private var community
    @Environment(\.dismiss) private var dismiss
    @State private var draft = GroupDraft()
    @State private var hasPlan = true
    @State private var planID = ReadingPlan.gospelsID
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group name", text: $draft.name)
                        .accessibilityIdentifier("groupForm.name")
                    TextField("What's it for? (optional)", text: $draft.description, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Toggle("Read a plan together", isOn: $hasPlan)
                    if hasPlan {
                        Picker("Plan", selection: $planID) {
                            if let custom = existingCustomPlan {
                                Text(custom.title).tag(Self.keepExisting)
                            }
                            ForEach(ReadingPlan.builtIns) { plan in
                                Text(plan.title).tag(plan.id)
                            }
                        }
                        DatePicker("Starts", selection: $draft.planStart, displayedComponents: .date)
                    }
                } footer: {
                    Text("Everyone sees the same day's reading, who has read it, and a discussion for each day.")
                }
                if let error = community.errorMessage {
                    Section { Text(error).foregroundStyle(.orange) }
                }
            }
            .navigationTitle(existing == nil ? "Start a Group" : "Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Create" : "Save", systemImage: "checkmark", action: save)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .accessibilityIdentifier("groupForm.save")
                }
            }
            .onAppear(perform: load)
        }
    }

    private static let keepExisting = "existing-plan"

    /// A group's own (custom) plan, offered so editing doesn't replace it.
    private var existingCustomPlan: ReadingPlan? {
        guard let plan = existing?.plan, ReadingPlan.builtIn(id: plan.id) == nil else { return nil }
        return plan
    }

    private func load() {
        guard let existing else { return }
        draft.name = existing.name
        draft.description = existing.description
        hasPlan = existing.plan != nil
        if let id = existing.plan?.id {
            planID = ReadingPlan.builtIn(id: id) != nil ? id : Self.keepExisting
        }
        if let start = existing.planStart { draft.planStart = start }
    }

    private func save() {
        isSaving = true
        var draft = draft
        draft.plan = hasPlan ? (planID == Self.keepExisting ? existingCustomPlan : ReadingPlan.builtIn(id: planID)) : nil
        Task {
            if let existing {
                if await community.updateGroup(existing.id, draft: draft) {
                    dismiss()
                    onSaved(existing.id)
                }
            } else if let id = await community.createGroup(draft) {
                await PushNotifications.shared.enable()
                onSaved(id)
            }
            isSaving = false
        }
    }
}

/// Join a group with the code a leader shared.
struct JoinGroupView: View {
    let onJoined: (UUID) -> Void

    @Environment(CommunityStore.self) private var community
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isJoining = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title3.monospaced())
                        .focused($focused)
                        .submitLabel(.join)
                        .onSubmit(join)
                        .accessibilityIdentifier("joinGroup.code")
                } footer: {
                    Text(community.errorMessage ?? String(localized: "Your group leader can share the code from the group's Members page."))
                        .foregroundStyle(community.errorMessage == nil ? Color.secondary : Color.orange)
                }
            }
            .navigationTitle("Join a Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join", systemImage: "checkmark", action: join)
                        .disabled(code.filter { $0.isLetter || $0.isNumber }.count < 6 || isJoining)
                        .accessibilityIdentifier("joinGroup.join")
                }
            }
            .onAppear {
                community.errorMessage = nil
                focused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func join() {
        guard !isJoining else { return }
        isJoining = true
        Task {
            if let id = await community.joinGroup(code: code) {
                await PushNotifications.shared.enable()
                onJoined(id)
            }
            isJoining = false
        }
    }
}
