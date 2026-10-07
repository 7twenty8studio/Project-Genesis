import Foundation
import SwiftData
import SwiftUI
import WidgetKit

/// Builds the widget snapshot from the app's data and asks WidgetKit to
/// refresh. Cheap, so it runs whenever the app becomes active or data changes.
@MainActor
enum WidgetSnapshotWriter {
    /// `memoriseShown`: false while Memorise is switched off in Settings ›
    /// Features, so its widget shows the off state instead of a passage.
    static func refresh(library: BibleLibrary, progress: ReadingProgress, context: ModelContext, isPremium: Bool, theme: ReaderTheme = .automatic, memoriseShown: Bool = true, now: Date = .now) {
        let snapshot = make(library: library, progress: progress, context: context, isPremium: isPremium, theme: theme, memoriseShown: memoriseShown, now: now)
        // Apple Watch gets the verses of the day too (sent only when they change).
        WatchConnector.shared.send(WatchPayload(generatedAt: now, translation: snapshot.translation, isPremium: isPremium, verses: snapshot.dailyVerses))
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

    /// Days ticked off on the Today's Reading widget since the app last ran.
    static func applyPendingPlanDays(context: ModelContext) {
        let changes = PendingPlanDays.take()
        guard !changes.isEmpty else { return }
        let store = StudyStore(context: context)
        for change in changes {
            let id = change.enrollmentID
            var descriptor = FetchDescriptor<PlanEnrollment>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let enrollment = (try? context.fetch(descriptor))?.first else { continue }
            store.setDay(change.day, completed: change.completed, in: enrollment)
        }
    }

    /// The reader theme's colours for theme-matched widgets (Premium). Auto
    /// and Seasons are resolved here: light and dark for Auto, today's
    /// season for Seasons (the snapshot is rewritten every time the app runs).
    static func widgetTheme(for theme: ReaderTheme, now: Date = .now) -> WidgetSnapshot.Theme {
        func colors(_ scheme: ColorScheme) -> WidgetSnapshot.Theme.Colors {
            let resolved = theme.resolved(for: scheme, on: now)
            let palette = resolved.palette
            return WidgetSnapshot.Theme.Colors(
                background: palette.backgroundHex,
                text: palette.textHex,
                secondary: palette.secondaryTextHex,
                accent: palette.accentHex,
                hasPaperTexture: resolved.hasPaperTexture,
                isDark: resolved.isDark
            )
        }
        return WidgetSnapshot.Theme(name: theme.rawValue, light: colors(.light), dark: colors(.dark))
    }

    static func make(library: BibleLibrary, progress: ReadingProgress, context: ModelContext, isPremium: Bool = false, theme: ReaderTheme = .automatic, memoriseShown: Bool = true, now: Date = .now) -> WidgetSnapshot {
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
                    fractionComplete: planProgress.fractionComplete,
                    enrollmentID: enrollment.id,
                    scheduledDay: planProgress.scheduledDay(on: now, calendar: calendar)
                )
            }
        }

        let prayers = (try? context.fetch(FetchDescriptor<Prayer>(predicate: #Predicate { !$0.isAnswered }))) ?? []
        let nextReminder = prayers.compactMap(\.reminderAt).filter { $0 > now }.min()

        // Memorise: the passage due soonest, as a first-letters prompt.
        // Switched off: nothing about it, just the off state.
        let memory = memoriseShown ? ((try? context.fetch(FetchDescriptor<MemoryVerse>(sortBy: [SortDescriptor(\.dueAt)]))) ?? []) : []
        var memorise = WidgetSnapshot.Memorise(isUnlocked: isPremium, dueDates: [], total: 0, reference: nil, hint: nil, translation: nil, isHidden: memoriseShown ? nil : true)
        if isPremium, memoriseShown, let next = memory.first {
            let translation = library.translations.first { $0.id == next.translationID } ?? library.currentTranslation
            let text = ((try? library.repository(for: translation).verses(from: next.start, through: next.end)) ?? []).map(\.plainText).joined(separator: " ")
            memorise = WidgetSnapshot.Memorise(
                isUnlocked: true,
                dueDates: memory.map(\.dueAt),
                total: memory.count,
                reference: next.reference.description,
                hint: text.isEmpty ? nil : MemoryHint.opening(text, words: 5),
                translation: translation.abbreviation
            )
        }

        return WidgetSnapshot(
            generatedAt: now,
            translation: library.currentTranslation.abbreviation,
            dailyVerses: dailyVerses,
            continueReading: continueReading,
            streakDays: progress.streak(on: now),
            chaptersRead: progress.chaptersRead.count,
            plan: plan,
            activePrayerCount: prayers.count,
            nextPrayerReminder: nextReminder,
            memorise: memorise,
            isPremium: isPremium,
            // Theme-matched widgets are Premium; free widgets keep the default look.
            theme: isPremium ? widgetTheme(for: theme, now: now) : nil
        )
    }
}
