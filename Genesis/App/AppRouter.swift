import Observation
import SwiftUI

enum AppTab: Hashable {
    case home, read, library, explore, together, search
}

/// Screens pushed on the Together tab (groups and the community).
enum TogetherRoute: Hashable {
    case group(UUID)
    case post(CommunityPost)
    /// A church's published sermon, by its link's slug.
    case sermon(String)
    /// Find a church's sermons by its name.
    case churchSearch
}

/// A church sermon opened from its link (a Universal Link, a QR code or
/// versely://sermon/<slug>), shown over whatever tab is open.
struct SermonLinkRoute: Identifiable, Hashable {
    let slug: String
    var id: String { slug }
}

/// Screens pushed on the Explore tab (timeline, maps, people).
enum ExploreRoute: Hashable {
    case event(Int)
    case person(Int)
    case place(Int)
}

/// Screens pushed on the Home tab.
enum HomeRoute: Hashable {
    case plans
    case plan(UUID)
    case prayerJournal
    case insights
    case memorise
    case sermons
    /// Goals & Streaks: the daily goal, streak shields and milestones.
    case goals
}

/// App-wide navigation: which tab is showing, and opening the reader at a
/// passage from anywhere.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var homePath: [HomeRoute] = []
    var explorePath: [ExploreRoute] = []
    var togetherPath: [TogetherRoute] = []
    var showsAccount = false
    /// Search as a full-screen sheet, used on iPhone where Search isn't a tab.
    var showsSearch = false
    /// A church sermon opened from its link.
    var sermonLink: SermonLinkRoute?
    @ObservationIgnored let reader: ReaderViewModel

    init(reader: ReaderViewModel) {
        self.reader = reader
    }

    func read(_ verse: VerseID) {
        reader.open(verse)
        // Out of a sermon opened from its link, into the reader.
        sermonLink = nil
        tab = .read
    }

    func read(_ chapter: ChapterID) {
        read(chapter.firstVerse)
    }

    func read(_ reference: PassageReference) {
        read(reference.firstVerse)
    }

    /// Opens search: the Search tab on iPad and the open Duo, a sheet on iPhone.
    func openSearch(asTab: Bool) {
        if asTab { tab = .search } else { showsSearch = true }
    }

    func continueReading() {
        tab = .read
    }

    func explore(_ route: ExploreRoute) {
        tab = .explore
        explorePath.append(route)
    }

    /// A group's page, e.g. from an announcement notification.
    func openGroup(_ id: UUID) {
        tab = .together
        togetherPath = [.group(id)]
    }

    func open(_ route: HomeRoute) {
        tab = .home
        homePath = [route]
    }

    /// A church sermon from its link.
    func openSermon(slug: String) {
        sermonLink = SermonLinkRoute(slug: slug)
    }

    /// Handles versely:// links from widgets and notifications, and a
    /// church sermon's link (https://versely.7twenty8studio.com/s/<slug>,
    /// a Universal Link, or versely://sermon/<slug>).
    func handle(_ url: URL) {
        if let slug = ChurchSermonLink.slug(in: url) {
            openSermon(slug: slug)
            return
        }
        guard url.scheme == GenesisLink.scheme else { return }
        // Sign in with Google's return address belongs to its web sheet.
        if GoogleOAuth.isCallback(url) { return }
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
        case "memorise":
            open(.memorise)
        case "sermons":
            open(.sermons)
        case "insights":
            open(.insights)
        case "group":
            if let id = UUID(uuidString: url.lastPathComponent) { openGroup(id) } else { tab = .together }
        default:
            tab = .home
        }
    }
}

extension EnvironmentValues {
    /// Colours for the active paper theme.
    @Entry var palette: ThemePalette = ReaderTheme.paper.palette
    /// People, places and events (nil if Study.sqlite is missing from the build).
    @Entry var studyData: StudyRepository? = nil
}
