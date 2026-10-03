import SwiftUI
import WidgetKit

@main
struct GenesisWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchVerseWidget()
    }
}

struct WatchVerseEntry: TimelineEntry {
    let date: Date
    let payload: WatchPayload?
}

/// One entry per day from what the phone last sent.
struct WatchVerseProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchVerseEntry {
        WatchVerseEntry(date: .now, payload: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchVerseEntry) -> Void) {
        completion(WatchVerseEntry(date: .now, payload: context.isPreview ? Self.sample : (WatchPayload.load() ?? Self.sample)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchVerseEntry>) -> Void) {
        let payload = WatchPayload.load()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var entries = [WatchVerseEntry(date: .now, payload: payload)]
        for offset in 1..<7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                entries.append(WatchVerseEntry(date: day, payload: payload))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static let sample = WatchPayload(
        generatedAt: .now,
        translation: "KJV",
        isPremium: true,
        verses: [WidgetSnapshot.DailyVerse(day: "", reference: String(localized: "Psalms 119:105", comment: "Bible reference"), text: "Thy word is a lamp unto my feet, and a light unto my path.", verse: 19_119_105)]
    )
}

/// The verse of the day on a watch face or in the Smart Stack.
struct WatchVerseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchVerse", provider: WatchVerseProvider()) { entry in
            WatchVerseView(entry: entry)
        }
        .configurationDisplayName("Verse of the Day")
        .description("A new verse each morning, from Genesis on your iPhone.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct WatchVerseView: View {
    let entry: WatchVerseEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let unlocked = entry.payload?.isPremium == true
        let verse = unlocked ? entry.payload?.verse(on: entry.date) : nil
        Group {
            switch family {
            case .accessoryInline:
                Text(verse?.reference ?? String(localized: "Verse of the Day"))
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "book.closed")
                        .font(.title3)
                }
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Text(verse?.reference ?? String(localized: "Verse of the Day"))
                        .font(.headline)
                        .widgetAccentable()
                    Text(verse?.text ?? (unlocked || entry.payload == nil ? String(localized: "Open Genesis on your iPhone.") : String(localized: "Part of Genesis Premium.")))
                        .font(.caption)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}
