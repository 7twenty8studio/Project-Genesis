import SwiftData
import SwiftUI

/// Home: today's progress toward the daily goal and the streak shield, or an
/// invitation to set a goal. Opens Goals & Streaks.
struct GoalHomeCard: View {
    @Environment(GoalPreferences.self) private var goals
    @Environment(ReadingProgress.self) private var progress
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            router.homePath.append(.goals)
        } label: {
            HStack(spacing: 14) {
                ring
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(palette.text)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(palette.secondaryText)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.goal")
    }

    private var today: GoalProgress? {
        goals.goal.progress(chaptersToday: progress.chaptersRead(on: .now), secondsToday: progress.secondsRead(on: .now))
    }

    private var title: String {
        guard let today else { return String(localized: "Set a daily goal") }
        return today.isMet ? String(localized: "Today's goal reached") : String(localized: "Today's goal")
    }

    private var detail: String {
        guard let today else { return String(localized: "A chapter or a few minutes a day, whatever fits your life.") }
        let goalLine = today.isMet ? goals.goal.title : today.label
        guard goals.usesStreakShields else { return goalLine }
        let shield = progress.streakShieldReady()
            ? String(localized: "Streak shield ready")
            : String(localized: "Streak shield used this week")
        return String(localized: "\(goalLine) · \(shield)", comment: "Home goal card: progress, then the streak shield's state")
    }

    private var ring: some View {
        let fraction = today?.fraction ?? 0
        return ZStack {
            Circle()
                .stroke(palette.secondaryText.opacity(0.2), lineWidth: 5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: today?.isMet == true ? "checkmark" : "target")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.accent)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

/// Home: a milestone just reached, shown once ("30 days in a row").
struct MilestoneBanner: View {
    let milestone: Milestone
    let onDismiss: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: milestone.systemImage)
                .font(.title2)
                .foregroundStyle(palette.accent)
                .symbolEffect(.bounce, value: milestone.id)
            VStack(alignment: .leading, spacing: 4) {
                Text("Milestone")
                    .font(.caption.weight(.semibold))
                    .kerning(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.accent)
                Text(milestone.title)
                    .font(.headline)
                    .foregroundStyle(palette.text)
                Text(milestone.detail)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(palette.secondaryText)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("home.milestone.dismiss")
        }
        .card()
        .accessibilityIdentifier("home.milestone")
    }
}

/// Watches for milestones while Home is on screen (attached to Home itself,
/// since the banner isn't there until there's something to show). Someone
/// seeing milestones for the first time has what they'd already reached
/// marked quietly instead of a parade; after that, one at a time.
struct MilestoneWatcher: ViewModifier {
    @Binding var showing: Milestone?

    @Environment(GoalPreferences.self) private var goals
    @Environment(ReadingProgress.self) private var progress
    @Environment(FeaturePreferences.self) private var features
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onAppear(perform: check)
            .onChange(of: progress.chaptersRead.count) { check() }
            .onChange(of: progress.readingDays.count) { check() }
            .onChange(of: showing) { _, now in
                // Dismissed: the next one, if several were reached at once.
                if now == nil { check() }
            }
    }

    private func check() {
        guard features.isOn(.goals) else { return }
        let stats = Milestones.Stats.current(progress: progress, context: modelContext, features: features)
        let result = Milestones.toCelebrate(stats, celebrated: goals.celebrated, hasCelebratedAny: goals.hasCelebratedAny)
        if !goals.hasCelebratedAny || !result.markQuietly.isEmpty {
            // Also records that milestones have been looked at, even with
            // nothing reached yet, so the next one is celebrated.
            goals.markCelebrated(result.markQuietly)
        }
        guard showing == nil, let next = result.show else { return }
        withAnimation(Motion.change(reduceMotion: reduceMotion)) { showing = next }
    }
}
