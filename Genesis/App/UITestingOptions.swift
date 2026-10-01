import Foundation

/// Launch options used only by the UI test suite (GenesisUITests).
///
/// `-uiTesting` starts from a clean slate: settings and progress are wiped,
/// highlights and notes live in memory, and crash reporting stays off.
/// Other flags put the app into a known state so tests are repeatable:
///
///     -skipOnboarding                 go straight to the app
///     -uiTestingStart 43003016        open the reader at a verse (VerseID raw value)
///     -uiTestingTheme slate           a ReaderTheme raw value
///     -uiTestingReadingMode scroll    page | scroll
///     -uiTestingPageTurn slide        slide | curl
///     -uiTestingPremium               act as a Premium subscriber (default: free)
///     -uiTestingAI                    turn the study assistant on (default: off, like release)
///     -uiTestingWhatsNew              show What's New announcements (default: never)
struct UITestingOptions {
    let isEnabled: Bool
    let skipsOnboarding: Bool
    let startVerse: VerseID?
    let theme: ReaderTheme?
    let readingMode: ReadingMode?
    let pageTurn: PageTurnStyle?
    let isPremium: Bool
    let enablesAI: Bool
    let showsWhatsNew: Bool

    static let current = UITestingOptions(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        isEnabled = arguments.contains("-uiTesting")
        skipsOnboarding = arguments.contains("-skipOnboarding")
        startVerse = value(after: "-uiTestingStart").flatMap(Int.init).map(VerseID.init(rawValue:))
        theme = value(after: "-uiTestingTheme").flatMap(ReaderTheme.init(rawValue:))
        readingMode = value(after: "-uiTestingReadingMode").flatMap(ReadingMode.init(rawValue:))
        pageTurn = value(after: "-uiTestingPageTurn").flatMap(PageTurnStyle.init(rawValue:))
        isPremium = arguments.contains("-uiTestingPremium")
        enablesAI = arguments.contains("-uiTestingAI")
        showsWhatsNew = arguments.contains("-uiTestingWhatsNew")
    }

    /// Wipes saved state. Must run before any store reads UserDefaults.
    func resetPersistentState() {
        guard isEnabled, let bundleID = Bundle.main.bundleIdentifier else { return }
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: bundleID)
        if skipsOnboarding {
            defaults.set(true, forKey: "onboarding.complete")
            defaults.set(Translation.kjv.id, forKey: "library.currentTranslation")
        }
    }

    @MainActor
    func apply(settings: ReaderSettings, router: AppRouter) {
        guard isEnabled else { return }
        if let theme { settings.preferences.theme = theme }
        if let readingMode { settings.preferences.readingMode = readingMode }
        if let pageTurn {
            settings.preferences.pageTurn = pageTurn
            settings.preferences.pageTurnChosen = true
        }
        if let startVerse { router.read(startVerse) }
    }
}
