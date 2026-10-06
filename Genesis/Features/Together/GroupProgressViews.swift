import SwiftUI

/// Everyone's progress through the group's plan: a bar each, furthest along
/// first, with a tick for who has read today.
struct GroupProgressSection: View {
    let model: GroupDetailModel
    let plan: ReadingPlan
    let today: Int

    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette

    var body: some View {
        Section {
            ForEach(model.progressRows, id: \.member.userID) { row in
                MemberProgressRow(
                    name: community.isMine(row.member.userID) ? String(localized: "You") : row.member.displayName,
                    daysDone: row.progress.daysDone,
                    dayCount: plan.dayCount,
                    readToday: model.readToday.contains(row.member.userID)
                )
            }
            NavigationLink {
                GroupPlanView(model: model, plan: plan, today: today)
            } label: {
                Label("Every Day of the Plan", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(palette.accent)
            }
            .accessibilityIdentifier("group.allDays")
        } header: {
            Text("Progress")
        } footer: {
            Text("Catch up on earlier days and join their discussions from Every Day of the Plan.")
        }
        .listRowBackground(palette.surface)
    }
}

struct MemberProgressRow: View {
    let name: String
    let daysDone: Int
    let dayCount: Int
    let readToday: Bool

    @Environment(\.palette) private var palette

    private var fraction: Double { dayCount > 0 ? min(1, Double(daysDone) / Double(dayCount)) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                if readToday {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(palette.accent)
                        .accessibilityLabel("Read today")
                }
                Spacer()
                Text("\(daysDone) of \(dayCount) days")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
            }
            ProgressView(value: fraction)
                .tint(palette.accent)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("group.memberProgress")
    }
}

/// Every day of the group's plan: what to read, and a way into each day's
/// readers and discussion.
struct GroupPlanView: View {
    let model: GroupDetailModel
    let plan: ReadingPlan
    let today: Int

    @Environment(\.palette) private var palette

    var body: some View {
        List {
            ThemedRows {
                Section {
                    ForEach(plan.days, id: \.number) { day in
                        let isFuture = day.number > today
                        NavigationLink {
                            GroupDayView(model: model, plan: plan, day: day.number)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: model.hasRead(day: day.number) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.hasRead(day: day.number) ? palette.accent : palette.separator)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Day \(day.number)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(day.number == today ? palette.accent : palette.secondaryText)
                                    Text(day.title)
                                        .foregroundStyle(isFuture ? palette.secondaryText : palette.text)
                                }
                                Spacer()
                                let comments = model.posts(forDay: day.number).count
                                if comments > 0 {
                                    Label(String(comments), systemImage: "bubble.left")
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryText)
                                        .accessibilityLabel(comments == 1 ? String(localized: "1 comment") : String(localized: "\(comments) comments"))
                                }
                            }
                        }
                        .accessibilityIdentifier("group.day.\(day.number)")
                    }
                }
            }
        }
        .themedScreen()
        .navigationTitle(plan.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One day of the plan: the reading, who has read it, and its discussion.
struct GroupDayView: View {
    let model: GroupDetailModel
    let plan: ReadingPlan
    let day: Int

    @Environment(AppRouter.self) private var router
    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette

    var body: some View {
        let planDay = plan.days.first { $0.number == day }
        let readers = model.dayReaders[day] ?? []
        List {
            ThemedRows {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(planDay?.title ?? "")
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .foregroundStyle(palette.text)
                        HStack {
                            if let first = planDay?.spans.first?.first {
                                Button {
                                    router.read(first)
                                } label: {
                                    Label("Read", systemImage: "book")
                                }
                                .buttonStyle(.bordered)
                            }
                            Spacer()
                            Button {
                                Task { await model.setRead(!model.hasRead(day: day), day: day) }
                            } label: {
                                Label(model.hasRead(day: day) ? "Done" : "Mark as read", systemImage: model.hasRead(day: day) ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("group.day.markRead")
                        }
                        let names = model.members
                            .filter { readers.contains($0.userID) && !community.blocked.contains($0.userID) }
                            .map { community.isMine($0.userID) ? String(localized: "You") : $0.displayName }
                        Text(names.isEmpty ? String(localized: "No one has marked this day yet.") : String(localized: "Read by \(names.formatted(.list(type: .and)))"))
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 4)
                } header: {
                    Text("Day \(day) of \(plan.dayCount)")
                }
                .listRowBackground(palette.surface)

                DiscussionSection(model: model, day: day)
            }
        }
        .themedScreen()
        .navigationTitle("Day \(day)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadReaders(day: day) }
    }
}
