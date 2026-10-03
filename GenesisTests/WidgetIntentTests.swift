import Foundation
import SwiftData
import Testing
@testable import Genesis

@Suite("Premium widgets", .serialized)
@MainActor
struct WidgetIntentTests {
    @Test func tickedDaysWaitForTheApp() {
        _ = PendingPlanDays.take()
        let plan = UUID()
        PendingPlanDays.add(.init(enrollmentID: plan, day: 3, completed: true))
        PendingPlanDays.add(.init(enrollmentID: plan, day: 3, completed: false))
        PendingPlanDays.add(.init(enrollmentID: plan, day: 4, completed: true))
        let changes = PendingPlanDays.take()
        #expect(changes.count == 2, "The latest tick for a day wins")
        #expect(changes.first { $0.day == 3 }?.completed == false)
        #expect(PendingPlanDays.take().isEmpty, "Taking clears them")
    }

    @Test func theAppAppliesTicksToThePlan() throws {
        _ = PendingPlanDays.take()
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let plan = ReadingPlan.gospels
        let enrollment = StudyStore(context: context).start(plan)
        PendingPlanDays.add(.init(enrollmentID: enrollment.id, day: 1, completed: true))
        WidgetSnapshotWriter.applyPendingPlanDays(context: context)
        #expect(enrollment.completedDays.contains(1))
    }

    @Test func olderSnapshotsStillDecode() throws {
        // Written by the previous version: no Memorise, Premium or plan ids.
        let json = """
        {"generatedAt":0,"translation":"KJV","dailyVerses":[],"streakDays":2,"chaptersRead":5,"activePrayerCount":0,
         "plan":{"title":"P","todayTitle":"John 1","dayNumber":1,"dayCount":30,"isTodayComplete":false,"fractionComplete":0}}
        """
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.memorise == nil)
        #expect(snapshot.isPremium == nil)
        #expect(snapshot.plan?.enrollmentID == nil)
    }
}
