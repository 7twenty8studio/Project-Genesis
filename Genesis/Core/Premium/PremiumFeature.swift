import Foundation

/// What Genesis Premium unlocks (from the PRD's Premium Features list).
enum PremiumFeature: String, CaseIterable, Identifiable, Sendable {
    case morningWelcome
    case wordStudy
    case advancedAI
    case historicalContent
    case premiumThemes
    case readingInsights
    case advancedSearch
    case ambientSounds
    case memorise
    case widgets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morningWelcome: String(localized: "Morning welcome")
        case .wordStudy: String(localized: "Word study and commentary")
        case .premiumThemes: String(localized: "Themes, fonts and icons")
        case .advancedAI: String(localized: "Advanced study assistant")
        case .historicalContent: String(localized: "Family trees, maps and journeys")
        case .readingInsights: String(localized: "Reading insights")
        case .advancedSearch: String(localized: "Advanced search")
        case .ambientSounds: String(localized: "Ambient sounds")
        case .memorise: String(localized: "Memorise Scripture")
        case .widgets: String(localized: "Every widget")
        }
    }

    var detail: String {
        switch self {
        case .morningWelcome: String(localized: "Begin each day with a quiet welcome: your name, today's verse and reading, and your sounds easing in.")
        case .wordStudy: String(localized: "The Hebrew and Greek words behind every verse, with Strong's definitions, and Matthew Henry's commentary on the whole Bible.")
        case .premiumThemes: String(localized: "Textured paper and seasonal themes, Starlight for reading at night, illuminated first letters, three more book fonts, special app icons and a ribbon when you finish a chapter.")
        case .advancedAI: String(localized: "Summaries, historical background, discussion questions and more, with up to 30 new answers a day.")
        case .historicalContent: String(localized: "Family trees for 3,000 people, interactive maps with Paul's journeys and the Exodus, and the people and places beside the chapter you're reading.")
        case .readingInsights: String(localized: "Time spent reading, favourite books and your reading history.")
        case .advancedSearch: String(localized: "Search by topic across the whole Bible, and narrow searches to a testament or book.")
        case .widgets: String(localized: "Every widget in every size, in your reading theme: today's reading, progress, prayer, Memorise, your group and listening on the Lock Screen.")
        case .memorise: String(localized: "Flashcards that bring each verse back just before you'd forget it, plus games, levels and a daily streak.")
        case .ambientSounds: String(localized: "Rain, ocean waves, wind, a crackling fire, birdsong and a soft worship pad to read and pray with, mixed your way.")
        }
    }

    var systemImage: String {
        switch self {
        case .morningWelcome: "sun.horizon"
        case .wordStudy: "character.book.closed"
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

/// Who a Premium plan covers. Individual is one person (Family Sharing off);
/// Family is shared with up to six people through Apple's Family Sharing.
enum PremiumPlan: String, CaseIterable, Sendable {
    case individual, family

    var title: String {
        switch self {
        case .individual: String(localized: "Individual", comment: "Premium plan for one person")
        case .family: String(localized: "Family", comment: "Premium plan shared with family")
        }
    }

    var detail: String {
        switch self {
        case .individual: String(localized: "For you, on all your devices.")
        case .family: String(localized: "For up to six people in your Apple family, each with their own notes and progress.")
        }
    }
}

/// Genesis Premium subscriptions, all in one App Store subscription group (so
/// switching plans is an upgrade or downgrade, never two subscriptions).
/// Prices live in App Store Connect (and in Config/Genesis.storekit for local
/// testing); these are fallbacks for display before the App Store answers.
enum PremiumProduct: String, CaseIterable, Sendable {
    case monthly = "com.7twenty8studio.genesis.premium.monthly"
    case yearly = "com.7twenty8studio.genesis.premium.yearly"
    case familyMonthly = "com.7twenty8studio.genesis.premium.family.monthly"
    case familyYearly = "com.7twenty8studio.genesis.premium.family.yearly"

    static func product(_ plan: PremiumPlan, yearly: Bool) -> PremiumProduct {
        switch plan {
        case .individual: yearly ? .yearly : .monthly
        case .family: yearly ? .familyYearly : .familyMonthly
        }
    }

    var plan: PremiumPlan {
        switch self {
        case .monthly, .yearly: .individual
        case .familyMonthly, .familyYearly: .family
        }
    }

    var isYearly: Bool { self == .yearly || self == .familyYearly }

    var fallbackPrice: String {
        switch self {
        case .monthly: "$7.99"
        case .yearly: "$59.99"
        case .familyMonthly: "$12.99"
        case .familyYearly: "$99.99"
        }
    }

    var periodTitle: String {
        isYearly
            ? String(localized: "Yearly", comment: "Subscription period")
            : String(localized: "Monthly", comment: "Subscription period")
    }

    var periodUnit: String {
        isYearly
            ? String(localized: "year", comment: "Subscription period unit, as in $7.99 / month")
            : String(localized: "month", comment: "Subscription period unit, as in $7.99 / month")
    }

    /// "Family plan, billed yearly", for the active-subscription card.
    var planDescription: String {
        switch self {
        case .monthly: String(localized: "Individual plan, billed monthly")
        case .yearly: String(localized: "Individual plan, billed yearly")
        case .familyMonthly: String(localized: "Family plan, billed monthly")
        case .familyYearly: String(localized: "Family plan, billed yearly")
        }
    }

    static let ids = Set(allCases.map(\.rawValue))
}
