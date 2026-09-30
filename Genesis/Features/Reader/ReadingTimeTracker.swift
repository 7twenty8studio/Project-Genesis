import SwiftUI

/// Counts time while the reader is on screen and the app is in front, for
/// reading insights. Stored on the device only.
private struct ReadingTimeTracker: ViewModifier {
    @Environment(ReadingProgress.self) private var progress
    @Environment(\.scenePhase) private var scenePhase
    @State private var since: Date?
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                if scenePhase == .active { since = .now }
            }
            .onDisappear {
                isVisible = false
                flush()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    if isVisible, since == nil { since = .now }
                } else {
                    flush()
                }
            }
    }

    private func flush() {
        guard let since else { return }
        progress.addReadingTime(Date.now.timeIntervalSince(since))
        self.since = nil
    }
}

extension View {
    func tracksReadingTime() -> some View { modifier(ReadingTimeTracker()) }
}
