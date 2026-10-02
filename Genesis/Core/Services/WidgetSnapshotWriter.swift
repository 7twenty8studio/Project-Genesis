import Foundation
import SwiftData
import WidgetKit

/// Builds the widget snapshot from the app's data and asks WidgetKit to
/// refresh. Cheap, so it runs whenever the app becomes active or data changes.
@MainActor
enum WidgetSnapshotWriter {
    static func refresh(library: BibleLibrary, progress: ReadingProgress, context: ModelContext, now: Date = .now) {
        let snapshot = make(library: library, progress: progress, context: context, now: now)
        // Skip the write (and widget reload) when nothing visible changed.
        if var saved = WidgetSnapshot.load() {
            saved.generatedAt = snapshot.generatedAt
            if saved == snapshot { return }
        }
        do {
            try snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            CrashReporter.record(error, context: "WidgetSnapshot.save")
        }
    }

    static func make(library: BibleLibrary, progress: ReadingProgress, context: ModelContext, now: Date = .now) -> WidgetSnapshot {
        let repository = library.current
        let calendar = Calendar.current

        // Two weeks of daily verses so widgets stay fresh if the app isn't opened.
        let days = (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
        let dailyVerses: [WidgetSnapshot.DailyVerse] = days.compactMap { day in
            let id = DailyVerse.verse(for: day, calendar: calendar)
            guard let verse = try? repository.verse(id) else { return nil }
            return WidgetSnapshot.DailyVerse(
                day: Timestamp.dayString(from: day, calendar: calendar),
                reference: PassageReference(verse: id).description,
                text: verse.plainText,
                verse: id.rawValue
            )
        }

        var continueReading: WidgetSnapshot.ContinueReading?
        if progress.hasStartedReading {
            let position = progress.position
            let snippet = (try? repository.verse(position))?.plainText ?? ""
            continueReading = WidgetSnapshot.ContinueReading(
                reference: position.chapterID.description,
                snippet: snippet,
                verse: position.rawValue,
                bookProgress: progress.progressThroughBook
            )
        }

        let enrollments = (try? context.fetch(FetchDescriptor<PlanEnrollment>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        var plan: WidgetSnapshot.Plan?
        if let enrollment = enrollments.first(where: \.isActive), let definition = enrollment.plan {
            let planProgress = PlanProgress(plan: definition, startDate: enrollment.startDate, completedDays: enrollment.completedDays)
            if let today = planProgress.todaysDay(on: now, calendar: calendar) {
                plan = WidgetSnapshot.Plan(
                    // The definition's title follows the app's language for built-in plans.
                    title: definition.title,
                    todayTitle: today.title,
                    dayNumber: today.number,
                    dayCount: definition.dayCount,
                    isTodayComplete: planProgress.completedDays.contains(planProgress.scheduledDay(on: now, calendar: calendar)),
                    fractionComplete: planProgress.fractionComplete
                )
            }
        }

        let prayers = (try? context.fetch(FetchDescriptor<Prayer>(predicate: #Predicate { !$0.isAnswered }))) ?? []
        let nextReminder = prayers.compactMap(\.reminderAt).filter { $0 > now }.min()

        return WidgetSnapshot(
            generatedAt: now,
            translation: library.currentTranslation.abbreviation,
            dailyVerses: dailyVerses,
            continueReading: continueReading,
            streakDays: progress.streak(on: now),
            chaptersRead: progress.chaptersRead.count,
            plan: plan,
            activePrayerCount: prayers.count,
            nextPrayerReminder: nextReminder
        )
    }
}
