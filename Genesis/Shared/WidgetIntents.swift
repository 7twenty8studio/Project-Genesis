import ActivityKit
import AppIntents
import Foundation
import WidgetKit

// Shared by the app and the widget extension.

// MARK: - Ticking off today's reading

/// Reading-plan days ticked (or unticked) on a widget, waiting for the app to
/// apply them to the plan. The widget can't open the app's database, so it
/// leaves a note in the App Group and updates its own snapshot straight away.
enum PendingPlanDays {
    struct Change: Codable, Equatable, Sendable {
        let enrollmentID: UUID
        let day: Int
        let completed: Bool
    }

    private static let key = "widget.pendingPlanDays"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.appGroup) }

    static func add(_ change: Change) {
        guard let defaults else { return }
        var changes = load(from: defaults).filter { !($0.enrollmentID == change.enrollmentID && $0.day == change.day) }
        changes.append(change)
        defaults.set(try? JSONEncoder().encode(changes), forKey: key)
    }

    /// Returns the waiting changes and clears them.
    static func take() -> [Change] {
        guard let defaults else { return [] }
        let changes = load(from: defaults)
        defaults.removeObject(forKey: key)
        return changes
    }

    private static func load(from defaults: UserDefaults) -> [Change] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Change].self, from: data)) ?? []
    }
}

/// The tick on the Today's Reading widget.
struct TogglePlanDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Today's Reading"
    static let isDiscoverable = false

    @Parameter(title: "Plan")
    var enrollmentID: String

    @Parameter(title: "Day")
    var day: Int

    @Parameter(title: "Completed")
    var completed: Bool

    init() {}

    init(enrollmentID: UUID, day: Int, completed: Bool) {
        self.enrollmentID = enrollmentID.uuidString
        self.day = day
        self.completed = completed
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: enrollmentID) else { return .result() }
        PendingPlanDays.add(.init(enrollmentID: id, day: day, completed: completed))
        // Show the tick now; the app catches up when it next opens.
        if var snapshot = WidgetSnapshot.load(), var plan = snapshot.plan, plan.enrollmentID == id {
            plan.isTodayComplete = completed
            snapshot.plan = plan
            try? snapshot.save()
        }
        return .result()
    }
}

// MARK: - Listening on the Lock Screen

/// The Live Activity while the Bible is read aloud: the chapter, the verse
/// being read (verbatim from the database) and play/pause.
struct ListeningActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var reference: String
        var verseText: String?
        var isPlaying: Bool
        /// 0...1 through the chapter, when known.
        var progress: Double?
    }

    var translation: String
}

/// Hands Live Activity buttons to the app's audio player. The intent runs in
/// the app's process, where the app sets these.
@MainActor
enum ListeningControl {
    static var toggle: (() -> Void)?
    static var next: (() -> Void)?
}

struct ToggleListeningIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or Pause Listening"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        ListeningControl.toggle?()
        return .result()
    }
}

struct NextChapterIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next Chapter"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        ListeningControl.next?()
        return .result()
    }
}
