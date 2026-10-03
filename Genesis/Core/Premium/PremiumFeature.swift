import Foundation

/// What Genesis Premium unlocks (from the PRD's Premium Features list).
enum PremiumFeature: String, CaseIterable, Identifiable, Sendable {
    case unlimitedNotes
    case unlimitedPrayers
    case cloudBackup
    case premiumThemes
    case advancedAI
    case historicalContent
    case readingInsights
    case ambientSounds
    case memorise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlimitedNotes: String(localized: "Unlimited notes")
        case .unlimitedPrayers: String(localized: "Unlimited prayer journal")
        case .cloudBackup: String(localized: "Cloud backup and sync")
        case .premiumThemes: String(localized: "Premium themes")
        case .advancedAI: String(localized: "Advanced study assistant")
        case .historicalContent: String(localized: "Timeline, maps and people")
        case .readingInsights: String(localized: "Reading insights")
        case .ambientSounds: String(localized: "Ambient sounds")
        case .memorise: String(localized: "Memorise Scripture")
        }
    }

    var detail: String {
        switch self {
        case .unlimitedNotes: String(localized: "Free includes \(FreeLimits.notes) notes.")
        case .unlimitedPrayers: String(localized: "Free includes \(FreeLimits.prayers) prayer requests.")
        case .cloudBackup: String(localized: "Keep highlights, notes, plans and prayers on all your devices.")
        case .premiumThemes: String(localized: "Textured paper in Cream, Parchment, Midnight and Sage, and seasonal themes with falling leaves, snow, blossom and summer sunlight.")
        case .advancedAI: String(localized: "Summaries, historical background, discussion questions and more, without the daily limit.")
        case .historicalContent: String(localized: "An interactive timeline, Bible maps and journeys, and a character explorer with family trees.")
        case .readingInsights: String(localized: "Time spent reading, favourite books and your reading history.")
        case .memorise: String(localized: "Flashcards that bring each verse back just before you'd forget it, with a widget for your Home Screen.")
        case .ambientSounds: String(localized: "Rain, ocean waves, wind, a crackling fire, birdsong and a soft worship pad to read and pray with, mixed your way.")
        }
    }

    var systemImage: String {
        switch self {
        case .unlimitedNotes: "note.text"
        case .unlimitedPrayers: "hands.and.sparkles"
        case .cloudBackup: "icloud"
        case .premiumThemes: "paintpalette"
        case .advancedAI: "sparkles"
        case .historicalContent: "map"
        case .readingInsights: "chart.bar"
        case .ambientSounds: "speaker.wave.2"
        case .memorise: "brain.head.profile"
        }
    }
}

/// What the free version includes.
enum FreeLimits {
    static let notes = 25
    static let prayers = 25
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
        case .monthly: "$4.99"
        case .yearly: "$39.99"
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
        case .monthly: String(localized: "month", comment: "Subscription period unit, as in $4.99 / month")
        case .yearly: String(localized: "year", comment: "Subscription period unit, as in $4.99 / month")
        }
    }

    static let ids = Set(allCases.map(\.rawValue))
}
