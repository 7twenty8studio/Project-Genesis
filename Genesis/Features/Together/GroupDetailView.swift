import SwiftUI

/// A group: today's reading and discussion, prayer requests, announcements
/// and members.
struct GroupDetailView: View {
    let groupID: UUID

    enum Tab: String, CaseIterable, Identifiable {
        case today, prayer, news, members
        var id: String { rawValue }
        var title: String {
            switch self {
            case .today: "Today"
            case .prayer: "Prayer"
            case .news: "News"
            case .members: "Members"
            }
        }
    }

    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette
    @State private var model: GroupDetailModel?
    @State private var tab: Tab = .today

    var body: some View {
        Group {
            if let model, let group = model.group {
                content(model, group: group)
                    .navigationTitle(group.name)
            } else if community.hasLoaded, community.group(groupID) == nil {
                QuietEmptyState(systemImage: "person.3", title: "Not available", message: "You're no longer in this group, or it was closed.")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if community.group(groupID) == nil { await community.refresh() }
            let model = model ?? GroupDetailModel(groupID: groupID, store: community)
            self.model = model
            await model.refresh()
        }
    }

    private func content(_ model: GroupDetailModel, group: GroupSummary) -> some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityIdentifier("group.tab")

            if let error = model.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
            }

            switch tab {
            case .today: GroupTodayView(model: model, group: group)
            case .prayer: GroupPrayersView(model: model)
            case .news: GroupAnnouncementsView(model: model, group: group)
            case .members: GroupMembersView(model: model, group: group)
            }
        }
        .refreshable { await model.refresh() }
    }
}

/// The day's reading, who has read it, and the discussion.
struct GroupTodayView: View {
    let model: GroupDetailModel
    let group: GroupSummary

    @Environment(AppRouter.self) private var router
    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette

    var body: some View {
        let day = model.today
        List {
            if let plan = group.plan, let day {
                Section {
                    if day == 0 {
                        Text("\(plan.title) starts \(group.planStart?.formatted(date: .abbreviated, time: .omitted) ?? "soon").")
                            .foregroundStyle(palette.secondaryText)
                    } else {
                        reading(plan.days[day - 1], plan: plan, day: day)
                    }
                } header: {
                    Text(day == 0 ? "Reading plan" : "Day \(day) of \(plan.dayCount)")
                }
                .listRowBackground(palette.surface)
            }
            DiscussionSection(model: model, day: (day ?? 0) > 0 ? day : nil)
        }
    }

