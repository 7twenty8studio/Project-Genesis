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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlimitedNotes: "Unlimited notes"
        case .unlimitedPrayers: "Unlimited prayer journal"
        case .cloudBackup: "Cloud backup and sync"
        case .premiumThemes: "Premium themes"
        case .advancedAI: "Advanced study assistant"
        case .historicalContent: "Timeline, maps and people"
        case .readingInsights: "Reading insights"
        }
    }

    var detail: String {
        switch self {
        case .unlimitedNotes: "Free includes \(FreeLimits.notes) notes."
        case .unlimitedPrayers: "Free includes \(FreeLimits.prayers) prayer requests."
        case .cloudBackup: "Keep highlights, notes, plans and prayers on all your devices."
        case .premiumThemes: "Cream, Parchment, Midnight and Sage."
        case .advancedAI: "Summaries, historical background, discussion questions and more, without the daily limit."
        case .historicalContent: "An interactive timeline, Bible maps and journeys, and a character explorer with family trees."
        case .readingInsights: "Time spent reading, favourite books and your reading history."
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
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    var periodUnit: String {
        switch self {
        case .monthly: "month"
        case .yearly: "year"
        }
    }

    static let ids = Set(allCases.map(\.rawValue))
}
