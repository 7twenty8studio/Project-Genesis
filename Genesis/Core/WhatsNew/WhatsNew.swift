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
    /// The feature people can switch on from the note if they've hidden it.
    var feature: OptionalFeature?
}

enum WhatsNewCatalog {
    /// Oldest first; the sheet shows the newest first.
    static let all: [WhatsNewAnnouncement] = [studyAssistant, audioBible, churchGroups, community, yourWay, spanish, seasons, mapCertainty]

    static let mapCertainty = WhatsNewAnnouncement(
        id: "map-certainty",
        title: String(localized: "How sure is the map?"),
        items: [
            WhatsNewItem(
                systemImage: "checkmark.seal",
                title: String(localized: "Known, likely or uncertain"),
                detail: String(localized: "Every place on the Bible map now shows how sure scholars are of where it was. Uncertain sites have a question mark, and you can hide them from the Journeys menu.")
            ),
        ],
        feature: .explore
    )

    static let seasons = WhatsNewAnnouncement(
        id: "seasonal-themes",
        title: String(localized: "Read through the seasons"),
        items: [
            WhatsNewItem(
                systemImage: "leaf",
                title: String(localized: "Seasonal themes"),
                detail: String(localized: "Autumn, Winter, Spring and Summer, or Seasons to change with the calendar. Leaves, snow, blossom or summer sunlight drift gently across the page as you read. In Aa › Theme, with Premium.")
            ),
            WhatsNewItem(
                systemImage: "doc.richtext",
                title: String(localized: "Textured paper"),
                detail: String(localized: "Premium themes now have the gentle grain and fibres of real book paper.")
            ),
        ]
    )

    static let spanish = WhatsNewAnnouncement(
        id: "spanish",
        title: String(localized: "Genesis in Spanish"),
        items: [
            WhatsNewItem(
                systemImage: "globe",
                title: String(localized: "Genesis en español"),
                detail: String(localized: "Use Genesis in Spanish: Settings › Language (the gear on Home). It follows your iPhone's language too.")
            ),
            WhatsNewItem(
                systemImage: "book",
                title: String(localized: "Reina-Valera 1909"),
                detail: String(localized: "Download the Reina-Valera 1909 from Bibles on This Device › Get More. It's read aloud in a Spanish voice.")
            ),
            WhatsNewItem(
                systemImage: "text.magnifyingglass",
                title: String(localized: "Spanish references"),
                detail: String(localized: "Search and go to passages by their Spanish names too, like Juan 3:16 or Salmos 23.")
            ),
        ]
    )

    static let audioBible = WhatsNewAnnouncement(
        id: "audio-bible",
        title: String(localized: "Listen to the Bible"),
        items: [
            WhatsNewItem(
                systemImage: "headphones",
                title: String(localized: "Listen to any chapter"),
                detail: String(localized: "Tap the headphones in the reader. The page turns and the verse being read is marked as you go, and it keeps playing with your phone locked.")
            ),
            WhatsNewItem(
                systemImage: "person.wave.2",
                title: String(localized: "Choose a voice"),
                detail: String(localized: "Use your device's voices in every translation, offline, or a recorded narration where one is available. Change it under Audio Settings.")
            ),
            WhatsNewItem(
                systemImage: "moon",
                title: String(localized: "Speed and sleep timer"),
                detail: String(localized: "Listen faster or slower, and stop after a set time or at the end of the chapter.")
            ),
        ],
        feature: .listen
    )

    static let yourWay = WhatsNewAnnouncement(
        id: "your-way",
        title: String(localized: "Genesis, your way"),
        items: [
            WhatsNewItem(
                systemImage: "square.grid.2x2",
                title: String(localized: "Choose your features"),
                detail: String(localized: "Keep Genesis as simple as you like: turn listening, plans, explore and more on or off in Settings › Features (the gear on Home).")
            ),
            WhatsNewItem(
                systemImage: "tag",
                title: String(localized: "Search by topic"),
                detail: String(localized: "Search for a subject like forgiveness or fear to see the passages about it.")
            ),
            WhatsNewItem(
                systemImage: "arrow.down.circle",
                title: String(localized: "More Bibles"),
                detail: String(localized: "Download the Berean Standard Bible from the translation menu. Downloads work offline and stay up to date.")
            ),
            WhatsNewItem(
                systemImage: "hands.and.sparkles",
                title: String(localized: "Prayer on your Lock Screen"),
                detail: String(localized: "Add the Prayer Reminder widget to see your next reminder at a glance.")
            ),
        ]
    )

    static let churchGroups = WhatsNewAnnouncement(
        id: "church-groups",
        title: String(localized: "Church groups"),
        items: [
            WhatsNewItem(
                systemImage: "person.3",
                title: String(localized: "Read together"),
                detail: String(localized: "Start a group or join one with an invite code in the new Together tab. Follow a reading plan as a group and see who's kept up.")
            ),
            WhatsNewItem(
                systemImage: "hands.and.sparkles",
                title: String(localized: "Pray for each other"),
                detail: String(localized: "Share prayer requests with your group, tap \"I prayed\", and mark requests answered.")
            ),
            WhatsNewItem(
                systemImage: "megaphone",
                title: String(localized: "Talk and stay in touch"),
                detail: String(localized: "Discuss each day's reading, and get a notification when a leader posts an announcement.")
            ),
        ],
        flag: .groups,
        feature: .together
    )

    static let community = WhatsNewAnnouncement(
        id: "community",
        title: String(localized: "The Genesis community"),
        items: [
            WhatsNewItem(
                systemImage: "hands.and.sparkles",
                title: String(localized: "Prayer wall"),
                detail: String(localized: "Share a prayer request with everyone in Genesis, anonymously if you like, and pray for others.")
            ),
            WhatsNewItem(
                systemImage: "text.quote",
                title: String(localized: "Reflections"),
                detail: String(localized: "Share a short thought on a passage and encourage one another.")
            ),
            WhatsNewItem(
                systemImage: "shield",
                title: String(localized: "Kind and safe"),
                detail: String(localized: "Everyone agrees to the community guidelines. Report or block anyone from the … menu on any post.")
            ),
        ],
        flag: .community,
        feature: .together
    )

    static let studyAssistant = WhatsNewAnnouncement(
        id: "study-assistant",
        title: String(localized: "The study assistant"),
        items: [
            WhatsNewItem(
                systemImage: "sparkles",
                title: String(localized: "Explain a passage"),
                detail: String(localized: "Long-press a verse, then tap Explain for a short, plain-language explanation. Free accounts include \(FreeLimits.aiRequestsPerDay) a day after signing in.")
            ),
            WhatsNewItem(
                systemImage: "text.book.closed",
                title: String(localized: "Study a chapter"),
                detail: String(localized: "Tap the sparkles in the reader for summaries, historical background, discussion questions and more with Premium.")
            ),
            WhatsNewItem(
                systemImage: "checkmark.shield",
                title: String(localized: "Clearly labelled"),
                detail: String(localized: "Answers are AI-generated study notes, shown apart from the text and never in place of Scripture. They don't take sides between traditions.")
            ),
        ],
        flag: .studyAssistant,
        feature: .studyAssistant
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
