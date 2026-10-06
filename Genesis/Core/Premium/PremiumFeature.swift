import Foundation

/// What Genesis Premium unlocks (from the PRD's Premium Features list).
enum PremiumFeature: String, CaseIterable, Identifiable, Sendable {
    case cloudBackup
    case premiumThemes
    case advancedAI
    case historicalContent
    case readingInsights
    case advancedSearch
    case ambientSounds
    case memorise
    case widgets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cloudBackup: String(localized: "Cloud backup and sync")
        case .premiumThemes: String(localized: "Premium themes")
        case .advancedAI: String(localized: "Advanced study assistant")
        case .historicalContent: String(localized: "Timeline, maps and people")
        case .readingInsights: String(localized: "Reading insights")
        case .advancedSearch: String(localized: "Advanced search")
        case .ambientSounds: String(localized: "Ambient sounds")
        case .memorise: String(localized: "Memorise Scripture")
        case .widgets: String(localized: "More widgets")
        }
    }

    var detail: String {
        switch self {
        case .cloudBackup: String(localized: "Keep highlights, notes, plans and prayers on all your devices.")
        case .premiumThemes: String(localized: "Textured paper in Cream, Parchment, Midnight and Sage, and seasonal themes with falling leaves, snow, blossom and summer sunlight.")
        case .advancedAI: String(localized: "Summaries, historical background, discussion questions and more, without the daily limit.")
        case .historicalContent: String(localized: "An interactive timeline, Bible maps and journeys, and a character explorer with family trees.")
        case .readingInsights: String(localized: "Time spent reading, favourite books and your reading history.")
        case .advancedSearch: String(localized: "Search by topic across the whole Bible, and narrow searches to a testament or book.")
        case .widgets: String(localized: "Tick off today's reading from your Home Screen, and follow along on the Lock Screen while you listen.")
        case .memorise: String(localized: "Flashcards that bring each verse back just before you'd forget it, with a widget for your Home Screen.")
        case .ambientSounds: String(localized: "Rain, ocean waves, wind, a crackling fire, birdsong and a soft worship pad to read and pray with, mixed your way.")
        }
    }

    var systemImage: String {
        switch self {
        case .cloudBackup: "icloud"
        case .premiumThemes: "paintpalette"
        case .advancedAI: "sparkles"
        case .historicalContent: "map"
        case .readingInsights: "chart.bar"
        case .advancedSearch: "text.magnifyingglass"
        case .ambientSounds: "speaker.wave.2"
        case .memorise: "brain.head.profile"
        case .widgets: "apps.iphone"
        }
    }
}

/// What the free version includes. Notes, highlights, the prayer journal and
/// reading plans have no limits.
enum FreeLimits {
    /// Passage explanations per day without Premium. The server enforces this;
    /// the app only uses it for display.
    static let aiRequestsPerDay = 3
}

/// Genesis Premium subscriptions. Prices live in App Store Connect (and in
/// Config/Genesis.storekit for local testing); these are fallbacks for display
/// before the App Store answers.
enum PremiumProduct: String, CaseIterable, Sendable {
    case monthly = "com.7twenty8studio.genesis.premium.monthly"
    case yearly = "com.7twenty8studio.genesis.premium.yearly"

    var fallbackPrice: String {
        switch self {
        case .monthly: "$7.99"
        case .yearly: "$59.99"
        }
    }

    var periodTitle: String {
        switch self {
        case .monthly: String(localized: "Monthly", comment: "Subscription period")
        case .yearly: String(localized: "Yearly", comment: "Subscription period")
        }
    }

    var periodUnit: String {
        switch self {
        case .monthly: String(localized: "month", comment: "Subscription period unit, as in $7.99 / month")
        case .yearly: String(localized: "year", comment: "Subscription period unit, as in $7.99 / month")
        }
    }

    static let ids = Set(allCases.map(\.rawValue))
}
