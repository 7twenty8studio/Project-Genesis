import Foundation
import SwiftData

// Reading plans and the prayer journal. Same rules as the rest of StudyStore:
// every change updates `updatedAt`, deletions leave a tombstone for sync.

extension StudyStore {
    // MARK: Reading plans

    @discardableResult
    func start(_ plan: ReadingPlan, on date: Date = .now) -> PlanEnrollment {
        let enrollment = PlanEnrollment(plan: plan, startDate: date)
        context.insert(enrollment)
        save()
        return enrollment
    }

    func setDay(_ day: Int, completed: Bool, in enrollment: PlanEnrollment) {
        var days = enrollment.completedDays
        if completed { days.insert(day) } else { days.remove(day) }
        enrollment.completedDays = days
        enrollment.updatedAt = .now
        save()
    }

    /// Starts the plan again from today, clearing progress.
    func restart(_ enrollment: PlanEnrollment, on date: Date = .now) {
        enrollment.completedDays = []
        enrollment.startDate = Calendar.current.startOfDay(for: date)
        enrollment.isActive = true
        enrollment.updatedAt = .now
        save()
    }

    func delete(_ enrollment: PlanEnrollment) {
        recordDeletion(of: enrollment.id, in: SyncTable.readingPlans)
        context.delete(enrollment)
        save()
    }

    // MARK: Prayer journal

    /// Prayers with any content (answered ones included).
    func prayerCount() -> Int {
        let descriptor = FetchDescriptor<Prayer>(predicate: #Predicate { $0.title != "" || $0.body != "" })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    @discardableResult
    func createPrayer(category: PrayerCategory = .personal, passages: [PrayerPassage] = []) -> Prayer {
        let prayer = Prayer(category: category)
        prayer.passages = passages
        context.insert(prayer)
        save()
        return prayer
    }

    /// "I prayed for this": counts towards the prayer streak.
    func markPrayed(_ prayer: Prayer, on date: Date = .now) {
        prayer.lastPrayedAt = date
        prayer.updatedAt = .now
        save()
        PrayerStreak.record(on: date)
    }

    /// Attaches a passage (ids only), once.
    func attach(_ passage: PrayerPassage, to prayer: Prayer) {
        var passages = prayer.passages
        guard !passages.contains(passage), passages.count < PrayerPassage.maximumPerPrayer else { return }
        passages.append(passage)
        prayer.passages = passages
        prayer.updatedAt = .now
        save()
    }

    func detach(_ passage: PrayerPassage, from prayer: Prayer) {
        prayer.passages = prayer.passages.filter { $0 != passage }
        prayer.updatedAt = .now
        save()
    }

    func markAnswered(_ prayer: Prayer, note: String? = nil, answered: Bool = true) {
        prayer.isAnswered = answered
        prayer.answeredAt = answered ? .now : nil
        if let note { prayer.answerNote = note }
        if answered {
            prayer.reminderAt = nil
            prayer.reminderRepeatsDaily = false
        }
        prayer.updatedAt = .now
        save()
        PrayerReminders.update(for: prayer)
        if answered { PrayerStreak.record() }
    }

    func delete(_ prayer: Prayer) {
        PrayerReminders.cancel(prayerID: prayer.id)
        deleteAttachments(of: .prayer, id: prayer.id)
        recordDeletion(of: prayer.id, in: SyncTable.prayers)
        context.delete(prayer)
        save()
    }
}
