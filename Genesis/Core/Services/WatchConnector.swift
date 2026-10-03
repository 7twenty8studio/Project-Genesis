import Foundation
import WatchConnectivity

/// Sends the verses of the day to the Genesis app on Apple Watch (Premium).
/// The watch keeps the latest copy, so it works when the phone is away.
@MainActor
final class WatchConnector: NSObject {
    static let shared = WatchConnector()

    private var latest: WatchPayload?
    private var lastSent: WatchPayload?
    private var isActivated = false

    /// Starts WatchConnectivity (no-op on iPads and phones without a watch).
    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(_ payload: WatchPayload) {
        latest = payload
        flush()
    }

    private func flush() {
        guard isActivated, let latest, WCSession.isSupported() else { return }
        if let lastSent, lastSent.isPremium == latest.isPremium, lastSent.translation == latest.translation, lastSent.verses == latest.verses {
            return
        }
        let session = WCSession.default
        guard session.isPaired, session.isWatchAppInstalled else { return }
        do {
            let data = try JSONEncoder().encode(latest)
            try session.updateApplicationContext([WatchPayload.contextKey: data])
            lastSent = latest
        } catch {
            CrashReporter.record(error, context: "Watch.updateApplicationContext")
        }
    }

    fileprivate func activated() {
        isActivated = true
        lastSent = nil
        flush()
    }
}

extension WatchConnector: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in WatchConnector.shared.activated() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another watch: activate again for the new one.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in WatchConnector.shared.activated() }
    }
}
