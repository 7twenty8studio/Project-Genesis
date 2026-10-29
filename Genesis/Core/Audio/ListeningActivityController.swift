import ActivityKit
import Foundation
import UIKit

/// The Lock Screen and Dynamic Island while the Bible is read aloud or
/// ambient sounds play (Premium): one activity with a row for each, so both
/// can be paused when they play together. `AudioPlayerService` sets the
/// listening row and `AmbientSoundService` the ambient one; the activity
/// ends when neither is left.
@MainActor
final class ListeningActivityController {
    typealias State = ListeningActivityAttributes.ContentState

    /// Checked before showing each row (Premium, and the person's choices).
    var allowsListening: () -> Bool = { false }
    var allowsAmbient: () -> Bool = { false }

    private var listening: ListeningActivityAttributes.Listening?
    private var ambient: ListeningActivityAttributes.Ambient?

    private var activity: Activity<ListeningActivityAttributes>?
    private var lastState: State?
    /// Swiped away: don't bring it back until something starts afresh.
    private var swipedAway = false
    /// Couldn't start from the background: try again in the foreground.
    private var waitingForForeground = false
    private var heldBack: Bool { swipedAway || waitingForForeground }

    /// The Bible being read aloud: shows or updates its row.
    func showListening(_ state: ListeningActivityAttributes.Listening) {
        guard allowsListening() else {
            endListening()
            return
        }
        if listening == nil { swipedAway = false }
        listening = state
        refresh()
    }

    /// Listening stopped: its row goes (the activity too, if nothing else plays).
    func endListening() {
        guard listening != nil else { return }
        listening = nil
        refresh()
    }

    /// Ambient sounds playing or paused: shows or updates their row.
    func showAmbient(_ state: ListeningActivityAttributes.Ambient) {
        guard allowsAmbient() else {
            endAmbient()
            return
        }
        if ambient == nil { swipedAway = false }
        ambient = state
        refresh()
    }

    /// The ambient sounds were closed.
    func endAmbient() {
        guard ambient != nil else { return }
        ambient = nil
        refresh()
    }

    /// The app came to the foreground: a refused start can be tried again.
    func appBecameActive() {
        guard waitingForForeground else { return }
        waitingForForeground = false
        lastState = nil
        refresh()
    }

    private func refresh() {
        let state = State(listening: listening, ambient: ambient)
        guard !state.isEmpty, ActivityAuthorizationInfo().areActivitiesEnabled else {
            // Nothing plays: take the activity away and allow a new one next time.
            lastState = nil
            swipedAway = false
            waitingForForeground = false
            dismiss()
            return
        }
        guard state != lastState, !heldBack else { return }
        lastState = state
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity {
            if activity.activityState == .active {
                let id = activity.id
                Task { await Self.update(id: id, with: content) }
                return
            }
            // Swiped away: respect that until something starts afresh.
            self.activity = nil
            swipedAway = true
            return
        }
        guard UIApplication.shared.applicationState != .background else {
            waitingForForeground = true
            return
        }
        do {
            activity = try Activity.request(attributes: ListeningActivityAttributes(), content: content, pushType: nil)
        } catch {
            waitingForForeground = true
        }
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

    nonisolated private static func update(id: String, with content: ActivityContent<State>) async {
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
