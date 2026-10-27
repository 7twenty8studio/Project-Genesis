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
    static let all: [WhatsNewAnnouncement] = [studyAssistant, audioBible, churchGroups, community, yourWay, spanish, seasons, mapCertainty, readAndShare, ambientSounds, memorise, premiumWidgets, octoberUpdate, groupProgress, readingLibrary, freeSyncAndWelcome, studyAndJournal, deluxeEdition, groupChallenges, nightAndOriginalWord, prayerJournalAndSwitches, sermonCompanion, verseWidgetOptions, journalExtras, readAlongOriginal, studyLibrary, hearOriginalWords, notifications, goalsAndStreaks, moreBibles, livelierSkies, tapToSelect, footnotes, backgroundDownloads, slimSelectionBar, verseWallpapers, widgetBackgrounds, keepsakeWidgets, widgetPhotoFraming]

    static let notifications = WhatsNewAnnouncement(
        id: "notifications-your-way",
        title: String(localized: "Notifications, your way"),
        items: [
            WhatsNewItem(
                systemImage: "sun.max",
                title: String(localized: "Verse of the Day"),
                detail: String(localized: "Today's verse each morning, at the time you choose.")
            ),
            WhatsNewItem(
                systemImage: "flame",
                title: String(localized: "Gentle reading reminders"),
                detail: String(localized: "A nudge only on days you haven't read yet, to keep your streak going, plus your plan, Memorize and Sunday sermon notes.")
            ),
            WhatsNewItem(
                systemImage: "bell.slash",
                title: String(localized: "You're in control"),
                detail: String(localized: "Choose each kind and its time, or turn them all off, in Settings › Notifications.")
            ),
        ]
    )

    static let widgetPhotoFraming = WhatsNewAnnouncement(
        id: "widget-photo-framing",
        title: String(localized: "Place your photo"),
        items: [
            WhatsNewItem(
                systemImage: "crop",
                title: String(localized: "Place your photo"),
                detail: String(localized: "In Settings › Widget Photo, tap Adjust Photo to drag and zoom your photo for each widget size.")
            ),
        ]
    )

    static let keepsakeWidgets = WhatsNewAnnouncement(
        id: "keepsake-widgets",
        title: String(localized: "Keepsake widgets"),
        items: [
            WhatsNewItem(
                systemImage: "rectangle.stack",
                title: String(localized: "Six new looks for your verse"),
                detail: String(localized: "With Premium, choose Instant Photo, Pressed Flowers, Film Strip, Typewriter, Library Card or Calendar Page as the verse widget's Background.")
            ),
        ]
    )

    static let widgetBackgrounds = WhatsNewAnnouncement(
        id: "widget-backgrounds",
        title: String(localized: "Widgets with a view"),
        items: [
            WhatsNewItem(
                systemImage: "photo.on.rectangle",
                title: String(localized: "Seasons, a postcard or your photo"),
                detail: String(localized: "Touch and hold the verse widget, tap Edit Widget and choose a Background. Pick your photo in Settings › Widget Photo.")
            ),
        ]
    )

    static let verseWallpapers = WhatsNewAnnouncement(
        id: "verse-wallpapers",
        title: String(localized: "Verse wallpapers"),
        items: [
            WhatsNewItem(
                systemImage: "iphone",
                title: String(localized: "A verse on your Lock Screen"),
                detail: String(localized: "Select a verse, tap Image and choose Lock Screen: the words sit below the clock, on paper, a season, the night sky or your own photo.")
            ),
            WhatsNewItem(
                systemImage: "livephoto",
                title: String(localized: "Wallpapers that move"),
                detail: String(localized: "With Premium, save a seasonal wallpaper as a Live Photo: leaves, petals or snow drift each time your iPhone wakes.")
            ),
            WhatsNewItem(
                systemImage: "square.and.arrow.down",
                title: String(localized: "Save or share it"),
                detail: String(localized: "Save it to Photos to set as your wallpaper, or share it to your stories.")
            ),
        ]
    )

    static let slimSelectionBar = WhatsNewAnnouncement(
        id: "slim-selection-bar",
        title: String(localized: "More page, less bar"),
        items: [
            WhatsNewItem(
                systemImage: "rectangle.bottomthird.inset.filled",
                title: String(localized: "One row of actions"),
                detail: String(localized: "When you select a verse, your favorite colors and every action sit in one row, so the verses below stay in view. Slide it sideways, or swipe up for everything.")
            ),
        ]
    )

    static let backgroundDownloads = WhatsNewAnnouncement(
        id: "background-downloads",
        title: String(localized: "Downloads keep going"),
        items: [
            WhatsNewItem(
                systemImage: "arrow.down.circle",
                title: String(localized: "Leave while a Bible downloads"),
                detail: String(localized: "Start a download and switch apps or lock your iPhone: it carries on, with its progress shown by iOS.")
            ),
        ]
    )

    static let footnotes = WhatsNewAnnouncement(
        id: "footnotes",
        title: String(localized: "Footnotes"),
        items: [
            WhatsNewItem(
                systemImage: "textformat.superscript",
                title: String(localized: "Translators' notes"),
                detail: String(localized: "In Bibles that have them, tap the small letter beside a word to read the translators' note.")
            ),
        ]
    )

    static let tapToSelect = WhatsNewAnnouncement(
        id: "tap-to-select",
        title: String(localized: "One tap to highlight"),
        items: [
            WhatsNewItem(
                systemImage: "hand.tap",
                title: String(localized: "Tap a verse"),
                detail: String(localized: "A single tap selects a verse, ready to highlight, note or share.")
            ),
            WhatsNewItem(
                systemImage: "book.pages",
                title: String(localized: "Turn from the edge"),
                detail: String(localized: "Tap the very edge of the page to turn it, or swipe as before.")
            ),
            WhatsNewItem(
                systemImage: "slider.horizontal.3",
                title: String(localized: "Controls at the top"),
                detail: String(localized: "Tap the top or bottom of the page, or any blank space, to show the reader controls.")
            ),
            WhatsNewItem(
                systemImage: "hand.draw",
                title: String(localized: "Selections stay"),
                detail: String(localized: "Turn the page while choosing verses and they stay selected; swipe the bar down to put it away.")
            ),
        ]
    )

    static let livelierSkies = WhatsNewAnnouncement(
        id: "starlight-shooting-stars",
        title: String(localized: "Skies and seasons that move"),
        items: [
            WhatsNewItem(
                systemImage: "sparkles",
                title: String(localized: "Shooting stars"),
                detail: String(localized: "Starlight's night sky twinkles brighter now, with a shooting star every few seconds above the page.")
            ),
            WhatsNewItem(
                systemImage: "leaf",
                title: String(localized: "Each season its own way"),
                detail: String(localized: "Spring petals ride a breeze, winter snow falls near and far, and autumn leaves drift more gently.")
            ),
            WhatsNewItem(
                systemImage: "accessibility",
                title: String(localized: "Calm with Reduce Motion"),
                detail: String(localized: "With Reduce Motion on, stars fade gently in place and the seasons hold a still picture.")
            ),
        ]
    )

    static let moreBibles = WhatsNewAnnouncement(
        id: "youversion-bibles",
        title: String(localized: "More Bibles, free"),
        items: [
            WhatsNewItem(
                systemImage: "books.vertical",
                title: String(localized: "NIV, NASB and NIrV"),
                detail: String(localized: "Three of the most read English Bibles, free to download and read offline.")
            ),
            WhatsNewItem(
                systemImage: "globe.americas",
                title: String(localized: "NVI, NBLA and LBLA"),
                detail: String(localized: "Loved Spanish Bibles, also free, alongside the Reina-Valera.")
            ),
            WhatsNewItem(
                systemImage: "info.circle",
                title: String(localized: "Good to know"),
                detail: String(localized: "These Bibles come from the YouVersion Platform. Listening isn't available for them yet, and widgets and Premium tools use a public-domain Bible with them.")
            ),
        ]
    )

    static let goalsAndStreaks = WhatsNewAnnouncement(
        id: "goals-shields-milestones",
        title: String(localized: "Goals, shields and milestones"),
        items: [
            WhatsNewItem(
                systemImage: "target",
                title: String(localized: "A daily goal"),
                detail: String(localized: "A chapter or a few minutes a day, with your progress on Home.")
            ),
            WhatsNewItem(
                systemImage: "shield.lefthalf.filled",
                title: String(localized: "Streak shield"),
                detail: String(localized: "One missed day a week no longer breaks your streak.")
            ),
            WhatsNewItem(
                systemImage: "hand.wave",
                title: String(localized: "Nudge a friend"),
                detail: String(localized: "In a group's members, tap the wave to invite someone to read with you today.")
            ),
            WhatsNewItem(
                systemImage: "gift",
                title: String(localized: "Remember answered prayers"),
                detail: String(localized: "A year after a prayer was answered, a reminder to give thanks.")
            ),
        ],
        feature: .goals
    )

    static let hearOriginalWords = WhatsNewAnnouncement(
        id: "original-word-pronunciation",
        title: String(localized: "Hear the Hebrew and Greek"),
        items: [
            WhatsNewItem(
                systemImage: "speaker.wave.2",
                title: String(localized: "Say it aloud"),
                detail: String(localized: "Tap a word in Original (Hebrew & Greek) or Word Study, then the speaker, to hear how it sounds.")
            ),
        ],
        feature: .wordStudy
    )

    static let studyLibrary = WhatsNewAnnouncement(
        id: "study-library-notes-commentaries",
        title: String(localized: "The Study Library"),
        items: [
            WhatsNewItem(
                systemImage: "text.book.closed",
                title: String(localized: "Study notes and a Bible dictionary"),
                detail: String(localized: "Download free study notes, book introductions and a Bible dictionary. Select a verse and tap Study to read them.")
            ),
            WhatsNewItem(
                systemImage: "books.vertical",
                title: String(localized: "Classic commentaries"),
                detail: String(localized: "Matthew Henry, Spurgeon, Calvin, Wesley and more, beside every verse. With Premium.")
            ),
            WhatsNewItem(
                systemImage: "character.magnify",
                title: String(localized: "Fuller Hebrew and Greek lexicons"),
                detail: String(localized: "Brown-Driver-Briggs and Liddell-Scott-Jones in Word Study. With Premium.")
            ),
            WhatsNewItem(
                systemImage: "globe",
                title: String(localized: "Key terms in Spanish"),
                detail: String(localized: "A Spanish dictionary of key Bible words, names and ideas, linked to the verses that use them.")
            ),
        ],
        feature: .studyLibrary
    )

    static let readAlongOriginal = WhatsNewAnnouncement(
        id: "parallel-follow-along-original-only",
        title: String(localized: "Read along, side by side"),
        items: [
            WhatsNewItem(
                systemImage: "text.line.first.and.arrowtriangle.forward",
                title: String(localized: "Follow along in parallel"),
                detail: String(localized: "While you listen, the verse being read is marked and kept on screen in Read in Parallel too.")
            ),
            WhatsNewItem(
                systemImage: "character.book.closed",
                title: String(localized: "Hebrew or Greek only"),
                detail: String(localized: "In Original (Hebrew & Greek), tap Hebrew Only or Greek Only to read the original by itself. With Premium.")
            ),
            WhatsNewItem(
                systemImage: "hands.and.sparkles",
                title: String(localized: "Prayers in one place"),
                detail: String(localized: "Prayer notes have moved into the Prayer Journal, with their passages and dates.")
            ),
            WhatsNewItem(
                systemImage: "character.magnify",
                title: String(localized: "Word Study in the Reina-Valera"),
                detail: String(localized: "Select a verse in the Reina-Valera 1909 and tap Word Study to see the Hebrew or Greek behind it.")
            ),
            WhatsNewItem(
                systemImage: "icloud",
                title: String(localized: "Attachments in your iCloud"),
                detail: String(localized: "Photos, recordings, PDFs and Pencil pages are saved on your device, then synced through your own private iCloud. Add as many as you like.")
            ),
        ]
    )

    static let journalExtras = WhatsNewAnnouncement(
        id: "journal-photos-voice-pdfs-templates",
        title: String(localized: "Richer prayers and sermon notes"),
        items: [
            WhatsNewItem(
                systemImage: "photo.on.rectangle",
                title: String(localized: "Photos and voice recordings"),
                detail: String(localized: "Add photos and voice recordings to a prayer or a sermon; they sync to your other devices through your iCloud.")
            ),
            WhatsNewItem(
                systemImage: "pencil.tip.crop.circle",
                title: String(localized: "Pencil pages"),
                detail: String(localized: "Sketch your sermon notes with Apple Pencil.")
            ),
            WhatsNewItem(
                systemImage: "doc.text",
                title: String(localized: "Templates and PDF export"),
                detail: String(localized: "Start from ACTS, a gratitude list or a sermon outline, and export a beautifully typeset PDF. With Premium.")
            ),
        ],
        feature: .prayer
    )

    static let verseWidgetOptions = WhatsNewAnnouncement(
        id: "verse-widget-your-way",
        title: String(localized: "Your verse, your way"),
        items: [
            WhatsNewItem(
                systemImage: "rectangle.split.2x1",
                title: String(localized: "A larger verse widget, free"),
                detail: String(localized: "The medium Verse of the Day widget is now free, on the Home Screen next to the small one and the Lock Screen.")
            ),
            WhatsNewItem(
                systemImage: "shuffle",
                title: String(localized: "Random verses"),
                detail: String(localized: "Touch and hold the verse widget, tap Edit Widget and choose Random Verse for a new encouraging verse every few hours.")
            ),
            WhatsNewItem(
                systemImage: "sparkles",
                title: String(localized: "Verses for how you feel"),
                detail: String(localized: "With Premium, choose hope, peace, faith, strength, comfort, love, gratitude or guidance, or a verse from what you've read this week.")
            ),
        ]
    )

    static let sermonCompanion = WhatsNewAnnouncement(
        id: "sermon-companion-church-mode",
        title: String(localized: "Take sermon notes"),
        items: [
            WhatsNewItem(
                systemImage: "building.columns",
                title: String(localized: "Sermon Notes"),
                detail: String(localized: "Write down the sermon with the preacher, church and date, attach the verses, and find any sermon again by church, date or search.")
            ),
            WhatsNewItem(
                systemImage: "moon",
                title: String(localized: "Church Mode"),
                detail: String(localized: "A dim, quiet screen that stays awake, with larger text and a quick verse lookup. All free.")
            ),
        ],
        feature: .sermons
    )

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
                detail: String(localized: "Every extra, from Memorize to Hebrew & Greek, now has its own switch in Settings › Features.")
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
                title: String(localized: "Memorize, now with games"),
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
                detail: String(localized: "Choose the font, color, size and alignment, or put the verse on one of your own photos.")
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
        title: String(localized: "Memorize Scripture"),
        items: [
            WhatsNewItem(
                systemImage: "brain.head.profile",
                title: String(localized: "Learn verses by heart"),
                detail: String(localized: "With Premium, select verses and tap Memorize. Flashcards bring each one back just before you'd forget it. Find them on Home.")
            ),
            WhatsNewItem(
                systemImage: "square.text.square",
                title: String(localized: "A Memorize widget"),
                detail: String(localized: "Add the Memorize widget to your Home Screen or Lock Screen to recall a verse at a glance.")
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
        title: String(localized: "Versely in Spanish"),
        items: [
            WhatsNewItem(
                systemImage: "globe",
                title: String(localized: "Versely en español"),
                detail: String(localized: "Use Versely in Spanish: Settings › Language (the gear on Home). It follows your iPhone's language too.")
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
        title: String(localized: "Versely, your way"),
        items: [
            WhatsNewItem(
                systemImage: "square.grid.2x2",
                title: String(localized: "Choose your features"),
                detail: String(localized: "Keep Versely as simple as you like: turn listening, plans, explore and more on or off in Settings › Features (the gear on Home).")
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
        title: String(localized: "The Versely community"),
        items: [
            WhatsNewItem(
                systemImage: "hands.and.sparkles",
                title: String(localized: "Prayer wall"),
                detail: String(localized: "Share a prayer request with everyone in Versely, anonymously if you like, and pray for others.")
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
