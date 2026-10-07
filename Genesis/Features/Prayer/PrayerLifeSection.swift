import SwiftUI

/// "Your prayer life": a gentle streak with "I prayed today", and a few
/// numbers. No guilt: a missed day simply starts again.
struct PrayerLifeSection: View {
    let prayers: [Prayer]

    @Environment(\.palette) private var palette
    @AppStorage(PrayerStreak.storageKey) private var prayedLog = ""
    @State private var showsDetails = false

    var body: some View {
        let facts = prayers.map(\.facts)
        let days = PrayerStreak.days(log: PrayerStreak.decodeLog(prayedLog), prayers: facts)
        let stats = PrayerStatistics(facts)
        Section {
            streakRow(days: days)
            if stats.total > 0 {
                numbers(stats)
                DisclosureGroup("More About Your Prayers", isExpanded: $showsDetails) {
                    PrayerStatisticsDetails(stats: stats)
                }
                .tint(palette.accent)
                .accessibilityIdentifier("prayer.stats.more")
            }
        } header: {
            Text("Your Prayer Life")
        }
    }

    private func streakRow(days: Set<String>) -> some View {
        let streak = PrayerStreak.length(of: days)
        let prayedToday = PrayerStreak.hasPrayed(in: days)
        return HStack(spacing: 12) {
            Image(systemName: "flame")
                .font(.title3)
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            streakText(streak, prayedToday: prayedToday)
                .font(.subheadline)
                .foregroundStyle(palette.text)
                .accessibilityIdentifier("prayer.streak")
            Spacer(minLength: 8)
            Button {
                prayedLog = PrayerStreak.recording(.now, in: prayedLog)
            } label: {
                Label(prayedToday ? "Prayed" : "I Prayed Today", systemImage: prayedToday ? "checkmark" : "hands.and.sparkles")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(prayedToday)
            .accessibilityIdentifier("prayer.prayedToday")
        }
    }

    private func streakText(_ streak: Int, prayedToday: Bool) -> Text {
        if streak >= 2 {
            Text("\(streak) days in a row of prayer")
        } else if prayedToday || streak == 1 {
            Text("You've prayed today. Every day is a fresh start.")
        } else {
            Text("Take a quiet moment with God today.")
        }
    }

    private func numbers(_ stats: PrayerStatistics) -> some View {
        HStack(spacing: 10) {
            number("\(stats.total)", label: String(localized: "requests"))
            number("\(stats.answered)", label: String(localized: "answered"))
            number("\(stats.answeredPercent)%", label: String(localized: "of all answered"))
            number("\(stats.active)", label: String(localized: "still praying"))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prayer.stats")
    }

    private func number(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(label)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Requests by category and how long answers took.
private struct PrayerStatisticsDetails: View {
    let stats: PrayerStatistics
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(stats.byCategory) { item in
                HStack {
                    Label(item.category.title, systemImage: item.category.systemImage)
                    Spacer()
                    Text(verbatim: "\(item.count)")
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(palette.text)
                .accessibilityElement(children: .combine)
            }
            averageText
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    private var averageText: Text {
        switch stats.averageAnswerDays {
        case nil: Text("When a prayer is answered, you'll see how long the answer took.")
        case 0?: Text("Answers came within a day, on average.")
        case 1?: Text("Answers came after about a day, on average.")
        case let days?: Text("Answers came after about \(days) days, on average.")
        }
    }
}
