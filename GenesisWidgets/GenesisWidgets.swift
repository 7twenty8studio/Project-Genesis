import UIKit
import SwiftUI
import WidgetKit

@main
struct GenesisWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DailyVerseWidget()
        ContinueReadingWidget()
        ReadingProgressWidget()
        StreakWidget()
        PrayerReminderWidget()
        MemoriseWidget()
        TodaysReadingWidget()
        GroupProgressWidget()
        ListeningLiveActivity()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Reads the snapshot the app writes. One entry per day at local midnight so
/// the verse of the day changes on time even if the app isn't opened.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? .placeholder : (WidgetSnapshot.load() ?? .placeholder)
        completion(SnapshotEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? .placeholder
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var entries = [SnapshotEntry(date: .now, snapshot: snapshot)]
        for offset in 1..<7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                entries.append(SnapshotEntry(date: day, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Style

/// Muted colours matching the app's Paper and Slate themes.
enum WidgetPalette {
    static let accent = Color(light: 0xA8844E, dark: 0xC9A96E)
    static let text = Color(light: 0x2B2A27, dark: 0xDAD5C8)
    static let secondary = Color(light: 0x7D776B, dark: 0x8D9196)
    static let background = Color(light: 0xFBF8F1, dark: 0x1E2226)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}


// MARK: - Daily verse

/// Free as the small Home Screen widget and on the Lock Screen; the medium
/// size is Premium.
struct DailyVerseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.dailyVerse.rawValue, provider: SnapshotProvider()) { entry in
            DailyVerseView(entry: entry)
        }
        .configurationDisplayName("Verse of the Day")
        .description("A new verse each morning.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct DailyVerseView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.snapshot.unlocks(.dailyVerse, in: family) {
            verseView
        } else {
            PremiumLockedView(message: String(localized: "Larger verse widgets come with Genesis Premium."), symbol: "text.quote")
        }
    }

    private var verseView: some View {
        let verse = entry.snapshot.dailyVerse(on: entry.date)
        let colors = WidgetColors(entry.snapshot)
        return Group {
            switch family {
            case .accessoryInline:
                Text(verse?.reference ?? String(localized: "Verse of the Day"))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(verse?.reference ?? "").font(.headline)
                    Text(verse?.text ?? "").font(.caption).lineLimit(3)
                }
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: String(localized: "Verse of the Day"), color: colors.accent)
                    Text(verse?.text ?? "")
                        .font(.system(family == .systemSmall ? .footnote : .body, design: .serif))
                        .foregroundStyle(colors.text)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Text("\(verse?.reference ?? "") \u{00B7} \(entry.snapshot.translation)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.secondary)
                }
            }
        }
        .containerBackground(for: .widget) {
            if WidgetSize(family).isAccessory { Color.clear } else { WidgetBackground(colors: colors) }
        }
        .widgetURL(verse.map { GenesisLink.read($0.verse) })
    }
}

// MARK: - Continue reading (Premium)

struct ContinueReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.continueReading.rawValue, provider: SnapshotProvider()) { entry in
            ContinueReadingView(entry: entry)
        }
        .configurationDisplayName("Continue Reading")
        .description("Pick up where you left off.")
        .supportedFamilies([.systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct ContinueReadingView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.snapshot.unlocks(.continueReading, in: family) {
            readingView
        } else {
            PremiumLockedView(message: String(localized: "Pick up where you left off with Genesis Premium."), symbol: "book")
        }
    }

    private var readingView: some View {
        let reading = entry.snapshot.continueReading
        let colors = WidgetColors(entry.snapshot)
        return Group {
            switch family {
            case .accessoryInline:
                Label(reading?.reference ?? String(localized: "Open Genesis"), systemImage: "book")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Continue", systemImage: "book").font(.caption)
                    Text(reading?.reference ?? String(localized: "Begin reading")).font(.headline)
                    if let reading { ProgressView(value: reading.bookProgress) }
                }
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: reading == nil ? String(localized: "Begin Reading") : String(localized: "Continue Reading"), color: colors.accent)
                    Text(reading?.reference ?? String(localized: "Genesis 1", comment: "Bible reference: the book of Genesis, chapter 1"))
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(colors.text)
                    Text(reading?.snippet ?? "In the beginning God created the heaven and the earth.")
                        .font(.system(.footnote, design: .serif))
                        .foregroundStyle(colors.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let reading {
                        ProgressView(value: reading.bookProgress).tint(colors.accent)
                    }
                }
            }
        }
        .containerBackground(for: .widget) {
            if WidgetSize(family).isAccessory { Color.clear } else { WidgetBackground(colors: colors) }
        }
        .widgetURL(GenesisLink.read(reading?.verse ?? 1_001_001))
    }
}

// MARK: - Reading progress (large, Premium)

struct ReadingProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.readingProgress.rawValue, provider: SnapshotProvider()) { entry in
            ReadingProgressView(entry: entry)
        }
        .configurationDisplayName("Reading Progress")
        .description("Today's plan reading, your streak and prayer reminders.")
        .supportedFamilies([.systemLarge])
    }
}

