import Foundation

/// Keeps a left-to-right verse laid out left to right. The KJV and ASV open
/// each stanza of Psalm 119 with its Hebrew letter ("נ NUN. Thy word is a
/// lamp…"); iOS takes a paragraph's direction from its first strong letter,
/// so without help the whole line is set right to left (".path" at the
/// start). Display only: a left-to-right mark (U+200E, invisible) goes
/// before each line; the words are never changed, and copies, shares, the
/// memory games and the study assistant keep using the verse's own text.
enum ScriptureDirection {
    private static let mark: Character = "\u{200E}"

    /// `text` ready to show, marked left to right when it mixes a
    /// right-to-left letter into a left-to-right (Latin-script) verse.
    /// A verse that is all Hebrew, or has no Hebrew, is returned as it is.
    static func display(_ text: String) -> String {
        guard needsMark(text) else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String(mark) + $0 }
            .joined(separator: "\n")
    }

    /// True when the text holds both a right-to-left letter and a Latin one.
    static func needsMark(_ text: String) -> Bool {
        var hasRightToLeft = false
        var hasLatin = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF:
                hasRightToLeft = true
            case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F:
                hasLatin = true
            default:
                break
            }
            if hasRightToLeft && hasLatin { return true }
        }
        return false
    }
}
