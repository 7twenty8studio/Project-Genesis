import Foundation
import Observation
import SwiftUI
import UIKit

enum ReadingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case page
    case scroll

    var id: String { rawValue }
    var title: String { self == .page ? String(localized: "Pages", comment: "Reading mode: page by page") : String(localized: "Scroll", comment: "Reading mode: continuous scrolling") }
}

enum PageTurnStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case slide
    case curl

    var id: String { rawValue }
    var title: String { self == .slide ? String(localized: "Slide", comment: "Page turn animation") : String(localized: "Page Curl") }
}

enum TextLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Verses flow together in paragraphs, like a printed book.
    case paragraphs
    /// Each verse starts on its own line.
    case versePerLine

    var id: String { rawValue }
    var title: String { self == .paragraphs ? String(localized: "Paragraphs") : String(localized: "Verse by Verse") }
}

enum ReaderMargins: String, Codable, CaseIterable, Identifiable, Sendable {
    case narrow, regular, wide

    var id: String { rawValue }
    var title: String {
        switch self {
        case .narrow: String(localized: "Narrow", comment: "Reader margins")
        case .regular: String(localized: "Regular", comment: "Reader margins")
        case .wide: String(localized: "Wide", comment: "Reader margins")
        }
    }

    /// Horizontal inset in points for a given container width.
    func inset(forWidth width: CGFloat) -> CGFloat {
        let base: CGFloat = switch self {
        case .narrow: 18
        case .regular: 28
        case .wide: 44
        }
        // Keep a comfortable measure (~70 characters) on wide screens.
        let maxLineWidth: CGFloat = 680
        return max(base, (width - maxLineWidth) / 2)
    }
}

/// How the chapter's large first letter is drawn.
enum InitialStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The letter, larger and in the accent colour.
    case plain
    /// The letter inside an ornamental frame, like a manuscript initial (Premium).
    case illuminated

    var id: String { rawValue }
    var title: String {
        switch self {
        case .plain: String(localized: "Classic", comment: "Large first letter style: a plain large letter")
        case .illuminated: String(localized: "Illuminated", comment: "Large first letter style: an ornamental manuscript initial")
        }
    }

    var isPremium: Bool { self == .illuminated }
}

/// Everything a person can adjust about reading. Stored as one JSON value so
/// new options can be added without migrations.
struct ReaderPreferences: Codable, Equatable, Sendable {
    var theme: ReaderTheme = .automatic
    var font: ReaderFont = .newYork
    var fontSize: Double = 19
    var lineSpacing: Double = 1.45
    var paragraphSpacing: Double = 0.55
    var margins: ReaderMargins = .regular
    var readingMode: ReadingMode = .page
    /// Kindle-like page curl by default. Use `choosePageTurn` to change it.
    var pageTurn: PageTurnStyle = .curl
    /// True once the person picks a page turn, so later default changes
    /// never override their choice.
    var pageTurnChosen = false
    var showsVerseNumbers = true
    var layout: TextLayout = .paragraphs
    var leftHanded = false
    var followsDynamicType = true
    /// Leaves, snow, blossom or summer light drifting by for a few seconds
    /// when the reader opens with a seasonal theme.
    var seasonalEffects = true
    /// A large first letter at the start of each chapter, as in printed Bibles.
    var largeInitial = true
    /// How the large first letter looks; illuminated needs Premium.
    var initialStyle: InitialStyle = .plain
    /// A soft paper rustle when a page turns (follows the silent switch).
    var pageTurnSound = false
    /// A light tap when a page turns.
    var pageTurnHaptic = true
    /// How loud the rustle is, 0…1 (five steps; 0.5 is the middle level).
    var pageTurnVolume = 0.5
    /// How firm the tap is, 0.2…1.
    var pageTurnHapticStrength = 0.9
    /// At night (with Dark Mode by default), switch to Night or Starlight (off by default).
    var nightReading = NightReadingSchedule()

    static let hapticStrengthRange: ClosedRange<Double> = 0.2...1

