import CoreGraphics
import Testing
import UIKit
@testable import Genesis

/// Two pages like an open book: only when it's chosen, wide, held sideways
/// and the side panel is closed; every spread starts on a left page.
@MainActor
@Suite("Two-page spread")
struct PageSpreadTests {
    @Test func showsOnAWideScreenHeldSideways() {
        // iPad landscape, panel closed.
        #expect(PageSpread.shows(enabled: true, size: CGSize(width: 1194, height: 834), sidePanelShown: false))
        #expect(PageSpread.shows(enabled: true, size: CGSize(width: 1024, height: 768), sidePanelShown: false))
    }

    @Test func onePageOtherwise() {
        let wide = CGSize(width: 1194, height: 834)
        // Not chosen.
        #expect(!PageSpread.shows(enabled: false, size: wide, sidePanelShown: false))
        // The side panel is open.
        #expect(!PageSpread.shows(enabled: true, size: wide, sidePanelShown: true))
        // Upright.
        #expect(!PageSpread.shows(enabled: true, size: CGSize(width: 834, height: 1194), sidePanelShown: false))
        // Too narrow (Split View, a phone on its side).
        #expect(!PageSpread.shows(enabled: true, size: CGSize(width: 700, height: 400), sidePanelShown: false))
        // Nearly square.
        #expect(!PageSpread.shows(enabled: true, size: CGSize(width: 900, height: 850), sidePanelShown: false))
        #expect(!PageSpread.shows(enabled: true, size: .zero, sidePanelShown: false))
    }

    @Test func aChapterEndingOnALeftPageGetsABlankRightPage() {
        #expect(PageSpread.slotCount(pages: 1) == 2)
        #expect(PageSpread.slotCount(pages: 2) == 2)
        #expect(PageSpread.slotCount(pages: 5) == 6)
        #expect(PageSpread.slotCount(pages: 0) == 0)
    }

    @Test func everySpreadStartsOnALeftPage() {
        #expect(PageSpread.leftIndex(of: 0) == 0)
        #expect(PageSpread.leftIndex(of: 1) == 0)
        #expect(PageSpread.leftIndex(of: 4) == 4)
        #expect(PageSpread.leftIndex(of: 5) == 4)
        #expect(PageSpread.isLeft(2))
        #expect(!PageSpread.isLeft(3))
    }

    @Test func bothHalvesKeepTheSameTextWidth() {
        let layout = ReaderLayout(
            size: CGSize(width: 1194, height: 834),
            safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 44),
            style: ReaderStyle(preferences: ReaderPreferences(), theme: .paper, contentSizeCategory: .large, allowsPremiumLook: false),
            margins: .regular
        )
        let left = layout.spreadPage(left: true)
        let right = layout.spreadPage(left: false)
        #expect(left.size.width == 597)
        #expect(left.pageTextSize == right.pageTextSize)
        // The window's inset stays on the outer edge only.
        #expect(left.safeArea.left == 44 && left.safeArea.right == 0)
        #expect(right.safeArea.left == 0 && right.safeArea.right == 44)
    }
}
