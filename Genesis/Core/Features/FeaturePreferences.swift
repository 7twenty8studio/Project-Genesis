import Foundation

/// Parts of Genesis people can switch off for a simpler app. Reading, notes,
/// highlights, bookmarks, search and the Bibles library are always there.
/// Every optional feature gets its own case (see CLAUDE.md, Feature choices).
enum OptionalFeature: String, CaseIterable, Identifiable, Codable, Sendable {
    case plans
    case prayer
    case memorise
    case listen
    case ambientSounds
    case wordStudy
    case explore
    case studyAssistant
    case insights
    case moments
    case together
    case sermons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plans: String(localized: "Reading Plans")
        case .prayer: String(localized: "Prayer Journal")
        case .memorise: String(localized: "Memorize Scripture")
        case .listen: String(localized: "Listen", comment: "Optional feature: hear chapters read aloud")
        case .ambientSounds: String(localized: "Ambient Sounds")
        case .wordStudy: String(localized: "Hebrew & Greek", comment: "Optional feature: the original-language Bible and word study")
        case .explore: String(localized: "Timeline, Maps & People")
        case .studyAssistant: String(localized: "Study Notes")
        case .insights: String(localized: "Insights & Year in Review")
        case .moments: String(localized: "Chapter Ribbons", comment: "Optional feature: a gold ribbon when a chapter or plan day is finished")
        case .together: String(localized: "Groups & Community")
        case .sermons: String(localized: "Sermon Notes")
        }
    }

    var detail: String {
        switch self {
        case .plans: String(localized: "Read the whole Bible in a year, or a book at a time, with today's reading on Home.")
        case .prayer: String(localized: "A private journal of what you're praying for and how God answered.")
        case .memorise: String(localized: "Learn verses by heart with flashcards and short games.")
        case .listen: String(localized: "Hear any chapter read aloud, with the page following along.")
        case .ambientSounds: String(localized: "Rain, waves, a fire or birdsong while you read and pray.")
        case .wordStudy: String(localized: "The original-language Bible beside yours, and Word Study for any verse.")
        case .explore: String(localized: "Explore the Bible's story, places and people.")
        case .studyAssistant: String(localized: "Short explanations of a passage, clearly labelled as AI-generated.")
        case .insights: String(localized: "Your reading time, favorite books and a look back on your year.")
        case .moments: String(localized: "A small gold ribbon when you finish a chapter or a day of your plan.")
        case .together: String(localized: "Read and pray with your church group, and the community prayer wall.")
        case .sermons: String(localized: "Take notes during the sermon, with the verses beside them and Church Mode for a dim, quiet screen.")
        }
    }

    var systemImage: String {
        switch self {
        case .plans: "calendar"
        case .prayer: "hands.and.sparkles"
        case .memorise: "brain.head.profile"
        case .listen: "headphones"
        case .ambientSounds: "speaker.wave.2"
        case .wordStudy: "character.book.closed"
        case .explore: "map"
        case .studyAssistant: "sparkles"
        case .insights: "chart.bar"
        case .moments: "bookmark"
        case .together: "person.3"
        case .sermons: "building.columns"
        }
    }

    /// How Settings › Features groups the switches.
    enum Area: String, CaseIterable, Identifiable, Sendable {
        case daily, study, listening, community, touches

        var id: String { rawValue }

        var title: String {
            switch self {
            case .daily: String(localized: "Daily Rhythm", comment: "Settings › Features section: plans, prayer, memorizing")
            case .study: String(localized: "Study", comment: "Settings › Features section")
            case .listening: String(localized: "Listening & Sounds", comment: "Settings › Features section: listening and ambient sounds")
            case .community: String(localized: "Together", comment: "Settings › Features section: groups and community")
            case .touches: String(localized: "Little Touches", comment: "Settings › Features section: small extras")
            }
        }
    }

    var area: Area {
        switch self {
        case .plans, .prayer, .memorise: .daily
        case .wordStudy, .explore, .studyAssistant, .sermons: .study
        case .listen, .ambientSounds: .listening
        case .together: .community
        case .insights, .moments: .touches
        }
    }

    /// Offered on the setup screen too; the rest only in Settings › Features.
    var isOfferedInSetup: Bool {
        switch self {
        case .ambientSounds, .insights, .moments: false
        default: true
        }
    }

    /// The setting this one was split from, for choices saved before it had
    /// its own switch (plans, prayer and Memorise were "plansAndPrayer").
    var legacyParent: String? {
        switch self {
        case .plans, .prayer, .memorise: Self.legacyPlansAndPrayer
        default: nil
        }
    }

    static let legacyPlansAndPrayer = "plansAndPrayer"

    /// The switches that existed before every feature had its own.
    static let legacyKnown: Set<String> = ["listen", legacyPlansAndPrayer, "explore", "studyAssistant", "together"]

    /// Switched on for someone who sets up Genesis without changing anything.
    /// Groups and the community are opt-in.
    static let defaults: Set<OptionalFeature> = Set(allCases).subtracting([.together])
}