    static let fontSizeRange: ClosedRange<Double> = 13...36
    static let lineSpacingRange: ClosedRange<Double> = 1.1...2.1
    static let paragraphSpacingRange: ClosedRange<Double> = 0...1.5

    init() {}

    // Decode leniently so a missing or renamed key never resets everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReaderPreferences.defaults
        theme = (try? c.decode(ReaderTheme.self, forKey: .theme)) ?? d.theme
        font = (try? c.decode(ReaderFont.self, forKey: .font)) ?? d.font
        fontSize = (try? c.decode(Double.self, forKey: .fontSize)) ?? d.fontSize
        lineSpacing = (try? c.decode(Double.self, forKey: .lineSpacing)) ?? d.lineSpacing
        paragraphSpacing = (try? c.decode(Double.self, forKey: .paragraphSpacing)) ?? d.paragraphSpacing
        margins = (try? c.decode(ReaderMargins.self, forKey: .margins)) ?? d.margins
        readingMode = (try? c.decode(ReadingMode.self, forKey: .readingMode)) ?? d.readingMode
        pageTurnChosen = (try? c.decode(Bool.self, forKey: .pageTurnChosen)) ?? false
        // Early builds saved "slide" as an untouched default; only keep an explicit choice.
        pageTurn = pageTurnChosen ? ((try? c.decode(PageTurnStyle.self, forKey: .pageTurn)) ?? d.pageTurn) : d.pageTurn
        showsVerseNumbers = (try? c.decode(Bool.self, forKey: .showsVerseNumbers)) ?? d.showsVerseNumbers
        layout = (try? c.decode(TextLayout.self, forKey: .layout)) ?? d.layout
        leftHanded = (try? c.decode(Bool.self, forKey: .leftHanded)) ?? d.leftHanded
        followsDynamicType = (try? c.decode(Bool.self, forKey: .followsDynamicType)) ?? d.followsDynamicType
        seasonalEffects = (try? c.decode(Bool.self, forKey: .seasonalEffects)) ?? d.seasonalEffects
        largeInitial = (try? c.decode(Bool.self, forKey: .largeInitial)) ?? d.largeInitial
        initialStyle = (try? c.decode(InitialStyle.self, forKey: .initialStyle)) ?? d.initialStyle
        pageTurnSound = (try? c.decode(Bool.self, forKey: .pageTurnSound)) ?? d.pageTurnSound
        pageTurnHaptic = (try? c.decode(Bool.self, forKey: .pageTurnHaptic)) ?? d.pageTurnHaptic
        pageTurnVolume = (try? c.decode(Double.self, forKey: .pageTurnVolume)).map { min(max($0, 0), 1) } ?? d.pageTurnVolume
        pageTurnHapticStrength = (try? c.decode(Double.self, forKey: .pageTurnHapticStrength))
            .map { min(max($0, Self.hapticStrengthRange.lowerBound), Self.hapticStrengthRange.upperBound) } ?? d.pageTurnHapticStrength
        nightReading = (try? c.decode(NightReadingSchedule.self, forKey: .nightReading)) ?? d.nightReading
    }

    private static let defaults = ReaderPreferences()
}

/// Observable, persisted reader preferences shared across the app.
@MainActor
@Observable
final class ReaderSettings {
    var preferences: ReaderPreferences {
        didSet {
            guard preferences != oldValue else { return }
            save()
        }
    }

    /// The time night reading is judged by. RootView moves it on at each
    /// edge of the night window and when the app comes to the front, so the
    /// theme switches without redrawing every minute.
    var nightClock = Date.now

    /// Whether the system is in Dark Mode, for night reading "With Dark
    /// Mode". RootView keeps it up to date from the window scene, since the
    /// app's own colour scheme follows the reading theme.
    var systemIsDark = false

