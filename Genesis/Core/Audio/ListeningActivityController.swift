import ActivityKit
import Foundation
import UIKit

/// The Lock Screen and Dynamic Island while the Bible is read aloud
/// (Premium): the chapter, the verse being read and play/pause. Started,
/// updated and ended by `AudioPlayerService`.
@MainActor
final class ListeningActivityController {
    /// Checked before starting (Premium, and the person's Listen choice).
    var isAllowed: () -> Bool = { false }

    private var activity: Activity<ListeningActivityAttributes>?
    private var lastState: ListeningActivityAttributes.ContentState?
    /// Swiped away: don't bring it back until listening starts afresh.
    private var swipedAway = false
    /// Couldn't start from the background: try again in the foreground.
    private var waitingForForeground = false
    private var heldBack: Bool { swipedAway || waitingForForeground }

    /// Starts the activity, or updates it if it's already showing.
    func show(_ state: ListeningActivityAttributes.ContentState, translation: String) {
        guard isAllowed(), ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }
        guard state != lastState, !heldBack else { return }
        lastState = state
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity {
            if activity.activityState == .active, activity.attributes.translation == translation {
                let id = activity.id
                Task { await Self.update(id: id, with: content) }
                return
            }
            if activity.activityState != .active {
                // Swiped away: respect that until the next time listening starts.
                self.activity = nil
                swipedAway = true
                return
            }
            dismiss()
        }
        guard UIApplication.shared.applicationState != .background else {
            waitingForForeground = true
            return
        }
        do {
            activity = try Activity.request(attributes: ListeningActivityAttributes(translation: translation), content: content, pushType: nil)
        } catch {
            waitingForForeground = true
        }
    }

    /// Listening stopped: take the activity away and allow a new one next time.
    func end() {
        lastState = nil
        swipedAway = false
        waitingForForeground = false
        dismiss()
    }

    /// The app came to the foreground: a refused start can be tried again.
    func appBecameActive() {
        guard waitingForForeground else { return }
        waitingForForeground = false
        lastState = nil
    }

    private func dismiss() {
        guard let activity else { return }
        self.activity = nil
        let id = activity.id
        Task { await Self.end(ids: [id]) }
    }

    /// Clears activities left over from an earlier run (the app was closed
    /// while listening).
    func endStale() {
        let current = activity?.id
        let stale = Activity<ListeningActivityAttributes>.activities.map(\.id).filter { $0 != current }
        guard !stale.isEmpty else { return }
        Task { await Self.end(ids: stale) }
    }

    // `Activity` isn't Sendable, so it never crosses into a task: these look
    // each one up by id where they run.

    nonisolated private static func update(id: String, with content: ActivityContent<ListeningActivityAttributes.ContentState>) async {
        for activity in Activity<ListeningActivityAttributes>.activities where activity.id == id {
            await activity.update(content)
        }
    }

    nonisolated private static func end(ids: [String]) async {
        for activity in Activity<ListeningActivityAttributes>.activities where ids.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
