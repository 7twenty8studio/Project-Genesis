import SwiftUI

/// Every challenge in the group: running, starting soon and finished.
struct GroupChallengeListView: View {
    let model: GroupChallengesModel
    let groupModel: GroupDetailModel

    @Environment(\.palette) private var palette

    var body: some View {
        List {
            ThemedRows {
                section(String(localized: "Running"), model.running)
                section(String(localized: "Starting Soon"), model.upcoming)
                section(String(localized: "Finished"), model.finished)
                if model.challenges.isEmpty {
                    Text("No challenges yet.")
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .themedScreen()
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private func section(_ title: String, _ challenges: [GroupChallenge]) -> some View {
        if !challenges.isEmpty {
            Section {
                ForEach(challenges) { challenge in
                    NavigationLink {
                        GroupChallengeDetailView(model: model, groupModel: groupModel, challengeID: challenge.id)
                    } label: {
                        GroupChallengeRow(model: model, challenge: challenge)
                    }
                    .accessibilityIdentifier("challenges.row")
                }
            } header: {
                Text(title)
            }
        }
    }
}
