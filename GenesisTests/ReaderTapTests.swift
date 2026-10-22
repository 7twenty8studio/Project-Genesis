import CoreGraphics
import Testing
@testable import Genesis

/// A single tap on the reader: verses select, the page's very edge turns,
/// anywhere else shows the controls.
@Suite("Reader taps")
struct ReaderTapTests {
    private let verse = VerseID(book: 1, chapter: 1, verse: 3)

    private func tap(_ x: CGFloat, width: CGFloat = 390, margin: CGFloat = 28, verse: VerseID?, selecting: Bool = false, pages: Bool = true, leftHanded: Bool = false) -> ReaderTap.Action {
        ReaderTap.action(x: x, pageWidth: width, leftMargin: margin, rightMargin: margin,
                         verse: verse, isSelecting: selecting, turnsPages: pages, leftHanded: leftHanded)
    }

    @Test func aTapOnAVerseSelectsIt() {
        #expect(tap(120, verse: verse) == .toggleSelection(verse))
        // Near the start of a line, but past the margin and a little more.
        #expect(tap(45, verse: verse) == .toggleSelection(verse))
        #expect(tap(345, verse: verse) == .toggleSelection(verse))
    }

    @Test func theVeryEdgeTurnsThePage() {
        #expect(ReaderTap.edgeWidth(margin: 28, pageWidth: 390) == 38)
        #expect(tap(20, verse: verse) == .turnPage(forward: false))
        #expect(tap(375, verse: verse) == .turnPage(forward: true))
        #expect(tap(20, verse: nil, leftHanded: true) == .turnPage(forward: true))
    }

    @Test func theEdgeIsAnEasyTargetButNeverWide() {
        #expect(ReaderTap.edgeWidth(margin: 18, pageWidth: 390) == 32)
        // iPad: wide margins keep the turning edge to 15% of the page.
        #expect(ReaderTap.edgeWidth(margin: 172, pageWidth: 1024) == 1024 * 0.15)
    }

    @Test func blankSpaceShowsTheControls() {
        #expect(tap(195, verse: nil) == .toggleControls)
    }

    @Test func whileSelectingTapsChangeTheSelection() {
        #expect(tap(20, verse: verse, selecting: true) == .toggleSelection(verse))
        #expect(tap(195, verse: nil, selecting: true) == .clearSelection)
    }

    @Test func scrollingHasNoTurningEdges() {
        #expect(tap(10, verse: verse, pages: false) == .toggleSelection(verse))
        #expect(tap(10, verse: nil, pages: false) == .toggleControls)
    }

    @Test func theAnnouncementIsNew() {
        let ids = WhatsNewCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.last == "tap-to-select")
    }
}
