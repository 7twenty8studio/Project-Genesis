import Foundation
import Observation
import UIKit

enum ReadingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case page
    case scroll

    var id: String { rawValue }
    var title: String { self == .page ? "Pages" : "Scroll" }
}

enum PageTurnStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case slide
    case curl

    var id: String { rawValue }
    var title: String { self == .slide ? "Slide" : "Page Curl" }
}

enum TextLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Verses flow together in paragraphs, like a printed book.
    case paragraphs
    /// Each verse starts on its own line.
    case versePerLine

    var id: String { rawValue }
    var title: String { self == .paragraphs ? "Paragraphs" : "Verse by Verse" }
}

enum ReaderMargins: String, Codable, CaseIterable, Identifiable, Sendable {
    case narrow, regular, wide

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

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
    var pageTurn: PageTurnStyle = .slide
    var showsVerseNumbers = true
    var layout: TextLayout = .paragraphs
    var leftHanded = false
    var followsDynamicType = true

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
        pageTurn = (try? c.decode(PageTurnStyle.self, forKey: .pageTurn)) ?? d.pageTurn
        showsVerseNumbers = (try? c.decode(Bool.self, forKey: .showsVerseNumbers)) ?? d.showsVerseNumbers
        layout = (try? c.decode(TextLayout.self, forKey: .layout)) ?? d.layout
        leftHanded = (try? c.decode(Bool.self, forKey: .leftHanded)) ?? d.leftHanded
        followsDynamicType = (try? c.decode(Bool.self, forKey: .followsDynamicType)) ?? d.followsDynamicType
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

    var palette: ThemePalette { theme.palette }

    init(preferences: ReaderPreferences, theme: ReaderTheme, contentSizeCategory: UIContentSizeCategory) {
        font = preferences.font
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
    }
}
