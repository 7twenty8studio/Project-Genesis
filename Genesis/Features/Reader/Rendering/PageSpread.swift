import UIKit

/// Two pages side by side, as in an open book (Reader settings › Two-Page
/// Spread). Only on a wide screen held sideways with the side panel closed:
/// anywhere else the reader shows one page, as before.
///
/// Each chapter starts on a left page. A chapter that ends on a left page
/// leaves the right one blank, so every spread is a left page (even index)
/// and the page after it.
enum PageSpread {
    /// The narrowest reading area that shows two pages (each then keeps
    /// about 400 points, a comfortable line).
    static let minimumWidth: CGFloat = 800
    /// Clearly wider than tall: never an upright screen or a square window.
    static let minimumAspect: CGFloat = 1.15

    static func shows(enabled: Bool, size: CGSize, sidePanelShown: Bool) -> Bool {
        guard enabled, !sidePanelShown, size.height > 0 else { return false }
        return size.width >= minimumWidth && size.width / size.height >= minimumAspect
    }

    /// The pages a chapter takes as spreads: an odd count gets a blank right page.
    static func slotCount(pages: Int) -> Int {
        pages + pages % 2
    }

    /// The left page of the spread that holds a page.
    static func leftIndex(of index: Int) -> Int {
        index - index % 2
    }

    static func isLeft(_ index: Int) -> Bool {
        index % 2 == 0
    }
}

extension ReaderLayout {
    /// One page of a spread: half the width, with the window's side inset
    /// (a camera or rounded corner) kept on the outer edge only. Both halves
    /// keep the same text width, so one pagination serves either side.
    func spreadPage(left: Bool) -> ReaderLayout {
        var page = self
        page.size.width = (size.width / 2).rounded(.down)
        let outer = max(safeArea.left, safeArea.right)
        page.safeArea.left = left ? outer : 0
        page.safeArea.right = left ? 0 : outer
        return page
    }
}
