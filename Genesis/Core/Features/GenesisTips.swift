import SwiftUI
import TipKit

/// Small one-time hints (TipKit) the first time someone reaches a feature,
/// instead of a tutorial. At most one a day; each disappears once used.
enum GenesisTips {
    static let highlight = HighlightTip()
    static let listen = ListenTip()
    static let topics = TopicSearchTip()
    static let churchModeFocus = ChurchModeFocusTip()

    static func configure(testing: Bool) {
        // UI tests expect the screens without hints on top.
        if testing { Tips.hideAllTipsForTesting() }
        try? Tips.configure([.displayFrequency(.daily)])
    }
}

struct HighlightTip: Tip {
    var title: Text { Text("Highlight, note, share") }
    var message: Text? { Text("Press and hold a verse to highlight it, add a note, copy or share it.") }
    var image: Image? { Image(systemName: "highlighter") }
}

struct ListenTip: Tip {
    var title: Text { Text("Listen to this chapter") }
    var message: Text? { Text("Genesis reads aloud and turns the pages as it goes, even with your phone locked.") }
    var image: Image? { Image(systemName: "headphones") }
}

struct TopicSearchTip: Tip {
    var title: Text { Text("Search by topic") }
    var message: Text? { Text("Try a subject like forgiveness, fear or marriage to see the passages about it.") }
    var image: Image? { Image(systemName: "tag") }
}

/// Apps can't switch Do Not Disturb on, so Church Mode suggests it once.
struct ChurchModeFocusTip: Tip {
    var title: Text { Text("Quiet your phone") }
    var message: Text? { Text("Turn on Do Not Disturb or a Focus in Control Centre so nothing interrupts the sermon.") }
    var image: Image? { Image(systemName: "moon") }
}
