import Foundation
import SwiftData

/// A reading plan the person has started. The plan's schedule comes from
/// `ReadingPlan`; this stores only progress, so plans can improve without
/// migrating anyone's data.
@Model
final class PlanEnrollment {
    @Attribute(.unique) var id: UUID
    var planID: String
    var title: String
    /// Local midnight of the day the plan started.
    var startDate: Date
    /// Completed day numbers (1-based), comma separated.
    var completedDaysRaw: String = ""
    /// Book numbers for a custom plan, comma separated.
    var customBooksRaw: String? = nil
    var customDays: Int? = nil
    var isActive: Bool = true
    var createdAt: Date
    var updatedAt: Date

    init(plan: ReadingPlan, startDate: Date = .now, calendar: Calendar = .current) {
        id = UUID()
        planID = plan.id
        title = plan.title
        self.startDate = calendar.startOfDay(for: startDate)
        if case let .custom(books, days) = plan.kind {
            customBooksRaw = books.map(String.init).joined(separator: ",")
            customDays = days
        }
        createdAt = .now
        updatedAt = .now
    }

    /// Recreates an enrollment that was synced from another device.
    init(id: UUID, planID: String, title: String, startDate: Date) {
        self.id = id
        self.planID = planID
        self.title = title
        self.startDate = startDate
        createdAt = .now
        updatedAt = .now
    }

    var completedDays: Set<Int> {
        get { Set(completedDaysRaw.split(separator: ",").compactMap { Int($0) }) }
        set { completedDaysRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    var customBooks: [Int] {
        customBooksRaw?.split(separator: ",").compactMap { Int($0) } ?? []
    }

    /// The plan definition, rebuilt for custom plans.
    var plan: ReadingPlan? {
        if let customDays, !customBooks.isEmpty {
            return ReadingPlan.custom(id: planID, title: title, books: customBooks, days: customDays)
        }
        return ReadingPlan.builtIn(id: planID)
    }
}

enum PrayerCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    // Family, Church, Work, Health and Personal first; Friends kept for
    // prayers saved with it. The raw values match the prayers table's check.
    case family, church, work, health, personal, friends

    var id: String { rawValue }

    /// Reads any saved value: a known one in any case or spacing, a few
    /// likely words, and anything else as Personal, so no prayer is lost.
    init(lenient raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let known = PrayerCategory(rawValue: key) {
            self = known
            return
        }
        switch key {
        case "home", "marriage", "children", "kids", "parents", "relatives": self = .family
        case "ministry", "congregation", "mission", "missions": self = .church
        case "job", "career", "school", "study", "business": self = .work
        case "healing", "illness", "sickness", "wellbeing", "well-being": self = .health
        case "friend", "friendship", "neighbours", "neighbors": self = .friends
        default: self = .personal
        }
    }

    var title: String {
        switch self {
        case .family: String(localized: "Family")
        case .church: String(localized: "Church")
        case .work: String(localized: "Work")
        case .personal: String(localized: "Personal")
        case .health: String(localized: "Health")
        case .friends: String(localized: "Friends")
        }
    }

    var systemImage: String {
        switch self {
        case .family: "house"
        case .church: "building.columns"
        case .work: "briefcase"
        case .personal: "person"
        case .health: "heart"
        case .friends: "person.2"
        }
    }
}

/// A prayer request in the private prayer journal.
@Model
final class Prayer {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String
    var categoryRaw: String
    var isAnswered: Bool = false
    var answeredAt: Date? = nil
    var answerNote: String? = nil
    var reminderAt: Date? = nil
    var reminderRepeatsDaily: Bool = false
    /// Passages the prayer holds, as "start-end" verse ids separated by
    /// commas (`PrayerPassage`). Ids only, never the text.
    var passagesRaw: String = ""
    /// The last time the person marked this prayer as prayed.
    var lastPrayedAt: Date? = nil
    var createdAt: Date
    var updatedAt: Date

    init(title: String = "", body: String = "", category: PrayerCategory = .personal) {
        id = UUID()
        self.title = title
        self.body = body
        categoryRaw = category.rawValue
        createdAt = .now
        updatedAt = .now
    }

    var category: PrayerCategory {
        get { PrayerCategory(lenient: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }

    var passages: [PrayerPassage] {
        get { PrayerPassage.decode(passagesRaw) }
        set { passagesRaw = PrayerPassage.encode(newValue) }
    }

    var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var facts: PrayerFacts {
        PrayerFacts(
            id: id,
            category: category,
            isAnswered: isAnswered,
            createdAt: createdAt,
            answeredAt: answeredAt,
            lastPrayedAt: lastPrayedAt,
            hasContent: hasContent
        )
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = body.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        return firstLine.isEmpty ? String(localized: "Prayer") : firstLine
    }
}

/// Remembers that a synced record was deleted on this device, so the deletion
/// can be sent to the cloud. Removed once the server has it.
@Model
final class Tombstone {
    @Attribute(.unique) var recordID: UUID
    var table: String
    var deletedAt: Date

    init(recordID: UUID, table: String, deletedAt: Date = .now) {
        self.recordID = recordID
        self.table = table
        self.deletedAt = deletedAt
    }
}

/// Table names shared by local tombstones and the Supabase schema.
enum SyncTable {
    static let bookmarks = "bookmarks"
    static let highlightCollections = "highlight_collections"
    static let highlights = "highlights"
    static let notes = "notes"
    static let readingPlans = "reading_plans"
    static let prayers = "prayers"
    static let memoryVerses = "memory_verses"
    static let sermons = "sermons"
    static let attachments = "attachments"
}
