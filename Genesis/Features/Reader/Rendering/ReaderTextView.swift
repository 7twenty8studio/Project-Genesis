import UIKit

/// What happened when the person touched the text.
enum ReaderTextEvent {
    /// A tap; `location` is in the text view's coordinates, `verse` is the verse under it.
    case tap(location: CGPoint, bounds: CGRect, verse: VerseID?)
    /// A long press on a verse, which starts verse selection; `word` is the
    /// word under the finger, for looking up its Hebrew or Greek.
    case longPress(verse: VerseID, word: PressedWord?)
}

/// Displays reader text with TextKit 1 (matching `Paginator`) and reports taps
/// and long presses with the verse under the finger.
final class ReaderTextView: UITextView {
    var onEvent: ((ReaderTextEvent) -> Void)?

    /// Layout managers don't retain their text storage, so the view keeps it.
    private let ownedStorage: NSTextStorage

    init(scrollable: Bool) {
        // Build an explicit TextKit 1 stack so layout matches `Paginator` exactly.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = !scrollable
        layout.addTextContainer(container)
        ownedStorage = storage
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = false
        isScrollEnabled = scrollable
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        adjustsFontForContentSizeCategory = false
        showsVerticalScrollIndicator = scrollable
        alwaysBounceVertical = scrollable
        contentInsetAdjustmentBehavior = .never
        accessibilityTraits.insert(.staticText)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        press.minimumPressDuration = 0.35
        tap.require(toFail: press)
        addGestureRecognizer(tap)
        addGestureRecognizer(press)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The verse drawn at a point, if any.
    func verse(at point: CGPoint) -> VerseID? {
        guard textStorage.length > 0 else { return nil }
        let location = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        let glyphIndex = layoutManager.glyphIndex(for: location, in: textContainer)
        // Ignore taps in empty space beyond the end of a line.
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        guard glyphRect.insetBy(dx: -12, dy: -6).contains(location) else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length,
              let raw = textStorage.attribute(.verseID, at: characterIndex, effectiveRange: nil) as? Int else { return nil }
        return VerseID(rawValue: raw)
    }

    /// The word drawn at a point, with its verse and which copy of it in the
    /// verse it is (counted within this view's text).
    func word(at point: CGPoint, in verse: VerseID) -> PressedWord? {
        guard textStorage.length > 0 else { return nil }
        let location = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        let glyphIndex = layoutManager.glyphIndex(for: location, in: textContainer)
        let index = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let text = textStorage.string as NSString
        guard index < text.length, Self.isWordCharacter(text.character(at: index)) else { return nil }
        var start = index
        while start > 0, Self.isWordCharacter(text.character(at: start - 1)) { start -= 1 }
        var end = index + 1
        while end < text.length, Self.isWordCharacter(text.character(at: end)) { end += 1 }
        let word = text.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\u{2019}"))
        guard !word.isEmpty else { return nil }
        // Earlier copies of the word in the same verse.
        var verseRange = NSRange()
        _ = textStorage.attribute(.verseID, at: index, longestEffectiveRange: &verseRange, in: NSRange(location: 0, length: textStorage.length))
        let before = text.substring(with: NSRange(location: verseRange.location, length: max(0, start - verseRange.location)))
        let occurrence = VerseWords.ranges(in: before).filter { before[$0].caseInsensitiveCompare(word) == .orderedSame }.count
        return PressedWord(verse: verse, text: word, occurrence: occurrence)
    }

    private static func isWordCharacter(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.letters.contains(scalar) || unit == 0x27 || unit == 0x2019
    }

    /// The first verse whose text is visible, for remembering the position.
    func firstVisibleVerse() -> VerseID? {
        guard textStorage.length > 0 else { return nil }
        let top = CGPoint(x: bounds.midX - textContainerInset.left, y: contentOffset.y + contentInset.top - textContainerInset.top + 4)
        let glyphIndex = layoutManager.glyphIndex(for: top, in: textContainer)
        var index = layoutManager.characterIndexForGlyph(at: glyphIndex)
        while index < textStorage.length {
            var range = NSRange()
            if let raw = textStorage.attribute(.verseID, at: index, effectiveRange: &range) as? Int {
                return VerseID(rawValue: raw)
            }
            index = NSMaxRange(range)
        }
        return nil
    }

    /// Vertical position of a character offset, for scrolling to a verse.
    func yOffset(ofCharacter offset: Int) -> CGFloat {
        guard offset < textStorage.length else { return 0 }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: offset, length: 1), actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer).minY + textContainerInset.top
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: self)
        onEvent?(.tap(location: location, bounds: bounds, verse: verse(at: location)))
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: self)
        guard recognizer.state == .began, let verse = verse(at: location) else { return }
        onEvent?(.longPress(verse: verse, word: word(at: location, in: verse)))
    }
}
