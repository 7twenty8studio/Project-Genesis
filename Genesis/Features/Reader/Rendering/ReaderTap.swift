import CoreGraphics

/// What a single tap on the reader's text does:
/// - while verses are selected, a tap adds or removes a verse (or clears
///   the selection when it lands on no verse);
/// - in paged reading, a tap in the page's outer edge (the margin and a
///   little more) turns the page;
/// - a tap on a verse selects it, so highlighting is one tap away;
/// - a tap anywhere else (the running head, the page number, blank space)
///   shows or hides the reader controls.
/// Long-pressing a verse still selects it too.
enum ReaderTap {
    enum Action: Equatable {
        case turnPage(forward: Bool)
        case toggleSelection(VerseID)
        case clearSelection
        case toggleControls
    }

    /// How wide the page-turn edge is: the margin plus 10 points, at least
    /// 32 points (an easy target) and never more than 15% of the page, so
    /// it reaches only the first letters of a line.
    static func edgeWidth(margin: CGFloat, pageWidth: CGFloat) -> CGFloat {
        min(max(margin + 10, 32), pageWidth * 0.15)
    }

    static func action(
        x: CGFloat,
        pageWidth: CGFloat,
        leftMargin: CGFloat,
        rightMargin: CGFloat,
        verse: VerseID?,
        isSelecting: Bool,
        turnsPages: Bool,
        leftHanded: Bool
    ) -> Action {
        if isSelecting {
            return verse.map { .toggleSelection($0) } ?? .clearSelection
        }
        if turnsPages, pageWidth > 0 {
            // Left-handed readers turn forward from the left edge.
            if x < edgeWidth(margin: leftMargin, pageWidth: pageWidth) { return .turnPage(forward: leftHanded) }
            if x > pageWidth - edgeWidth(margin: rightMargin, pageWidth: pageWidth) { return .turnPage(forward: !leftHanded) }
        }
        if let verse { return .toggleSelection(verse) }
        return .toggleControls
    }
}