    private func reading(_ planDay: PlanDay, plan: ReadingPlan, day: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(planDay.title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(palette.text)
                .accessibilityIdentifier("group.reading")
            HStack {
                if let first = planDay.spans.first?.first {
                    Button {
                        router.read(first)
                    } label: {
                        Label("Read", systemImage: "book")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button {
                    Task { await model.setReadToday(!model.hasReadToday) }
                } label: {
                    Label(model.hasReadToday ? "Done" : "Mark as read", systemImage: model.hasReadToday ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("group.markRead")
            }
            let readCount = model.readToday.count
            Text(model.members.isEmpty ? "" : "\(readCount) of \(model.members.count) \(model.members.count == 1 ? "member has" : "members have") read today")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
                .accessibilityIdentifier("group.readCount")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }
}

/// Messages about the day's reading (or general chat without a plan).
struct DiscussionSection: View {
    let model: GroupDetailModel
    let day: Int?

    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette
    @State private var draft = ""
    @State private var isSending = false

    var body: some View {
        let posts = model.posts(forDay: day)
        Section {
            if posts.isEmpty {
                Text(day == nil ? "Start the conversation." : "What stood out to you today?")
                    .foregroundStyle(palette.secondaryText)
            }
            ForEach(posts) { post in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(post.displayName).font(.subheadline.weight(.semibold))
                        Text(post.createdAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Text(post.body)
                        .foregroundStyle(palette.text)
                }
                .padding(.vertical, 2)
                .contentActions(
                    .groupPost, id: post.id, authorName: post.displayName, isMine: community.isMine(post.userID),
                    canRemove: community.isMine(post.userID) || (model.group?.isLeader ?? false),
                    onRemove: { await model.remove(.groupPost, id: post.id) },
                    onBlock: { await community.block(post.userID) },
                    onHidden: { model.hide(post.id) }
                )
                .accessibilityIdentifier("group.post")
            }
            HStack(alignment: .bottom) {
                TextField(day == nil ? "Write a message" : "Share a thought on today's reading", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .accessibilityIdentifier("group.postField")
                Button {
                    isSending = true
                    Task {
                        if await model.addPost(draft, day: day) { draft = "" }
                        isSending = false
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("group.send")
            }
        } header: {
            Text(day == nil ? "Discussion" : "Today's discussion")
        }
        .listRowBackground(palette.surface)
    }
}

/// Prayer requests shared with the group.
struct GroupPrayersView: View {
    let model: GroupDetailModel

    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette
    @State private var draft = ""
    @State private var isSending = false

    var body: some View {
        List {
            Section {
                HStack(alignment: .bottom) {
                    TextField("Share a prayer request", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .accessibilityIdentifier("group.prayerField")
                    Button {
                        isSending = true
                        Task {
                            if await model.addPrayer(draft) { draft = "" }
                            isSending = false
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    .accessibilityLabel("Share")
                    .accessibilityIdentifier("group.sharePrayer")
                }
            } footer: {
                Text("Only members of this group can see these.")
            }
            .listRowBackground(palette.surface)

            Section {
                if model.visiblePrayers.isEmpty {
                    Text("No prayer requests yet.").foregroundStyle(palette.secondaryText)
                }
                ForEach(model.visiblePrayers) { prayer in
                    row(prayer)
                }
            }
            .listRowBackground(palette.surface)
        }
        .buttonStyle(.borderless)
    }

    private func row(_ prayer: GroupPrayer) -> some View {
        let prayed = model.prayedFor.contains(prayer.id)
        let mine = community.isMine(prayer.userID)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(prayer.displayName).font(.subheadline.weight(.semibold))
                if prayer.answeredAt != nil {
                    Label("Answered", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(palette.accent)
                }
            }
            Text(prayer.body)
                .foregroundStyle(palette.text)
            HStack(spacing: 16) {
                Button {
                    Task { await model.setPrayed(!prayed, for: prayer) }
                } label: {
                    Label(prayed ? "Prayed" : "I prayed", systemImage: prayed ? "hands.and.sparkles.fill" : "hands.and.sparkles")
                }
                .accessibilityIdentifier("group.prayed")
                if prayer.prayedCount > 0 {
                    Text("\(prayer.prayedCount) praying")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityIdentifier("group.prayedCount")
                }
                Spacer()
                if mine {
                    Button(prayer.answeredAt == nil ? "Mark answered" : "Not answered yet") {
                        Task { await model.setAnswered(prayer.answeredAt == nil, for: prayer) }
                    }
                    .font(.caption)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
        .contentActions(
            .groupPrayer, id: prayer.id, authorName: prayer.displayName, isMine: mine,
            canRemove: mine || (model.group?.isLeader ?? false),
            onRemove: { await model.remove(.groupPrayer, id: prayer.id) },
            onBlock: { await community.block(prayer.userID) },
            onHidden: { model.hide(prayer.id) }
        )
        .accessibilityIdentifier("group.prayer")
    }
}

/// Notes and events from the group's leaders.
struct GroupAnnouncementsView: View {
    let model: GroupDetailModel
    let group: GroupSummary

    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette
    @State private var composing = false

    var body: some View {
        List {
            if group.isLeader {
                Section {
                    Button {
                        composing = true
                    } label: {
                        Label("New Announcement", systemImage: "megaphone")
                    }
                    .accessibilityIdentifier("group.announce")
                } footer: {
                    Text("Members who allow notifications get one.")
                }
                .listRowBackground(palette.surface)
            }
            Section {
                if model.visibleAnnouncements.isEmpty {
                    Text("No announcements yet.").foregroundStyle(palette.secondaryText)
                }
                ForEach(model.visibleAnnouncements) { announcement in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(announcement.title)
                            .font(.headline)
                            .foregroundStyle(palette.text)
                        if !announcement.body.isEmpty {
                            Text(announcement.body).foregroundStyle(palette.text)
                        }
                        Text("\(announcement.displayName) · \(announcement.createdAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                    .padding(.vertical, 4)
                    .contentActions(
                        .groupAnnouncement, id: announcement.id, authorName: announcement.displayName,
                        isMine: community.isMine(announcement.userID),
                        canRemove: community.isMine(announcement.userID) || group.isLeader,
                        onRemove: { await model.remove(.groupAnnouncement, id: announcement.id) },
                        onBlock: { await community.block(announcement.userID) },
                        onHidden: { model.hide(announcement.id) }
                    )
                    .accessibilityIdentifier("group.announcement")
                }
            }
            .listRowBackground(palette.surface)
        }
        .sheet(isPresented: $composing) {
            AnnouncementComposer(model: model)
        }
    }
}

private struct AnnouncementComposer: View {
    let model: GroupDetailModel

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var message = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                    .accessibilityIdentifier("announcement.title")
                TextField("Details (optional)", text: $message, axis: .vertical)
                    .lineLimit(3...8)
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.orange)
                }
            }
            .navigationTitle("Announcement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post", systemImage: "paperplane") {
                        isSending = true
                        Task {
                            if await model.addAnnouncement(title: title, body: message) { dismiss() }
                            isSending = false
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                    .accessibilityIdentifier("announcement.post")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
