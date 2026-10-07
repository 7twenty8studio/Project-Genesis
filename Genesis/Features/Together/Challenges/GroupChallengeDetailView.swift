import SwiftUI

/// One challenge: what it asks, your progress and the group's, and (for
/// owners and moderators) a way to end it.
struct GroupChallengeDetailView: View {
    let model: GroupChallengesModel
    let groupModel: GroupDetailModel
    let challengeID: UUID

    @State private var confirmsEnd = false

    private var challenge: GroupChallenge? { model.challenge(challengeID) }

    var body: some View {
        Group {
            if let challenge {
                content(challenge)
                    .navigationTitle(challenge.kind.title)
            } else {
                QuietEmptyState(systemImage: "flag.checkered", title: String(localized: "Challenge ended"), message: String(localized: "This challenge has ended."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.canManage, let challenge, model.status(of: challenge) != .finished {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        confirmsEnd = true
                    } label: {
                        Label("End Challenge", systemImage: "flag.checkered")
                    }
                    .accessibilityIdentifier("challenge.end")
                }
            }
        }
        .confirmationDialog("End this challenge?", isPresented: $confirmsEnd, titleVisibility: .visible) {
            Button("End Challenge", role: .destructive) { end() }
                .accessibilityIdentifier("challenge.endConfirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everyone's progress is kept, and it moves to Finished.")
        }
        .task {
            if let challenge { await model.loadProgress(challenge) }
        }
    }

    private func end() {
        guard let challenge else { return }
        Task { await model.end(challenge) }
    }

    private func content(_ challenge: GroupChallenge) -> some View {
        List {
            ThemedRows {
                ChallengeHeaderSection(model: model, challenge: challenge)
                switch challenge.kind {
                case .reading:
                    ReadingChallengeSections(model: model, challenge: challenge)
                case .memorise:
                    MemoriseChallengeSections(model: model, challenge: challenge)
                case .streak, .prayer:
                    DailyChallengeSections(model: model, groupModel: groupModel, challenge: challenge)
                }
                ChallengeMembersSection(model: model, challenge: challenge)
            }
        }
        .refreshable { await model.loadProgress(challenge) }
    }
}

/// The challenge's title, details, dates, and how the group is doing (or,
/// once it's over, a gentle summary).
struct ChallengeHeaderSection: View {
    let model: GroupChallengesModel
    let challenge: GroupChallenge

    @Environment(\.palette) private var palette

    var body: some View {
        let status = model.status(of: challenge)
        let summary = model.summary(for: challenge)
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(challenge.kind.title, systemImage: challenge.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
                Text(challenge.title)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .accessibilityAddTraits(.isHeader)
                if !challenge.details.isEmpty {
                    Text(challenge.details)
                        .foregroundStyle(palette.text)
                }
                Text("\(ChallengeText.dates(challenge)) · \(ChallengeText.status(challenge, status: status, today: model.today(in: challenge)))")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                if status == .finished {
                    Text(Self.finishedSummary(challenge, summary: summary))
                        .font(.callout)
                        .foregroundStyle(palette.text)
                        .accessibilityIdentifier("challenge.summary")
                } else if summary.memberCount > 0 {
                    groupProgress(summary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func groupProgress(_ summary: GroupChallengeSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: summary.groupFraction)
                .tint(palette.accent)
                .accessibilityLabel("Group progress")
            let portion = summary.groupFraction.formatted(.percent.precision(.fractionLength(0)))
            Text("Together, the group is \(portion) of the way there.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
    }

    /// "You finished 14 of 16 chapters." Never a ranking.
    static func finishedSummary(_ challenge: GroupChallenge, summary: GroupChallengeSummary) -> String {
        let count = summary.myDone
        let total = summary.itemCount
        switch challenge.kind {
        case .reading:
            return String(localized: "You finished \(count) of \(total) chapters.")
        case .memorise:
            return count > 0 ? String(localized: "You learned this passage. Well done.") : String(localized: "This passage is still yours to learn.")
        case .streak:
            return String(localized: "You read on \(count) of \(total) days.")
        case .prayer:
            return String(localized: "You prayed on \(count) of \(total) days.")
        }
    }
}

/// Everyone in the group, in name order (you first), with their progress.
struct ChallengeMembersSection: View {
    let model: GroupChallengesModel
    let challenge: GroupChallenge

    @Environment(\.palette) private var palette

    var body: some View {
        let rows = model.memberRows(for: challenge)
        let summary = model.summary(for: challenge)
        Section {
            if rows.isEmpty {
                Text("No one has joined in yet.")
                    .foregroundStyle(palette.secondaryText)
            }
            ForEach(rows, id: \.userID) { row in
                ChallengeMemberRow(
                    name: row.userID == model.me ? String(localized: "You") : row.displayName,
                    detail: detail(row, summary: summary),
                    fraction: challenge.kind == .reading ? GroupChallengeSummary.fraction(done: row.done, of: challenge.itemCount) : nil,
                    isDone: isDone(row, summary: summary)
                )
            }
        } header: {
            Text("Members")
        } footer: {
            Text("No rankings, just encouragement.")
        }
    }

    private func isDone(_ row: ChallengeProgress, summary: GroupChallengeSummary) -> Bool {
        switch challenge.kind {
        case .reading, .memorise: row.done >= challenge.itemCount
        case .streak, .prayer: Set(row.items ?? []).contains(summary.day)
        }
    }

    private func detail(_ row: ChallengeProgress, summary: GroupChallengeSummary) -> String {
        let count = min(row.done, challenge.itemCount)
        let total = challenge.itemCount
        switch challenge.kind {
        case .reading:
            return String(localized: "\(count) of \(total) chapters")
        case .memorise:
            return count > 0 ? String(localized: "Learned it") : String(localized: "Still learning")
        case .streak, .prayer:
            let ticked = Set(row.items ?? [])
            if ChallengeStreak.isAlive(ticked, today: summary.day) {
                return String(localized: "Still going")
            }
            return String(localized: "\(count) of \(total) days")
        }
    }
}

struct ChallengeMemberRow: View {
    let name: String
    let detail: String
    let fraction: Double?
    let isDone: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(palette.accent)
                        .accessibilityLabel("Done")
                }
                Spacer()
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
            }
            if let fraction {
                ProgressView(value: fraction)
                    .tint(palette.accent)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("challenge.member")
    }
}
