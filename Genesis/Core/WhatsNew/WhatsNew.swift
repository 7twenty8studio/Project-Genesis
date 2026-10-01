import Foundation

/// One line in the What's New sheet.
struct WhatsNewItem: Identifiable, Hashable, Sendable {
    let systemImage: String
    let title: String
    let detail: String
    var id: String { title }
}

/// A one-time note about something new. Each is shown once per device.
///
/// To announce a feature, add one to `WhatsNewCatalog.all` with a new `id`
/// (never reuse or change an id, or people see it again):
/// - a feature that ships in an app update: leave `flag` nil. People who
///   install after it ships don't see it; they meet the feature fresh.
/// - a feature turned on from Supabase: set `flag`. It's shown the first time
///   the app sees that switch on.
struct WhatsNewAnnouncement: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let items: [WhatsNewItem]
    var flag: FeatureFlag?
}

enum WhatsNewCatalog {
    /// Oldest first; the sheet shows the newest first.
    static let all: [WhatsNewAnnouncement] = [studyAssistant]

    static let studyAssistant = WhatsNewAnnouncement(
        id: "study-assistant",
        title: "The study assistant",
        items: [
            WhatsNewItem(
                systemImage: "sparkles",
                title: "Explain a passage",
                detail: "Long-press a verse, then tap Explain for a short, plain-language explanation. Free accounts include \(FreeLimits.aiRequestsPerDay) a day after signing in."
            ),
            WhatsNewItem(
                systemImage: "text.book.closed",
                title: "Study a chapter",
                detail: "Tap the sparkles in the reader for summaries, historical background, discussion questions and more with Premium."
            ),
            WhatsNewItem(
                systemImage: "checkmark.shield",
                title: "Clearly labelled",
                detail: "Answers are AI-generated study notes, shown apart from the text and never in place of Scripture. They don't take sides between traditions."
            ),
        ],
        flag: .studyAssistant
    )
}

/// Remembers which announcements this device has seen and works out which to
/// show next.
@MainActor
@Observable
final class WhatsNewService {
    private(set) var seen: Set<String>

    @ObservationIgnored private let catalog: [WhatsNewAnnouncement]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isEnabled: Bool
    private static let storageKey = "whatsNew.seen"

    /// `isEnabled` is false in UI tests (unless they ask for it), so the sheet
    /// never covers the screen a test expects.
    init(catalog: [WhatsNewAnnouncement] = WhatsNewCatalog.all, defaults: UserDefaults = .standard, isEnabled: Bool = true) {
        self.catalog = catalog
        self.defaults = defaults
        self.isEnabled = isEnabled
        seen = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    /// Unseen announcements whose feature is available, newest first.
    func pending(flags: FeatureFlagService) -> [WhatsNewAnnouncement] {
        guard isEnabled else { return [] }
        return catalog.reversed().filter { announcement in
            guard !seen.contains(announcement.id) else { return false }
            guard let flag = announcement.flag else { return true }
            return flags.isOn(flag)
        }
    }

    func markSeen(_ announcements: [WhatsNewAnnouncement]) {
        seen.formUnion(announcements.map(\.id))
        defaults.set(seen.sorted(), forKey: Self.storageKey)
    }

    /// A new install: features that shipped with the app aren't news. Switched
    /// features are still announced when they turn on.
    func markShippedFeaturesSeen() {
        markSeen(catalog.filter { $0.flag == nil })
    }
}
