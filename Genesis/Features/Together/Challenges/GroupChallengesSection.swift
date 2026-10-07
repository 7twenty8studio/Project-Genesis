import SwiftUI

/// The group page's Challenges: what's running or about to start, a way to
/// finished ones, and (for owners and moderators) a new challenge.
struct GroupChallengesSection: View {
    let groupModel: GroupDetailModel
    let group: GroupSummary

    @Environment(CommunityStore.self) private var community
    @Environment(\.groupChallenges) private var backend
    @Environment(\.palette) private var palette
    @State private var model: GroupChallengesModel?
    @State private var creating = false

    var body: some View {
        Section {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .task { await load() }
            }
        } header: {
            Text("Challenges")
                .task { await load() }
                // Pulling to refresh the group refreshes its challenges too.
                .onChange(of: groupModel.isLoading) { wasLoading, isLoading in
                    if wasLoading, !isLoading, let model { Task { await model.refresh() } }
                }
        }
        .listRowBackground(palette.surface)
    }

    /// Called from the header and the loading row, whichever shows first.
    /// The refresh runs on its own so the loading row going away doesn't
    /// cancel it.
    private func load() async {
        if model == nil {
            model = GroupChallengesModel(groupID: group.id, backend: backend, store: community)
        }
        guard let model, !model.hasLoaded, !model.isLoading else { return }
        await Task { await model.refresh() }.value
    }

    @ViewBuilder
    private func content(_ model: GroupChallengesModel) -> some View {
        if model.current.isEmpty, model.hasLoaded {
            Text(model.canManage ? "Start a challenge to read, memorise or pray together." : "No challenges right now.")
                .foregroundStyle(palette.secondaryText)
        }
        ForEach(model.current) { challenge in
            NavigationLink {
                GroupChallengeDetailView(model: model, groupModel: groupModel, challengeID: challenge.id)
            } label: {
                GroupChallengeRow(model: model, challenge: challenge)
            }
            .accessibilityIdentifier("challenges.row")
        }
        if !model.finished.isEmpty {
            NavigationLink {
                GroupChallengeListView(model: model, groupModel: groupModel)
            } label: {
                Label("Finished Challenges", systemImage: "checkmark.seal")
                    .foregroundStyle(palette.accent)
            }
            .accessibilityIdentifier("challenges.finished")
        }
        if model.canManage {
            newChallengeButton(model)
        }
        if let error = model.errorMessage {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private func newChallengeButton(_ model: GroupChallengesModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                creating = true
            } label: {
                Label("New Challenge", systemImage: "plus.circle")
            }
            .disabled(!model.canStartAnother)
            .accessibilityIdentifier("challenges.new")
            if !model.canStartAnother {
                Text("A group can run up to five challenges at once.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $creating) {
            NewGroupChallengeView(model: model)
        }
    }
}

/// A challenge in a list: what it is, where it's up to, and your progress.
struct GroupChallengeRow: View {
    let model: GroupChallengesModel
    let challenge: GroupChallenge

    @Environment(\.palette) private var palette

    var body: some View {
        let summary = model.summary(for: challenge)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: challenge.kind.systemImage)
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(palette.text)
                Text(ChallengeText.status(challenge, status: model.status(of: challenge), today: model.today(in: challenge)))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                if model.status(of: challenge) == .running {
                    Text(ChallengeText.rowProgress(challenge, summary: summary))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    if challenge.kind == .reading {
                        ProgressView(value: summary.myFraction)
                            .tint(palette.accent)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Words about a challenge, shared by its row and its page.
enum ChallengeText {
    static func status(_ challenge: GroupChallenge, status: GroupChallengeStatus, today: Int) -> String {
        switch status {
        case .upcoming:
            let date = challenge.startDate()?.formatted(date: .abbreviated, time: .omitted) ?? challenge.startDay
            return String(localized: "Starts \(date)")
        case .running:
            let day = min(max(today, 1), challenge.days)
            let total = challenge.days
            return String(localized: "Day \(day) of \(total)")
        case .finished:
            if let endedAt = challenge.endedAt {
                let date = endedAt.formatted(date: .abbreviated, time: .omitted)
                return String(localized: "Ended early \(date)")
            }
            let date = challenge.endDate()?.formatted(date: .abbreviated, time: .omitted) ?? ""
            return String(localized: "Finished \(date)")
        }
    }

    /// One short line of progress for a running challenge's row.
    static func rowProgress(_ challenge: GroupChallenge, summary: GroupChallengeSummary) -> String {
        switch challenge.kind {
        case .reading:
            let count = summary.myDone
            let total = summary.itemCount
            return String(localized: "You've read \(count) of \(total) chapters")
        case .memorise:
            return summary.myDone > 0 ? String(localized: "You've learned it") : String(localized: "Still learning")
        case .streak, .prayer:
            return stillGoing(summary)
        }
    }

    /// "5 of 6 still going" (no ranking, just how many).
    static func stillGoing(_ summary: GroupChallengeSummary) -> String {
        let count = summary.stillGoing
        let total = summary.memberCount
        return total == 1 ? String(localized: "\(count) of 1 still going") : String(localized: "\(count) of \(total) still going")
    }

    /// "Oct 6 – Oct 19".
    static func dates(_ challenge: GroupChallenge) -> String {
        guard let start = challenge.startDate(), let end = challenge.endDate() else { return "" }
        let first = start.formatted(date: .abbreviated, time: .omitted)
        let last = end.formatted(date: .abbreviated, time: .omitted)
        return challenge.days == 1 ? first : "\(first) \u{2013} \(last)"
    }
}