struct ReadingProgressView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.snapshot.unlocks(.readingProgress, in: family) {
            progressView(WidgetColors(entry.snapshot))
        } else {
            PremiumLockedView(message: String(localized: "See your plan, streak and prayers at a glance with Genesis Premium."), symbol: "chart.bar")
        }
    }

    private func progressView(_ colors: WidgetColors) -> some View {
        let snapshot = entry.snapshot
        return VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: String(localized: "Today"), color: colors.accent)
            if let plan = snapshot.plan {
                Link(destination: GenesisLink.plans) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(plan.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(colors.secondary)
                        Text(plan.todayTitle)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .foregroundStyle(colors.text)
                        HStack {
                            Text("Day \(plan.dayNumber) of \(plan.dayCount)")
                            Spacer()
                            if plan.isTodayComplete { Label("Done", systemImage: "checkmark.circle.fill") }
                        }
                        .font(.caption)
                        .foregroundStyle(colors.secondary)
                        ProgressView(value: plan.fractionComplete).tint(colors.accent)
                    }
                }
            } else if let reading = snapshot.continueReading {
                Link(destination: GenesisLink.read(reading.verse)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Continue Reading").font(.caption.weight(.semibold)).foregroundStyle(colors.secondary)
                        Text(reading.reference).font(.system(.title3, design: .serif, weight: .semibold)).foregroundStyle(colors.text)
                        ProgressView(value: reading.bookProgress).tint(colors.accent)
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                statTile(value: "\(snapshot.streakDays)", label: String(localized: "day streak"), symbol: "flame", colors: colors)
                statTile(value: "\(snapshot.chaptersRead)", label: String(localized: "chapters read"), symbol: "book.pages", colors: colors)
            }

            Link(destination: GenesisLink.prayer) {
                HStack(spacing: 10) {
                    Image(systemName: "hands.and.sparkles").foregroundStyle(colors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.activePrayerCount == 1 ? "1 prayer" : "\(snapshot.activePrayerCount) prayers")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colors.text)
                        if let reminder = snapshot.nextPrayerReminder {
                            Text("Next reminder \(reminder.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(colors.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if let verse = snapshot.dailyVerse(on: entry.date) {
                Text("\u{201C}\(verse.text)\u{201D} \u{2014} \(verse.reference)")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(colors.secondary)
                    .lineLimit(3)
            }
        }
        .containerBackground(for: .widget) { WidgetBackground(colors: colors) }
    }

    private func statTile(value: String, label: String, symbol: String, colors: WidgetColors) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(colors.accent)
            Text(value).font(.system(.title2, design: .serif, weight: .semibold)).foregroundStyle(colors.text)
            Text(label).font(.caption2).foregroundStyle(colors.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lock screen streak (Premium)

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.streak.rawValue, provider: SnapshotProvider()) { entry in
            StreakView(entry: entry)
        }
        .configurationDisplayName("Reading Streak")
        .description("Days in a row you've read.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct StreakView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.snapshot.unlocks(.streak, in: family) {
            streakView
        } else {
            PremiumLockedView(message: String(localized: "Keep your reading streak in view with Genesis Premium."), symbol: "flame")
        }
    }

    private var streakView: some View {
        Group {
            if family == .accessoryInline {
                Label("\(entry.snapshot.streakDays)-day streak", systemImage: "flame")
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "flame")
                        Text("\(entry.snapshot.streakDays)").font(.headline)
                    }
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(GenesisLink.read(entry.snapshot.continueReading?.verse ?? 1_001_001))
    }
}

// MARK: - Lock screen prayer reminder (Premium)

struct PrayerReminderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.prayerReminder.rawValue, provider: SnapshotProvider()) { entry in
            PrayerReminderView(entry: entry)
        }
        .configurationDisplayName("Prayer Reminder")
        .description("Your next prayer reminder and how many requests you're praying for.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct PrayerReminderView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.snapshot.unlocks(.prayerReminder, in: family) {
            prayerView
        } else {
            PremiumLockedView(message: String(localized: "See your next prayer reminder with Genesis Premium."), symbol: "hands.and.sparkles")
        }
    }

    private var prayerView: some View {
        let snapshot = entry.snapshot
        // Prayer text is private: only counts and times appear here.
        let count = snapshot.activePrayerCount == 1 ? String(localized: "1 prayer") : String(localized: "\(snapshot.activePrayerCount) prayers")
        let next = snapshot.nextPrayerReminder.map { $0.formatted(date: .omitted, time: .shortened) }
        return Group {
            switch family {
            case .accessoryInline:
                Label(next.map { String(localized: "Pray at \($0)") } ?? count, systemImage: "hands.and.sparkles")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "hands.and.sparkles")
                        Text("\(snapshot.activePrayerCount)").font(.headline)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Prayer", systemImage: "hands.and.sparkles")
                        .font(.headline)
                    Text(next.map { String(localized: "Next reminder \($0)") } ?? String(localized: "No reminder set"))
                    Text(count).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(GenesisLink.prayer)
    }
}
