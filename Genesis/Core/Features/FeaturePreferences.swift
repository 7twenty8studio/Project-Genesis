import Foundation

/// Parts of Genesis people can switch off for a simpler app. Reading, notes,
/// highlights, bookmarks and search are always there.
enum OptionalFeature: String, CaseIterable, Identifiable, Codable, Sendable {
    case listen
    case plansAndPrayer
    case explore
    case studyAssistant
    case together

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listen: String(localized: "Listen", comment: "Optional feature: hear chapters read aloud")
        case .plansAndPrayer: String(localized: "Plans & Prayer")
        case .explore: String(localized: "Timeline, Maps & People")
        case .studyAssistant: String(localized: "Study Notes")
        case .together: String(localized: "Groups & Community")
        }
    }

    var detail: String {
        switch self {
        case .listen: String(localized: "Hear any chapter read aloud, with the page following along.")
        case .plansAndPrayer: String(localized: "Reading plans, memorising Scripture and a private prayer journal on your Home screen.")
        case .explore: String(localized: "Explore the Bible's story, places and people.")
        case .studyAssistant: String(localized: "Short explanations of a passage, clearly labelled as AI-generated.")
        case .together: String(localized: "Read and pray with your church group, and the community prayer wall.")
        }
    }

    var systemImage: String {
        switch self {
        case .listen: "headphones"
        case .plansAndPrayer: "calendar"
        case .explore: "map"
        case .studyAssistant: "sparkles"
        case .together: "person.3"
        }
    }

    /// Switched on for someone who sets up Genesis without changing anything.
    /// Groups and the community are opt-in.
    static let defaults: Set<OptionalFeature> = [.listen, .plansAndPrayer, .explore, .studyAssistant]
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

    /// `existingUser`: someone who set up Genesis before this screen existed
    /// keeps everything they already had.
    init(defaults: UserDefaults = .standard, existingUser: Bool = false) {
        self.defaults = defaults
        if let saved = defaults.stringArray(forKey: Self.enabledKey) {
            enabled = Set(saved.compactMap(OptionalFeature.init(rawValue:)))
            hasChosen = defaults.bool(forKey: Self.chosenKey)
        } else {
            enabled = existingUser ? Set(OptionalFeature.allCases) : OptionalFeature.defaults
            hasChosen = existingUser
        }
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
    }
}

extension FeaturePreferences {
    /// Whether the feature exists right now: the server has it switched on
    /// (for those behind a switch).
    static func isAvailable(_ feature: OptionalFeature, flags: FeatureFlagService) -> Bool {
        switch feature {
        case .studyAssistant: flags.isOn(.studyAssistant)
        case .together: flags.isOn(.groups) || flags.isOn(.community)
        case .listen, .plansAndPrayer, .explore: true
        }
    }

    /// Available and wanted.
    func shows(_ feature: OptionalFeature, flags: FeatureFlagService) -> Bool {
        isOn(feature) && Self.isAvailable(feature, flags: flags)
    }

    /// What to offer in setup and Settings.
    static func offered(flags: FeatureFlagService) -> [OptionalFeature] {
        OptionalFeature.allCases.filter { isAvailable($0, flags: flags) }
    }
}
