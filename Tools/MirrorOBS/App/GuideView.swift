import SwiftUI

/// The first-run guide (and Help): three pages, then Done.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let pages: [(symbol: String, title: String, text: String)] = [
        ("number.square", "1. Join the room",
         "Whoever runs OBS opens OBS Sharing on 7twenty8studio.com and gets a room code. Type it under Room. Mirror OBS remembers it for next time."),
        ("record.circle", "2. Start Broadcast",
         "Tap Start Broadcast, then Start Broadcast again in the sheet iOS shows. After 3 seconds everything on this screen goes to OBS, in any app. A red pill at the top means it's live."),
        ("rectangle.on.rectangle", "3. Show it in OBS",
         "In OBS add a Browser source with this iPhone's OBS link (Copy OBS link), sized 500 × 1080. Or find this iPhone on the host page. To stop, tap the red pill and Stop."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 22) {
                        Spacer()
                        Image(systemName: pages[i].symbol)
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(Studio.copper)
                        Text(pages[i].title)
                            .font(.title2.bold())
                        Text(pages[i].text)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 28)
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation(.easeOut(duration: 0.25)) { page += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Studio.ink)
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }
}
