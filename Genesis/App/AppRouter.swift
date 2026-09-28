import Observation
import SwiftUI

enum AppTab: Hashable {
    case home, read, library, search
}

/// App-wide navigation: which tab is showing, and opening the reader at a
/// passage from anywhere.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
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
}

extension EnvironmentValues {
    /// Colours for the active paper theme.
    @Entry var palette: ThemePalette = ReaderTheme.paper.palette
}