/// What this person wants to see. Hiding a feature hides its buttons, tabs
/// and Home sections; nothing is deleted, so turning it back on restores
/// everything. Server switches (FeatureFlagService) still decide whether a
/// feature exists at all.
@MainActor
@Observable
final class FeaturePreferences {
    private(set) var enabled: Set<OptionalFeature>
    /// True once the person has made a choice (during setup or in Settings).
    private(set) var hasChosen: Bool

    @ObservationIgnored private let defaults: UserDefaults
    private static let enabledKey = "features.enabled"
    private static let chosenKey = "features.chosen"
    /// The switches that existed when the choice was saved, so a switch added
    /// later starts the way that feature already was.
    private static let knownKey = "features.known"

    /// `existingUser`: someone who set up Genesis before this screen existed
    /// keeps everything they already had.
    init(defaults: UserDefaults = .standard, existingUser: Bool = false) {
        self.defaults = defaults
        if let saved = defaults.stringArray(forKey: Self.enabledKey) {
            let known = defaults.stringArray(forKey: Self.knownKey).map { Set($0) } ?? OptionalFeature.legacyKnown
            enabled = Self.migrated(saved: Set(saved), known: known)
            hasChosen = defaults.bool(forKey: Self.chosenKey)
            if known != Set(OptionalFeature.allCases.map(\.rawValue)) { save() }
        } else {
            enabled = existingUser ? Set(OptionalFeature.allCases) : OptionalFeature.defaults
            hasChosen = existingUser
        }
    }

    /// A saved choice read with today's switches. A switch the choice didn't
    /// know starts on, as that feature was always shown before; one split
    /// from an older switch (Plans & Prayer) follows it.
    nonisolated static func migrated(saved: Set<String>, known: Set<String>) -> Set<OptionalFeature> {
        var result = Set(saved.compactMap(OptionalFeature.init(rawValue:)))
        for feature in OptionalFeature.allCases where !known.contains(feature.rawValue) {
            let on = feature.legacyParent.map { saved.contains($0) } ?? true
            if on { result.insert(feature) }
        }
        return result
    }

    func isOn(_ feature: OptionalFeature) -> Bool {
        enabled.contains(feature)
    }

    func set(_ feature: OptionalFeature, on: Bool) {
        if on { enabled.insert(feature) } else { enabled.remove(feature) }
        hasChosen = true
        save()
    }

    /// The choice made during setup.
    func choose(_ features: Set<OptionalFeature>) {
        enabled = features
        hasChosen = true
        save()
    }

    private func save() {
        defaults.set(enabled.map(\.rawValue).sorted(), forKey: Self.enabledKey)
        defaults.set(hasChosen, forKey: Self.chosenKey)
        defaults.set(OptionalFeature.allCases.map(\.rawValue), forKey: Self.knownKey)
    }
}

extension FeaturePreferences {
    /// Whether the feature exists right now: the server has it switched on
    /// (for those behind a switch).
    static func isAvailable(_ feature: OptionalFeature, flags: FeatureFlagService) -> Bool {
        switch feature {
        case .studyAssistant: flags.isOn(.studyAssistant)
        case .together: flags.isOn(.groups) || flags.isOn(.community)
        case .plans, .prayer, .memorise, .listen, .ambientSounds, .wordStudy, .explore, .insights, .moments, .sermons: true
        }
    }

    /// Available and wanted.
    func shows(_ feature: OptionalFeature, flags: FeatureFlagService) -> Bool {
        isOn(feature) && Self.isAvailable(feature, flags: flags)
    }

    /// What to offer in Settings.
    static func offered(flags: FeatureFlagService) -> [OptionalFeature] {
        OptionalFeature.allCases.filter { isAvailable($0, flags: flags) }
    }

    /// What to offer on the setup screen.
    static func offeredInSetup(flags: FeatureFlagService) -> [OptionalFeature] {
        offered(flags: flags).filter(\.isOfferedInSetup)
    }
}
