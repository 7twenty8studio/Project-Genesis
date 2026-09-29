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

    @discardableResult
    func createPrayer(category: PrayerCategory = .personal) -> Prayer {
        let prayer = Prayer(category: category)
        context.insert(prayer)
        save()
        return prayer
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
    }

    func delete(_ prayer: Prayer) {
        PrayerReminders.cancel(prayerID: prayer.id)
        recordDeletion(of: prayer.id, in: SyncTable.prayers)
        context.delete(prayer)
        save()
    }
}
