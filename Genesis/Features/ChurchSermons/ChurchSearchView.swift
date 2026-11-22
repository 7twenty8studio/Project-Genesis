import SwiftUI

/// Find a church's sermons by its name: only churches that chose to be
/// listed, and only the sermons anyone with their link may read. No
/// location is asked for or sent.
struct ChurchSearchView: View {
    @Environment(\.churchSermons) private var backend
    @Environment(HiddenChurches.self) private var hidden
    @Environment(\.palette) private var palette
    @State private var query = ""
    @State private var results: [SermonChurch] = []
    @State private var searched = false
    @State private var errorMessage: String?

    var body: some View {
        let shown = results.filter { !hidden.isHidden($0.id) }
        List {
            ThemedRows {
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    Section {
                        Text("Search for your church by its name. Only churches that chose to be listed appear, with the sermons they've shared by link.")
                            .foregroundStyle(palette.secondaryText)
                    }
                } else if searched, shown.isEmpty {
                    Section {
                        Text("No listed church matches \u{201C}\(query)\u{201D}. Ask your church for its sermon link or QR code.")
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                ForEach(shown) { church in
                    Section {
                        if church.sermons.isEmpty {
                            Text("No sermons shared by link yet.")
                                .foregroundStyle(palette.secondaryText)
                        }
                        ForEach(church.sermons) { sermon in
                            NavigationLink(value: TogetherRoute.sermon(sermon.slug)) {
                                ChurchSermonRow(sermon: sermon)
                            }
                            .accessibilityIdentifier("churchSearch.sermon")
                        }
                    } header: {
                        Text(church.name)
                    }
                    .listRowBackground(palette.surface)
                }
            }
        }
        .themedScreen()
        .navigationTitle("Find a Church")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Church or ministry name"))
        .task(id: query) { await search() }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            searched = false
            return
        }
        // Wait for a pause in typing.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            results = try await backend.searchChurches(trimmed)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = CommunityError.from(error).errorDescription
        }
        searched = true
    }
}
