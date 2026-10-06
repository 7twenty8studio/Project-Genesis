import UIKit

/// Resolved geometry and style for laying out reader text. Equatable, so the
/// page and scroll views know when to re-layout.
struct ReaderLayout: Equatable {
    var size: CGSize
    var safeArea: UIEdgeInsets
    var style: ReaderStyle
    var margins: ReaderMargins

    /// Space above and below the text for the running head and page footer.
    /// Tall enough that the floating reader controls (shown on a tap) sit
    /// in the margin above the first line rather than over it.
    static let headHeight: CGFloat = 56
    static let footHeight: CGFloat = 36

    var textInsets: UIEdgeInsets {
        let side = margins.inset(forWidth: size.width)
        return UIEdgeInsets(
            top: safeArea.top + Self.headHeight,
            left: side + safeArea.left,
            bottom: safeArea.bottom + Self.footHeight,
            right: side + safeArea.right
        )
    }

    /// The area one page of text may fill.
    var pageTextSize: CGSize {
        let insets = textInsets
        return CGSize(
            width: max(0, size.width - insets.left - insets.right),
            height: max(0, size.height - insets.top - insets.bottom)
        )
    }
}

/// A chapter split into pages for the current layout.
struct PaginatedChapter {
    let built: BuiltChapter
    let pages: [NSRange]

    var id: ChapterID { built.chapter.id }

    func pageIndex(containing verse: VerseID) -> Int {
        guard let offset = built.verseOffsets[verse] else { return 0 }
        return pages.firstIndex { NSLocationInRange(offset, $0) } ?? 0
    }

    func firstVerse(onPage index: Int) -> VerseID? {
        guard pages.indices.contains(index) else { return nil }
        return built.verse(atOffset: pages[index].location)
    }

    /// The first verse that begins on a page, so jumping back to it lands on
    /// this same page. Falls back to the verse continued from the page before.
    func anchorVerse(onPage index: Int) -> VerseID? {
        guard pages.indices.contains(index) else { return nil }
        let page = pages[index]
        let starting = built.verseOffsets
            .filter { NSLocationInRange($0.value, page) }
            .min { $0.value < $1.value }?
            .key
        return starting ?? firstVerse(onPage: index)
    }
}
