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

private struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(1)
            .foregroundStyle(WidgetPalette.accent)
    }
}

// MARK: - Daily verse

struct DailyVerseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyVerse", provider: SnapshotProvider()) { entry in
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
        let verse = entry.snapshot.dailyVerse(on: entry.date)
        Group {
            switch family {
            case .accessoryInline:
                Text(verse?.reference ?? "Verse of the Day")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(verse?.reference ?? "").font(.headline)
                    Text(verse?.text ?? "").font(.caption).lineLimit(3)
                }
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Verse of the Day")
                    Text(verse?.text ?? "")
                        .font(.system(family == .systemSmall ? .footnote : .body, design: .serif))
                        .foregroundStyle(WidgetPalette.text)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Text("\(verse?.reference ?? "") \u{00B7} \(entry.snapshot.translation)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetPalette.secondary)
                }
            }
        }
        .containerBackground(for: .widget) { WidgetPalette.background }
        .widgetURL(verse.map { GenesisLink.read($0.verse) })
    }
}

// MARK: - Continue reading

struct ContinueReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ContinueReading", provider: SnapshotProvider()) { entry in
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
        let reading = entry.snapshot.continueReading
        Group {
            switch family {
            case .accessoryInline:
                Label(reading?.reference ?? "Open Genesis", systemImage: "book")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Continue", systemImage: "book").font(.caption)
                    Text(reading?.reference ?? "Begin reading").font(.headline)
                    if let reading { ProgressView(value: reading.bookProgress) }
                }
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: reading == nil ? "Begin Reading" : "Continue Reading")
                    Text(reading?.reference ?? "Genesis 1")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(WidgetPalette.text)
                    Text(reading?.snippet ?? "In the beginning God created the heaven and the earth.")
                        .font(.system(.footnote, design: .serif))
                        .foregroundStyle(WidgetPalette.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let reading {
                        ProgressView(value: reading.bookProgress).tint(WidgetPalette.accent)
                    }
                }
            }
        }
        .containerBackground(for: .widget) { WidgetPalette.background }
        .widgetURL(GenesisLink.read(reading?.verse ?? 1_001_001))
    }
}

// MARK: - Reading progress (large)

struct ReadingProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReadingProgress", provider: SnapshotProvider()) { entry in
            ReadingProgressView(entry: entry)
        }
        .configurationDisplayName("Reading Progress")
        .description("Today's plan reading, your streak and prayer reminders.")
        .supportedFamilies([.systemLarge])
    }
}

struct ReadingProgressView: View {
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Today")
            if let plan = snapshot.plan {
                Link(destination: GenesisLink.plans) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(plan.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WidgetPalette.secondary)
                        Text(plan.todayTitle)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .foregroundStyle(WidgetPalette.text)
                        HStack {
                            Text("Day \(plan.dayNumber) of \(plan.dayCount)")
                            Spacer()
                            if plan.isTodayComplete { Label("Done", systemImage: "checkmark.circle.fill") }
                        }
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.secondary)
                        ProgressView(value: plan.fractionComplete).tint(WidgetPalette.accent)
                    }
                }
            } else if let reading = snapshot.continueReading {
                Link(destination: GenesisLink.read(reading.verse)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Continue Reading").font(.caption.weight(.semibold)).foregroundStyle(WidgetPalette.secondary)
                        Text(reading.reference).font(.system(.title3, design: .serif, weight: .semibold)).foregroundStyle(WidgetPalette.text)
                        ProgressView(value: reading.bookProgress).tint(WidgetPalette.accent)
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                statTile(value: "\(snapshot.streakDays)", label: "day streak", symbol: "flame")
                statTile(value: "\(snapshot.chaptersRead)", label: "chapters read", symbol: "book.pages")
            }

            Link(destination: GenesisLink.prayer) {
                HStack(spacing: 10) {
                    Image(systemName: "hands.and.sparkles").foregroundStyle(WidgetPalette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.activePrayerCount == 1 ? "1 prayer" : "\(snapshot.activePrayerCount) prayers")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WidgetPalette.text)
                        if let reminder = snapshot.nextPrayerReminder {
                            Text("Next reminder \(reminder.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(WidgetPalette.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if let verse = snapshot.dailyVerse(on: entry.date) {
                Text("\u{201C}\(verse.text)\u{201D} \u{2014} \(verse.reference)")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(3)
            }
        }
        .containerBackground(for: .widget) { WidgetPalette.background }
    }

    private func statTile(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(WidgetPalette.accent)
            Text(value).font(.system(.title2, design: .serif, weight: .semibold)).foregroundStyle(WidgetPalette.text)
            Text(label).font(.caption2).foregroundStyle(WidgetPalette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lock screen streak

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Streak", provider: SnapshotProvider()) { entry in
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
