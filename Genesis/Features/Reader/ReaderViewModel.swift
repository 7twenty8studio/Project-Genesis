import Foundation
import Observation
import SwiftData

/// State and actions for the reader: which chapter is open, selection,
/// controls visibility and study actions on the selected verses.
@MainActor
@Observable
final class ReaderViewModel {
    /// The chapter currently on screen.
    private(set) var chapterID: ChapterID
    /// A verse to bring into view. Changes to `navigationToken` tell the
    /// page or scroll view to jump there.
    private(set) var focusVerse: VerseID
    private(set) var navigationToken = 0

    var selection: Set<VerseID> = []
    /// The verse the study panel is about; falls back to the top of the page.
    var studyVerse: VerseID?
    var showsControls = true
    /// Bumped whenever highlights, notes or bookmarks change, so views redraw.
    private(set) var decorationsVersion = 0

    var isSelecting: Bool { !selection.isEmpty }

    @ObservationIgnored let library: BibleLibrary
    @ObservationIgnored let progress: ReadingProgress
    @ObservationIgnored var modelContext: ModelContext?
    @ObservationIgnored private var chapterCache: [String: Chapter] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []

    init(library: BibleLibrary, progress: ReadingProgress) {
        self.library = library
        self.progress = progress
        chapterID = progress.position.chapterID
        focusVerse = progress.position
    }

    var translation: Translation { library.currentTranslation }
    var chapter: Chapter? { loadChapter(chapterID) }

    // MARK: Loading

    /// Loads a chapter from the current translation, with a small cache so
    /// page turns across chapter boundaries never wait on disk.
    func loadChapter(_ id: ChapterID) -> Chapter? {
        let key = "\(translation.id)-\(id.book)-\(id.chapter)"
        if let cached = chapterCache[key] { return cached }
        do {
            let chapter = try library.current.chapter(id)
            chapterCache[key] = chapter
            cacheOrder.append(key)
            if cacheOrder.count > 12 {
                chapterCache.removeValue(forKey: cacheOrder.removeFirst())
            }
            return chapter
        } catch {
            CrashReporter.record(error, context: "Reader.loadChapter")
            return nil
        }
    }

    func decorations(for id: ChapterID) -> ChapterDecorations {
        guard let modelContext else { return ChapterDecorations(selection: selection) }
        let store = StudyStore(context: modelContext)
        let noted = store.notes(in: id).compactMap { note -> VerseID? in
            if case let .verses(_, end) = note.anchor { return end }
            return nil
        }
        return ChapterDecorations(
            highlights: store.highlightColors(in: id),
            selection: selection,
            notedVerses: Set(noted)
        )
    }

    // MARK: Navigation

    func open(_ verse: VerseID) {
        selection = []
        studyVerse = nil
        chapterID = verse.chapterID
        focusVerse = verse
        navigationToken += 1
        progress.update(verse)
    }

    func open(_ chapter: ChapterID) {
        open(chapter.firstVerse)
    }

    func goToNextChapter() {
        if let next = chapterID.next { open(next) }
    }

    func goToPreviousChapter() {
        if let previous = chapterID.previous { open(previous) }
    }

    /// Called by the page or scroll view when the person moves through the text.
    func didShow(chapter: ChapterID, firstVerse: VerseID?) {
        if chapter != chapterID {
            chapterID = chapter
            selection = []
        }
        let verse = firstVerse ?? chapter.firstVerse
        focusVerse = verse
        progress.update(verse)
    }

    func switchTranslation(to translation: Translation) {
        guard translation != library.currentTranslation else { return }
        library.currentTranslation = translation
        chapterCache.removeAll()
        cacheOrder.removeAll()
        navigationToken += 1
    }

    // MARK: Interaction

    func toggleControls() {
        showsControls.toggle()
    }

    /// Keyboard and accessibility page turns; the page view watches the token.
    private(set) var pageTurnToken = 0
    private(set) var pageTurnForward = true

    func requestPageTurn(forward: Bool) {
        pageTurnForward = forward
        pageTurnToken += 1
    }

    func toggleSelection(_ verse: VerseID) {
        if selection.contains(verse) {
            selection.remove(verse)
        } else {
            // Selection stays within one chapter.
            if let first = selection.first, first.chapterID != verse.chapterID { selection = [] }
            selection.insert(verse)
        }
        decorationsVersion += 1
    }

    func clearSelection() {
        guard !selection.isEmpty else { return }
        selection = []
        decorationsVersion += 1
    }

    var selectedVerses: [Verse] {
        guard let chapter = loadChapter(selection.first?.chapterID ?? chapterID) else { return [] }
        return chapter.verses.filter { selection.contains($0.id) }
    }

    var selectedReference: PassageReference? { PassageReference(verses: selection) }

    // MARK: Study actions

    func highlightSelection(_ color: HighlightColor) {
        guard let modelContext else { return }
        StudyStore(context: modelContext).highlight(selection, color: color)
        selection = []
        decorationsVersion += 1
    }

    func removeHighlightFromSelection() {
        guard let modelContext else { return }
        StudyStore(context: modelContext).removeHighlights(selection)
        selection = []
        decorationsVersion += 1
    }

    /// Bookmarks the selected verse, or the current position if nothing is selected.
    @discardableResult
    func toggleBookmark() -> Bool {
        guard let modelContext else { return false }
        let verse = selection.min() ?? focusVerse
        let added = StudyStore(context: modelContext).toggleBookmark(at: verse)
        decorationsVersion += 1
        return added
    }

    var isCurrentChapterBookmarked: Bool {
        _ = decorationsVersion
        guard let modelContext else { return false }
        return !StudyStore(context: modelContext).bookmarks(in: chapterID).isEmpty
    }

    /// Creates a note on the selected verses (or the chapter) and returns it for editing.
    func makeNoteForSelection(kind: NoteKind = .text) -> Note? {
        guard let modelContext else { return nil }
        let anchor: NoteAnchor = if let first = selection.min(), let last = selection.max() {
            .verses(first, last)
        } else {
            .chapter(chapterID)
        }
        let note = StudyStore(context: modelContext).createNote(kind: kind, anchor: anchor)
        selection = []
        decorationsVersion += 1
        return note
    }

    func notesDidChange() {
        decorationsVersion += 1
    }

    var shareTextForSelection: String {
        ChapterTextBuilder.shareText(for: selectedVerses, translation: translation)
    }
}
