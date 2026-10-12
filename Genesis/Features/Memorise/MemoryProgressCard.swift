import SwiftUI

/// The Memorise level (by passages memorised) with a calm bar toward the
/// next one, and the days-in-a-row practice streak.
struct MemoryProgressCard: View {
    /// Passages at mastery `.memorised`.
    let memorisedCount: Int

    @Environment(\.palette) private var palette
    @AppStorage(PracticeStreak.storageKey) private var streak = PracticeStreak()

    private var level: MemoryLevel { MemoryLevel.level(memorised: memorisedCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: level.symbol)
                    .font(.title3)
                    .foregroundStyle(palette.accent)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(.headline)
                        .foregroundStyle(palette.text)
                        .accessibilityIdentifier("memorise.level")
                    Text(nextText)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
            }
            ProgressView(value: MemoryLevel.progress(memorised: memorisedCount))
                .tint(palette.accent)
                .accessibilityLabel("Level progress")
            HStack(spacing: 6) {
                Image(systemName: streak.hasPractised() ? "checkmark.circle" : "calendar")
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                Text(streakText)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityIdentifier("memorise.streak")
            }
        }
        .padding(.vertical, 6)
    }

    private var nextText: String {
        guard let next = level.next else { return String(localized: "You've reached the highest level.") }
        return String(localized: "Next level: \(next.title)")
    }

    private var streakText: String {
        let streakCount = streak.current()
        switch streakCount {
        case 0: return String(localized: "Practice today to start a streak.")
        case 1: return String(localized: "1 day in a row")
        default: return String(localized: "\(streakCount) days in a row")
        }
    }
}

/// One game on the Memorise screen.
struct MemoryGameRow: View {
    let mode: MemoryGameMode

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: mode.symbol)
                .font(.body)
                .foregroundStyle(palette.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(palette.text)
                Text(mode.subtitle)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
