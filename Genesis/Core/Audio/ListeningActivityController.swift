import ActivityKit
import Foundation

/// The Lock Screen and Dynamic Island while the Bible is read aloud
/// (Premium): the chapter, the verse being read and play/pause. Started,
/// updated and ended by `AudioPlayerService`.
@MainActor
final class ListeningActivityController {
    /// Checked before starting (Premium, and the person's Listen choice).
    var isAllowed: () -> Bool = { false }

    private var activity: Activity<ListeningActivityAttributes>?
    private var lastState: ListeningActivityAttributes.ContentState?

    /// Starts the activity, or updates it if it's already showing.
    func show(_ state: ListeningActivityAttributes.ContentState, translation: String) {
        guard isAllowed(), ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }
        guard state != lastState || activity == nil else { return }
        lastState = state
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity, activity.activityState == .active, activity.attributes.translation == translation {
            Task { await activity.update(content) }
            return
        }
        end()
        do {
            activity = try Activity.request(attributes: ListeningActivityAttributes(translation: translation), content: content, pushType: nil)
        } catch {
            CrashReporter.record(error, context: "LiveActivity.request")
        }
    }

    func end() {
        lastState = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Clears activities left over from an earlier run (the app was closed
    /// while listening).
    func endStale() {
        for stale in Activity<ListeningActivityAttributes>.activities where stale.id != activity?.id {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
