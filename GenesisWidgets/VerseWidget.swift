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

/// The verse widget's background, as people pick it when editing the
/// widget: "Chosen in Versely" (the default: the style picked with previews
/// in Settings › Widget Styles) or one of its own. The rest mirror
/// `WidgetArtStyle` (same raw values, saved in installed widgets: never
/// change them). Everything but Classic is Premium.
enum VerseWidgetBackground: String, AppEnum, CaseIterable {
    case app
    case classic, paper, autumn, winter, spring, summer, night, photo, vintage
    case instantPhoto, pressedFlowers, filmStrip, typewriter, libraryCard, calendarPage

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Background")

    static let caseDisplayRepresentations: [VerseWidgetBackground: DisplayRepresentation] = [
        .app: DisplayRepresentation(title: "Chosen in Versely"),
        .classic: DisplayRepresentation(title: "Classic"),
        .paper: DisplayRepresentation(title: "Paper"),
        .autumn: DisplayRepresentation(title: "Autumn"),
        .winter: DisplayRepresentation(title: "Winter"),
        .spring: DisplayRepresentation(title: "Spring"),
        .summer: DisplayRepresentation(title: "Summer"),
        .night: DisplayRepresentation(title: "Night"),
        .photo: DisplayRepresentation(title: "Your Photo"),
        .vintage: DisplayRepresentation(title: "Vintage"),
        .instantPhoto: DisplayRepresentation(title: "Instant Photo"),
        .pressedFlowers: DisplayRepresentation(title: "Pressed Flowers"),
        .filmStrip: DisplayRepresentation(title: "Film Strip"),
        .typewriter: DisplayRepresentation(title: "Typewriter"),
        .libraryCard: DisplayRepresentation(title: "Library Card"),
        .calendarPage: DisplayRepresentation(title: "Calendar Page"),
    ]

    /// The look to draw: the one chosen in Versely for `.app`.
    func style(in snapshot: WidgetSnapshot) -> WidgetArtStyle {
        self == .app ? snapshot.chosenVerseStyle : (WidgetArtStyle(rawValue: rawValue) ?? .classic)
    }
}

/// The verse widget's settings. Widgets installed before it existed have no
/// saved choice and get the default, the verse of the day, as before.
struct VerseWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Verse"
    static var description: IntentDescription { IntentDescription("Choose which verse the widget shows.") }

    @Parameter(title: "Show", default: .verseOfTheDay)
    var option: VerseWidgetOption

    /// Widgets with no saved choice follow the style chosen in Versely
    /// (Classic until one is, so they look as before).
    @Parameter(title: "Background", default: .app)
    var background: VerseWidgetBackground

    init() {}
}

// MARK: - Timeline

struct VerseEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let source: VerseWidgetSource
    var background: WidgetArtStyle = .classic
}

/// The verse of the day changes at midnight; Random Verse and the categories
/// every three hours (`VerseWidgetSchedule`).
struct VerseProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> VerseEntry {
        VerseEntry(date: .now, snapshot: .placeholder, source: .verseOfTheDay)
    }

    func snapshot(for configuration: VerseWidgetIntent, in context: Context) async -> VerseEntry {
        let snapshot = context.isPreview ? WidgetSnapshot.galleryPreview : (WidgetSnapshot.load() ?? .placeholder)
        return VerseEntry(date: .now, snapshot: snapshot, source: configuration.option.source, background: configuration.background.style(in: snapshot))
    }

    func timeline(for configuration: VerseWidgetIntent, in context: Context) async -> Timeline<VerseEntry> {
        let snapshot = WidgetSnapshot.load() ?? .placeholder
        let source = configuration.option.source
        let background = configuration.background.style(in: snapshot)
        var dates = VerseWidgetSchedule.entryDates(rotates: source.rotates, from: .now)
        // Seasonal backgrounds drift on: a step every minute for an hour.
        if SeasonalDrift.moves(background) {
            dates = SeasonalDrift.entryDates(adding: dates, from: .now)
        }
        return Timeline(entries: dates.map { VerseEntry(date: $0, snapshot: snapshot, source: source, background: background) }, policy: .atEnd)
    }
}

// MARK: - Widget

/// Free at every size with Verse of the Day or Random Verse in the Classic
/// look; the categories, From Your Reading and the backgrounds are Premium.
/// A Premium choice without Premium shows the verse of the day in the
/// Classic look with a small Premium tag, never a locked card. The kind is
/// unchanged from the earlier static widget, so installed widgets carry on.
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
        if art == .photo && WidgetArtImage.load(.photo, family: family) == nil {
            PremiumLockedView(message: String(localized: "Choose your photo in Versely: Settings › Widget Photo."), symbol: "photo.badge.plus")
        } else {
            let passage = entry.snapshot.passage(for: source, on: entry.date)
            let colors = WidgetColors(entry.snapshot)
            VerseWidgetContent(
                passage: passage,
                title: title,
                colors: colors,
                family: family,
                art: art,
                date: entry.date,
                isVerseOfTheDay: source == .verseOfTheDay,
                showsPremiumTag: showsPremiumTag
            )
            .containerBackground(for: .widget) {
                VerseWidgetBackdrop(art: art, colors: colors, family: family)
            }
            .widgetURL(passage.map { GenesisLink.read($0.verse) })
        }
    }

    private var isPremium: Bool { entry.snapshot.isPremium == true }

    /// The option shown: a Premium one without Premium falls back to the
    /// verse of the day (its verses aren't written without Premium).
    private var source: VerseWidgetSource {
        WidgetAccess.isUnlocked(entry.source, isPremium: isPremium) ? entry.source : .verseOfTheDay
    }

    /// The background shown: the Lock Screen's widgets have none, and a
    /// Premium one without Premium falls back to Classic.
    private var art: WidgetArtStyle {
        if WidgetSize(family).isAccessory { return .classic }
        return WidgetAccess.isUnlocked(entry.background, isPremium: isPremium) ? entry.background : .classic
    }

    /// A Premium option or background was chosen without Premium. The
    /// Lock Screen has no room for the tag; it just shows the free verse.
    private var showsPremiumTag: Bool {
        guard !WidgetSize(family).isAccessory else { return false }
        return source != entry.source || art != entry.background
    }

    /// The small capitals above the verse.
    private var title: String {
        switch source {
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
