import Observation
import SwiftUI

enum AppTab: Hashable {
    case home, read, library, search
}

/// Screens pushed on the Home tab.
enum HomeRoute: Hashable {
    case plans
    case plan(UUID)
    case prayerJournal
}

/// App-wide navigation: which tab is showing, and opening the reader at a
/// passage from anywhere.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var homePath: [HomeRoute] = []
    var showsAccount = false
    @ObservationIgnored let reader: ReaderViewModel

    init(reader: ReaderViewModel) {
        self.reader = reader
    }

    func read(_ verse: VerseID) {
        reader.open(verse)
        tab = .read
    }

    func read(_ chapter: ChapterID) {
        read(chapter.firstVerse)
    }

    func read(_ reference: PassageReference) {
        read(reference.firstVerse)
    }

    func continueReading() {
        tab = .read
    }

    func open(_ route: HomeRoute) {
        tab = .home
        homePath = [route]
    }

    /// Handles genesis:// links from widgets and notifications.
    func handle(_ url: URL) {
        guard url.scheme == GenesisLink.scheme else { return }
        switch url.host() {
        case "read":
            if let raw = Int(url.lastPathComponent), raw > 1_000_000 {
                read(VerseID(rawValue: raw))
            } else {
                continueReading()
            }
        case "plans":
            open(.plans)
        case "prayer":
            open(.prayerJournal)
        default:
            tab = .home
        }
    }
}

extension EnvironmentValues {
    /// Colours for the active paper theme.
    @Entry var palette: ThemePalette = ReaderTheme.paper.palette
}
