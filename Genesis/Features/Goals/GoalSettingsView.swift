import SwiftData
import SwiftUI

/// Goals & Streaks: the daily reading goal, streak shields, and the
/// milestones reached and still ahead. Reached from Settings and from the
/// goal card on Home.
struct GoalSettingsView: View {
    @Environment(GoalPreferences.self) private var goals
    @Environment(ReadingProgress.self) private var progress
    @Environment(FeaturePreferences.self) private var features
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var goals = goals
        let stats = Milestones.Stats.current(progress: progress, context: modelContext, features: features)
        Form {
            ThemedRows {
                Section {
                    Picker("Daily Goal", selection: $goals.goal) {
                        ForEach(ReadingGoal.allCases) { goal in
                            Text(goal.title).tag(goal)
                        }
                    }
                    .accessibilityIdentifier("goals.daily")
                    if let today = todaysProgress {
                        LabeledContent("Today") {
                            Text(today.isMet ? String(localized: "Goal reached") : today.label)
                                .foregroundStyle(today.isMet ? palette.accent : palette.secondaryText)
                        }
                    }
                } footer: {
                    Text("Chapters count when you open them; minutes are time spent in the reader.")
                }
                .listRowBackground(palette.surface)

                Section {
                    Toggle(isOn: $goals.usesStreakShields) {
                        Label("Streak Shield", systemImage: "shield.lefthalf.filled")
                    }
                    .tint(palette.accent)
                    .accessibilityIdentifier("goals.shields")
                    if goals.usesStreakShields {
                        LabeledContent("This week") {
                            Text(progress.streakShieldReady() ? String(localized: "Ready") : String(localized: "Used"))
                                .foregroundStyle(palette.secondaryText)
                        }
                        .accessibilityIdentifier("goals.shieldStatus")
                    }
                } footer: {
                    Text("Life happens. With the shield on, one missed day a week doesn't break your streak (it just doesn't add to it).")
                }
                .listRowBackground(palette.surface)

                milestones(stats)
            }
        }
        .themedScreen()
        .navigationTitle("Goals & Streaks")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var todaysProgress: GoalProgress? {
        goals.goal.progress(chaptersToday: progress.chaptersRead(on: .now), secondsToday: progress.secondsRead(on: .now))
    }

    @ViewBuilder
    private func milestones(_ stats: Milestones.Stats) -> some View {
        let earned = Milestones.earned(stats)
        let next = Milestones.next(stats).filter { visible($0.kind) }
        if !next.isEmpty {
            Section("Next Milestones") {
                ForEach(next) { milestone in
                    MilestoneRow(milestone: milestone, isEarned: false)
                }
            }
            .listRowBackground(palette.surface)
        }
        Section {
            if earned.isEmpty {
                Text("Your first milestone is three days of reading in a row.")
                    .foregroundStyle(palette.secondaryText)
            } else {
                ForEach(earned.reversed()) { milestone in
                    MilestoneRow(milestone: milestone, isEarned: true)
                }
            }
        } header: {
            Text("Milestones Reached")
        }
        .listRowBackground(palette.surface)
    }

    /// Prayer and Memorize milestones only while those features are shown.
    private func visible(_ kind: Milestone.Kind) -> Bool {
        switch kind {
        case .prayers: features.isOn(.prayer)
        case .memorised: features.isOn(.memorise)
        case .streak, .chapters, .books: true
        }
    }
}

private struct MilestoneRow: View {
    let milestone: Milestone
    let isEarned: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        Label {
            Text(milestone.title)
                .foregroundStyle(isEarned ? palette.text : palette.secondaryText)
        } icon: {
            Image(systemName: milestone.systemImage)
                .foregroundStyle(isEarned ? palette.accent : palette.secondaryText)
        }
        .accessibilityIdentifier(isEarned ? "goals.milestone.earned" : "goals.milestone.next")
    }
}