    /// UI tests: nil follows the clock, false never switches at night, true
    /// is always night (`-uiTestingNight`). Set once at launch.
    @ObservationIgnored var nightReadingOverride: Bool?

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "reader.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(ReaderPreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = ReaderPreferences()
        }
    }

    func reset() {
        preferences = ReaderPreferences()
    }

    /// The theme the person reads in right now, before Auto and Seasons are
    /// resolved: their chosen theme, or the night theme while Dark Mode is on
    /// or inside the night window. `premium` is `.premiumThemes` (Starlight
    /// falls back to Night).
    func currentTheme(premium: Bool, calendar: Calendar = .current) -> ReaderTheme {
        let schedule = preferences.nightReading
        let day = preferences.theme
        switch nightReadingOverride {
        case .some(false):
            return day
        case .some(true):
            return schedule.theme.theme(premium: premium) ?? day
        case .none:
            return NightReading.theme(for: schedule, dayTheme: day, now: nightClock, calendar: calendar, systemIsDark: systemIsDark, premium: premium)
        }
    }

    /// The theme to draw with now: night reading applied, then Auto and
    /// Seasons resolved for the appearance.
    func effectiveTheme(for scheme: ColorScheme, premium: Bool) -> ReaderTheme {
        currentTheme(premium: premium).resolved(for: scheme)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

/// Fully resolved values the text renderer needs. Equatable, so layout caches
/// can tell when they must be rebuilt.
struct ReaderStyle: Equatable {
    let font: ReaderFont
    let fontSize: CGFloat
    let lineHeightMultiple: CGFloat
    let paragraphSpacing: CGFloat
    let theme: ReaderTheme
    let showsVerseNumbers: Bool
    let layout: TextLayout
    /// Accessibility: mark highlights with patterns as well as colour.
    let differentiatesWithoutColor: Bool
    /// The language of the Bible being read ("en", "es"): book names in the
    /// text and running heads follow it, not the app's language.
    let bibleLanguage: String
    /// A large first letter at the start of the chapter.
    let largeInitial: Bool
    /// How that letter is drawn: illuminated only with Premium.
    let initialStyle: InitialStyle

    var palette: ThemePalette { theme.palette }

    /// - Parameter allowsPremiumLook: whether Premium typefaces and the
    ///   illuminated initial may be used; nil asks the app's
    ///   `EntitlementService` (`.premiumThemes`). Without Premium they fall
    ///   back to New York and the plain initial, the way a Premium theme
    ///   falls back to Automatic, while the saved choice is kept for when
    ///   Premium returns.
    @MainActor
    init(
        preferences: ReaderPreferences,
        theme: ReaderTheme,
        contentSizeCategory: UIContentSizeCategory,
        differentiatesWithoutColor: Bool = false,
        bibleLanguage: String = "en",
        allowsPremiumLook: Bool? = nil
    ) {
        let premium = allowsPremiumLook ?? (EntitlementService.app?.allows(.premiumThemes) ?? false)
        self.differentiatesWithoutColor = differentiatesWithoutColor
        self.bibleLanguage = bibleLanguage
        font = Self.resolvedFont(preferences.font, premium: premium)
        var size = CGFloat(preferences.fontSize)
        if preferences.followsDynamicType {
            // Scale the chosen size the way Dynamic Type scales body text.
            let traits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
            size = UIFontMetrics(forTextStyle: .body).scaledValue(for: size, compatibleWith: traits)
        }
        fontSize = size
        lineHeightMultiple = CGFloat(preferences.lineSpacing)
        paragraphSpacing = CGFloat(preferences.paragraphSpacing) * size
        self.theme = theme
        showsVerseNumbers = preferences.showsVerseNumbers
        layout = preferences.layout
        largeInitial = preferences.largeInitial
        initialStyle = Self.resolvedInitialStyle(preferences.initialStyle, premium: premium)
    }

    /// A Premium typeface only with Premium; otherwise the default, New York.
    static func resolvedFont(_ font: ReaderFont, premium: Bool) -> ReaderFont {
        premium || !font.isPremium ? font : .newYork
    }

    /// The illuminated initial only with Premium; otherwise plain.
    static func resolvedInitialStyle(_ style: InitialStyle, premium: Bool) -> InitialStyle {
        premium || !style.isPremium ? style : .plain
    }
}
