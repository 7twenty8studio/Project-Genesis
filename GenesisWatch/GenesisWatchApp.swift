import SwiftUI
import WatchConnectivity
import WidgetKit

/// Genesis on Apple Watch: the verse of the day, sent from the iPhone
/// (Premium). Verses are verbatim from the Bible on the phone.
@main
struct GenesisWatchApp: App {
    @State private var store = WatchVerseStore()

    var body: some Scene {
        WindowGroup {
            TodayVerseView()
                .environment(store)
        }
        // New verses from the phone while the app isn't open: take them, so
        // the complication updates.
        .backgroundTask(.watchConnectivity) { [store] in
            await store.receivePendingContent()
        }
    }
}

/// The verses the phone sent, kept on the watch for its app and complications.
@MainActor
@Observable
final class WatchVerseStore: NSObject {
    private(set) var payload: WatchPayload?

    override init() {
        payload = WatchPayload.load()
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Waits (briefly) for WatchConnectivity to deliver what's queued.
    func receivePendingContent() async {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState != .activated { session.activate() }
        for _ in 0..<20 where session.activationState != .activated || session.hasContentPending {
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    fileprivate func received(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(WatchPayload.self, from: data), payload != self.payload else { return }
        self.payload = payload
        try? payload.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WatchVerseStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // The last context sent while the watch app wasn't running.
        guard let data = session.receivedApplicationContext[WatchPayload.contextKey] as? Data else { return }
        Task { @MainActor in self.received(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchPayload.contextKey] as? Data else { return }
        Task { @MainActor in self.received(data) }
    }
}

struct TodayVerseView: View {
    @Environment(WatchVerseStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Genesis")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let payload = store.payload, !payload.isPremium {
            message(
                systemImage: "lock",
                text: String(localized: "The verse of the day on Apple Watch is part of Genesis Premium. Subscribe in Genesis on your iPhone.")
            )
        } else if let payload = store.payload, let verse = payload.verse(on: .now) {
            Text("Verse of the Day")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verse.text)
                .font(.system(.body, design: .serif))
            Text("\(verse.reference) · \(payload.translation)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
        } else {
            message(systemImage: "iphone", text: String(localized: "Open Genesis on your iPhone to bring the verse of the day to your watch."))
        }
    }

    private func message(systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
            Text(text)
                .font(.footnote)
        }
    }
}
