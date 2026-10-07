import SwiftUI

/// Listening with follow-along in the parallel views (two Bibles, or a Bible
/// and its Hebrew or Greek): when the verse being read leaves the screen,
/// the scroll view brings its row back, as the single-Bible reader does.
/// Rows need `.id(verse number)` inside a `.scrollTargetLayout()` stack.
struct ParallelFollowAlong: ViewModifier {
    /// The verse number being read in this chapter, or nil.
    let playingRow: Int?
    /// How many rows are loaded, so a new chapter's verse is found once it arrives.
    let rowCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible: Set<Int> = []

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.8) { ids in
                    visible = Set(ids)
                }
                .onChange(of: FollowKey(row: playingRow, count: rowCount)) { _, key in
                    guard let row = key.row, key.count > 0, !visible.contains(row) else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                        proxy.scrollTo(row, anchor: UnitPoint(x: 0.5, y: 0.15))
                    }
                }
        }
    }

    private struct FollowKey: Equatable {
        let row: Int?
        let count: Int
    }
}

/// The soft mark behind the verse being read aloud, matching the reader's.
struct PlayingVerseMark: ViewModifier {
    let isPlaying: Bool
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.background {
            if isPlaying {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.accent.opacity(0.16))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            }
        }
    }
}
