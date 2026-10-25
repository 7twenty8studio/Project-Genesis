import Testing
@testable import Genesis

@Suite("Recent highlight colors")
struct RecentHighlightColorsTests {
    @Test func startsWithTheDefaultOrder() {
        #expect(RecentHighlightColors.shown(from: "") == [.yellow, .blue, .green])
    }

    @Test func theLastColorUsedComesFirst() {
        var stored = ""
        stored = RecentHighlightColors.recording(.pink, in: stored)
        #expect(RecentHighlightColors.shown(from: stored) == [.pink, .yellow, .blue])
        stored = RecentHighlightColors.recording(.orange, in: stored)
        stored = RecentHighlightColors.recording(.pink, in: stored)
        #expect(RecentHighlightColors.shown(from: stored) == [.pink, .orange, .yellow])
        // Each color once.
        #expect(stored == "pink,orange")
    }

    @Test func unknownValuesAreIgnored() {
        #expect(RecentHighlightColors.shown(from: "teal,,green") == [.green, .yellow, .blue])
    }
}
