import SwiftUI

/// Groups you've asked to join, waiting for approval, with Withdraw.
/// Shows nothing when there are none.
struct PendingJoinRequestsSection: View {
    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette

    var body: some View {
        if !community.joinRequests.isEmpty {
            Section {
                ForEach(community.joinRequests) { request in
                    row(request)
                }
            } header: {
                Text("Waiting to Join")
            } footer: {
                Text("You'll be let in once your request is approved.")
            }
            .listRowBackground(palette.surface)
        }
    }

    private func row(_ request: GroupJoinRequest) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(community.requestedGroupName(request))
                    .font(.headline)
                    .foregroundStyle(palette.text)
                Text("Asked \(request.createdAt.formatted(.relative(presentation: .named))).")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            Button("Withdraw") {
                Task { await community.withdrawJoinRequest(request) }
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("groups.withdrawRequest")
        }
        .padding(.vertical, 2)
    }
}
