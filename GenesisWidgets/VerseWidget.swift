import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration

/// The verse widget's options, as people pick them when editing the widget.
/// Mirrors `VerseWidgetSource` case for case (same raw values, which are
/// saved in installed widgets: never change them).
enum VerseWidgetOption: String, AppEnum, CaseIterable {
    case verseOfTheDay, random, fromYourReading
    case hope, peace, faith, strength, comfort, love, gratitude, guidance

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Verse")

    static let caseDisplayRepresentations: [VerseWidgetOption: DisplayRepresentation] = [
        .verseOfTheDay: DisplayRepresentation(title: "Verse of the Day"),
        .random: DisplayRepresentation(title: "Random Verse"),
        .fromYourReading: DisplayRepresentation(title: "From Your Reading"),
        .hope: DisplayRepresentation(title: "Hope"),
        .peace: DisplayRepresentation(title: "Peace"),
        .faith: DisplayRepresentation(title: "Faith"),
        .strength: DisplayRepresentation(title: "Strength"),
        .comfort: DisplayRepresentation(title: "Comfort"),
        .love: DisplayRepresentation(title: "Love"),
        .gratitude: DisplayRepresentation(title: "Gratitude"),
        .guidance: DisplayRepresentation(title: "Guidance"),
    ]

    var source: VerseWidgetSource { VerseWidgetSource(rawValue: rawValue) ?? .verseOfTheDay }
}

/// The verse widget's settings. Widgets installed before it existed have no
/// saved choice and get the default, the verse of the day, as before.
struct VerseWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Verse"
    static var description: IntentDescription { IntentDescription("Choose which verse the widget shows.") }

    @Parameter(title: "Show", default: .verseOfTheDay)
    var option: VerseWidgetOption

    init() {}
}

// MARK: - Timeline

struct VerseEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let source: VerseWidgetSource
}

/// The verse of the day changes at midnight; Random Verse and the categories
/// every three hours (`VerseWidgetSchedule`).
struct VerseProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> VerseEntry {
        VerseEntry(date: .now, snapshot: .placeholder, source: .verseOfTheDay)
    }

    func snapshot(for configuration: VerseWidgetIntent, in context: Context) async -> VerseEntry {
        let snapshot = context.isPreview ? .placeholder : (WidgetSnapshot.load() ?? .placeholder)
        return VerseEntry(date: .now, snapshot: snapshot, source: configuration.option.source)
    }

    func timeline(for configuration: VerseWidgetIntent, in context: Context) async -> Timeline<VerseEntry> {
        let snapshot = WidgetSnapshot.load() ?? .placeholder
        let source = configuration.option.source
        let dates = VerseWidgetSchedule.entryDates(rotates: source.rotates, from: .now)
        return Timeline(entries: dates.map { VerseEntry(date: $0, snapshot: snapshot, source: source) }, policy: .atEnd)
    }
}

// MARK: - Widget

/// Free as the small and medium Home Screen widget and on the Lock Screen
/// (verse of the day or a random verse); the large size and the categories
/// and From Your Reading are Premium. The kind is unchanged from the
/// earlier static widget, so installed widgets carry on.
struct DailyVerseWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.dailyVerse.rawValue, intent: VerseWidgetIntent.self, provider: VerseProvider()) { entry in
            DailyVerseView(entry: entry)
        }
        .configurationDisplayName("Verse of the Day")
        .description("A new verse each morning, a random verse, or verses on hope, peace and more.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct DailyVerseView: View {
    let entry: VerseEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let isPremium = entry.snapshot.isPremium == true
        if !entry.snapshot.unlocks(.dailyVerse, in: family) {
            PremiumLockedView(message: String(localized: "Larger verse widgets come with Genesis Premium."), symbol: "text.quote")
        } else if !WidgetAccess.isUnlocked(entry.source, size: WidgetSize(family), isPremium: isPremium) {
            PremiumLockedView(message: lockedMessage, symbol: entry.source == .fromYourReading ? "book.pages" : "sparkles")
        } else {
            VerseContentView(
                passage: entry.snapshot.passage(for: entry.source, on: entry.date),
                title: title,
                colors: WidgetColors(entry.snapshot),
                family: family
            )
        }
    }

    private var lockedMessage: String {
        entry.source == .fromYourReading
            ? String(localized: "Verses from your own reading come with Genesis Premium.")
            : String(localized: "Verses on hope, peace and more come with Genesis Premium.")
    }

    /// The small capitals above the verse.
    private var title: String {
        switch entry.source {
        case .verseOfTheDay: String(localized: "Verse of the Day")
        case .random: String(localized: "A Verse for You")
        case .fromYourReading: String(localized: "From Your Reading")
        case .hope: String(localized: "Hope")
        case .peace: String(localized: "Peace")
        case .faith: String(localized: "Faith")
        case .strength: String(localized: "Strength")
        case .comfort: String(localized: "Comfort")
        case .love: String(localized: "Love")
        case .gratitude: String(localized: "Gratitude")
        case .guidance: String(localized: "Guidance")
        }
    }
}

/// The verse itself, verbatim, set in a serif with room to breathe. Free
/// widgets follow light and dark; Premium ones the reading theme.
private struct VerseContentView: View {
    let passage: WidgetSnapshot.Passage?
    let title: String
    let colors: WidgetColors
    let family: WidgetFamily

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if WidgetSize(family).isAccessory { Color.clear } else { WidgetBackground(colors: colors) }
            }
            .widgetURL(passage.map { GenesisLink.read($0.verse) })
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text(passage?.reference ?? title)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(passage?.reference ?? title).font(.headline)
                Text(passage?.text ?? "").font(.system(.caption, design: .serif)).lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            homeScreen
        }
    }

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
            Eyebrow(text: title, color: colors.accent)
            Text(passage?.text ?? "")
                .font(.system(textStyle, design: .serif))
                .lineSpacing(family == .systemSmall ? 1 : 3)
                .foregroundStyle(colors.text)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Text(citation)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(colors.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textStyle: Font.TextStyle {
        switch family {
        case .systemSmall: .footnote
        case .systemLarge, .systemExtraLarge: .title3
        default: .body
        }
    }

    /// "Psalms 23:1 · KJV"
    private var citation: String {
        guard let passage else { return "" }
        return passage.reference + " \u{00B7} " + passage.translation
    }
}
