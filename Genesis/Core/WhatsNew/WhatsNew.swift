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
    static let all: [WhatsNewAnnouncement] = [studyAssistant, audioBible, churchGroups, community, yourWay, spanish, seasons, mapCertainty, readAndShare, ambientSounds, memorise, premiumWidgets, octoberUpdate, groupProgress, readingLibrary, freeSyncAndWelcome, studyAndJournal, deluxeEdition, groupChallenges, nightAndOriginalWord, prayerJournalAndSwitches]

    static let prayerJournalAndSwitches = WhatsNewAnnouncement(
        id: "prayer-journal-timeline-feature-switches",
        title: String(localized: "A fuller prayer journal"),
        items: [
            WhatsNewItem(
                systemImage: "calendar.day.timeline.left",
                title: String(localized: "Your prayers as a timeline"),
                detail: String(localized: "See what you asked and how God answered, month by month, and search your journal.")
            ),
            WhatsNewItem(
                systemImage: "book.closed",
                title: String(localized: "Pray with Scripture"),
                detail: String(localized: "Attach verses to a prayer, or select verses in the reader and tap Pray.")
            ),
            WhatsNewItem(
                systemImage: "flame",
                title: String(localized: "A gentle streak"),
                detail: String(localized: "See the days in a row you've prayed and a few numbers about your prayer life. All free.")
            ),
            WhatsNewItem(
                systemImage: "square.grid.2x2",
                title: String(localized: "Switch off anything you don't use"),
                detail: String(localized: "Every extra, from Memorise to Hebrew & Greek, now has its own switch in Settings › Features.")
            ),
        ],
        feature: .prayer
    )

    static let nightAndOriginalWord = WhatsNewAnnouncement(
        id: "night-reading-original-word",
        title: String(localized: "Read by night, look deeper"),
        items: [
            WhatsNewItem(
                systemImage: "moon.stars",
                title: String(localized: "Night reading"),
                detail: String(localized: "A soft Night page switches on in the evening, or read under the stars with Starlight.")
            ),
            WhatsNewItem(
                systemImage: "character.book.closed",
                title: String(localized: "The original word"),
                detail: String(localized: "Read the Hebrew and Greek beside your Bible, word by word, and tap any word for its meaning.")
            ),
        ]
    )

    static let groupChallenges = WhatsNewAnnouncement(
        id: "group-challenges-moderators",
        title: String(localized: "Grow together"),
        items: [
            WhatsNewItem(
                systemImage: "flag.checkered",
                title: String(localized: "Group challenges"),
                detail: String(localized: "Read a book together, learn a passage, keep a reading streak or pray every day as a group.")
            ),
            WhatsNewItem(
                systemImage: "person.badge.shield.checkmark",
                title: String(localized: "Owners and moderators"),
                detail: String(localized: "Group owners can choose moderators, approve new members, and review anything reported.")
            ),
        ],
        flag: .groups,
        feature: .together
    )

    static let deluxeEdition = WhatsNewAnnouncement(
        id: "memorise-games-sanctuary-look",
        title: String(localized: "A deluxe edition"),
        items: [
            WhatsNewItem(
                systemImage: "gamecontroller",
                title: String(localized: "Memorise, now with games"),
                detail: String(localized: "Fill the gaps, put the words in order, or try a one-minute speed round, and grow from Seed to Cedar.")
            ),
            WhatsNewItem(
                systemImage: "textformat.alt",
                title: String(localized: "Illuminated letters and new fonts"),
                detail: String(localized: "With Premium, chapters can open with an illuminated letter, in one of three new book fonts.")
            ),
        ]
    )

    static let studyAndJournal = WhatsNewAnnouncement(
        id: "word-study-handwriting-touches",
        title: String(localized: "Study deeper, write freely"),
        items: [
            WhatsNewItem(
                systemImage: "character.book.closed",
                title: String(localized: "Word study and commentary"),
                detail: String(localized: "Select a verse and tap Word Study to see its Hebrew or Greek, Strong's definitions and Matthew Henry's commentary.")
            ),
            WhatsNewItem(
                systemImage: "pencil.tip",
                title: String(localized: "Handwritten journaling"),
                detail: String(localized: "Write or sketch in any note with Apple Pencil or your finger, and start a journal entry from a gentle prompt.")
            ),
            WhatsNewItem(
                systemImage: "textformat.size.larger",
                title: String(localized: "Reading touches"),
                detail: String(localized: "Each chapter opens with a large first letter, and pages can turn with a soft sound and tap (Aa in the reader).")
            ),
        ]
    )

    static let freeSyncAndWelcome = WhatsNewAnnouncement(
        id: "free-sync-explore-welcome",
        title: String(localized: "More for everyone"),
        items: [
            WhatsNewItem(
                systemImage: "icloud",
                title: String(localized: "Sync is now free"),
                detail: String(localized: "Sign in to keep your highlights, notes, plans and prayers on all your devices.")
            ),
            WhatsNewItem(
                systemImage: "person.2",
                title: String(localized: "Explore the timeline and people"),
                detail: String(localized: "Browse the story of Scripture and more than 3,000 people, free.")
            ),
            WhatsNewItem(
                systemImage: "sun.horizon",
                title: String(localized: "A morning welcome"),
                detail: String(localized: "With Premium, start each day with today's verse and reading, and your sounds easing in.")
            ),
        ]
    )

    static let readingLibrary = WhatsNewAnnouncement(
        id: "reading-library",
        title: String(localized: "Find the right Bible"),
        items: [
            WhatsNewItem(
                systemImage: "books.vertical",
                title: String(localized: "Bibles by language"),
                detail: String(localized: "The Bibles screen now groups translations by language, with the most read first.")
            ),
            WhatsNewItem(
                systemImage: "text.word.spacing",
                title: String(localized: "Know what you're choosing"),
                detail: String(localized: "See how each Bible is translated, how it reads, its audio, and whether it's public domain.")
            ),
            WhatsNewItem(
                systemImage: "questionmark.circle",
                title: String(localized: "Which Bible is right for me?"),
                detail: String(localized: "A short guide explains the differences and suggests a Bible for study, everyday reading or reading aloud.")
            ),
        ]
    )

    static let groupProgress = WhatsNewAnnouncement(
        id: "group-progress",
        title: String(localized: "Read together"),
        items: [
            WhatsNewItem(
                systemImage: "chart.bar.fill",
                title: String(localized: "See how your group is doing"),
                detail: String(localized: "A group with a reading plan now shows everyone's progress, with a tick for who has read today.")
            ),
            WhatsNewItem(
                systemImage: "bubble.left.and.bubble.right",
                title: String(localized: "Every day has its discussion"),
                detail: String(localized: "Catch up on earlier days and talk about each one from Every Day of the Plan.")
            ),
            WhatsNewItem(
                systemImage: "square.text.square",
                title: String(localized: "A Group Progress widget"),
                detail: String(localized: "With Premium, keep your group's reading on your Home Screen.")
            ),
        ],
        flag: .groups,
        feature: .together
    )

    static let octoberUpdate = WhatsNewAnnouncement(
        id: "images-fonts-feedback",
        title: String(localized: "Your verse images, your way"),
        items: [
            WhatsNewItem(
                systemImage: "photo.on.rectangle",
                title: String(localized: "More ways to make verse images"),
                detail: String(localized: "Choose the font, colour, size and alignment, or put the verse on one of your own photos.")
            ),
            WhatsNewItem(
                systemImage: "textformat",
                title: String(localized: "Two new reading fonts"),
                detail: String(localized: "Literata and EB Garamond, in the reader under Aa › Font.")
            ),
            WhatsNewItem(
                systemImage: "envelope",
                title: String(localized: "Tell us what you think"),
                detail: String(localized: "Report a problem or share an idea from Settings › Send Feedback. Theme and listening settings are there too.")
            ),
        ]
    )

    static let premiumWidgets = WhatsNewAnnouncement(
        id: "premium-widgets",
        title: String(localized: "More widgets"),
        items: [
            WhatsNewItem(
                systemImage: "checklist",
                title: String(localized: "Tick off today's reading"),
                detail: String(localized: "With Premium, the Today's Reading widget shows your plan's reading and lets you mark it read without opening the app.")
            ),
            WhatsNewItem(
                systemImage: "headphones",
                title: String(localized: "Listening on the Lock Screen"),
                detail: String(localized: "While the Bible is read aloud, the Lock Screen and Dynamic Island show the verse being read, with play and pause.")
            ),
        ]
    )

    static let memorise = WhatsNewAnnouncement(
        id: "memorise-scripture",
        title: String(localized: "Memorise Scripture"),
        items: [
            WhatsNewItem(
                systemImage: "brain.head.profile",
                title: String(localized: "Learn verses by heart"),
                detail: String(localized: "With Premium, select verses and tap Memorise. Flashcards bring each one back just before you'd forget it. Find them on Home.")
            ),
            WhatsNewItem(
                systemImage: "square.text.square",
                title: String(localized: "A Memorise widget"),
                detail: String(localized: "Add the Memorise widget to your Home Screen or Lock Screen to recall a verse at a glance.")
            ),
        ],
        feature: .memorise
    )

    static let ambientSounds = WhatsNewAnnouncement(
        id: "ambient-sounds",
        title: String(localized: "Ambient sounds"),
        items: [
            WhatsNewItem(
                systemImage: "speaker.wave.2",
                title: String(localized: "Read with rain, waves or a fire"),
                detail: String(localized: "With Premium, mix rain, ocean waves, wind, a crackling fire, birdsong and a soft worship pad while you read and pray. Find them in the reader under Aa.")
            ),
            WhatsNewItem(
                systemImage: "timer",
                title: String(localized: "A timer that fades out"),
                detail: String(localized: "Set a timer and the sounds fade gently away, for reading before sleep.")
            ),
        ],
        feature: .ambientSounds
    )

    static let readAndShare = WhatsNewAnnouncement(
        id: "parallel-images-icons-review",
        title: String(localized: "Read side by side, share beautifully"),
        items: [
            WhatsNewItem(
                systemImage: "rectangle.split.2x1",
                title: String(localized: "Parallel Bibles"),
                detail: String(localized: "Read two translations side by side, verse by verse. Tap the translation in the reader, then Read in Parallel. On the open iPhone Duo each gets its own screen.")
            ),
            WhatsNewItem(
                systemImage: "photo",
                title: String(localized: "Verse images"),
                detail: String(localized: "Select a verse and tap Image to make a picture to share, on paper or with the seasons.")
            ),
            WhatsNewItem(
                systemImage: "app.badge",
                title: String(localized: "App icons"),
                detail: String(localized: "Choose a Night or seasonal icon, or let it change with the seasons, in Settings › App Icon.")
            ),
            WhatsNewItem(
                systemImage: "sparkles",
                title: String(localized: "Year in Review"),
                detail: String(localized: "Look back on your year of reading, highlights and prayer, from Insights, and on Home in December and January.")
            ),
        ]
    )

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
