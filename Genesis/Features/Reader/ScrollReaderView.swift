import SwiftUI
import UIKit

/// Continuous scroll mode: one chapter per view, swipe sideways for the
/// next or previous chapter.
struct ScrollReaderView: UIViewRepresentable {
    let viewModel: ReaderViewModel
    let layout: ReaderLayout
    let navigationToken: Int
    let decorationsVersion: Int
    let translationID: String
    let chapterID: ChapterID
    /// How much of the bottom the selection bar covers (0 when nothing is
    /// selected): the selected verses are kept above it.
    var bottomObstruction: CGFloat = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> ReaderTextView {
        let textView = ReaderTextView(scrollable: true)
        textView.accessibilityIdentifier = "reader.scroll"
        textView.delegate = context.coordinator
        textView.onEvent = { [weak coordinator = context.coordinator] event in coordinator?.handle(event) }

        let next = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipedNext))
        next.direction = .left
        let previous = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipedPrevious))
        previous.direction = .right
        for swipe in [next, previous] {
            // Recognise alongside the vertical scroll pan.
            swipe.delegate = context.coordinator
            textView.addGestureRecognizer(swipe)
        }
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ textView: ReaderTextView, context: Context) {
        context.coordinator.setObstruction(bottomObstruction)
        context.coordinator.update(
            layout: layout,
            chapterID: chapterID,
            navigationToken: navigationToken,
            decorationsVersion: decorationsVersion,
            translationID: translationID
        )
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        let viewModel: ReaderViewModel
        weak var textView: ReaderTextView?

        private var layout: ReaderLayout?
        private var built: BuiltChapter?
        private var navigationToken = -1
        private var decorationsVersion = -1
        private var translationID = ""
        private var followedVerse: VerseID?
        private var obstruction: CGFloat = 0

        init(viewModel: ReaderViewModel) {
            self.viewModel = viewModel
        }

        func update(layout newLayout: ReaderLayout, chapterID: ChapterID, navigationToken token: Int, decorationsVersion version: Int, translationID translation: String) {
            guard let textView else { return }
            let chapterChanged = built?.chapter.id != chapterID
            let navigated = token != navigationToken
            let restyled = newLayout != layout || translation != translationID
            let redecorated = version != decorationsVersion
            guard chapterChanged || navigated || restyled || redecorated else { return }

            let keepOffset = !chapterChanged && !navigated
            let previousVerse = keepOffset ? textView.firstVisibleVerse() : nil

            layout = newLayout
            navigationToken = token
            decorationsVersion = version
            translationID = translation

            guard let chapter = viewModel.loadChapter(chapterID) else { return }
            let built = ChapterTextBuilder.build(chapter, style: newLayout.style, decorations: viewModel.decorations(for: chapterID))
            self.built = built

            textView.backgroundColor = PaperTexture.pageColor(for: newLayout.style.theme)
            var insets = newLayout.textInsets
            insets.bottom += 80
            textView.textContainerInset = insets
            textView.accessibilityLabel = chapter.id.description(in: newLayout.style.bibleLanguage)

            if redecorated && !restyled && !chapterChanged && !navigated {
                // Only colours or underlines changed: keep the exact scroll position.
                let offset = textView.contentOffset
                textView.attributedText = built.text
                textView.layoutIfNeeded()
                textView.setContentOffset(offset, animated: false)
                keepPlayingVerseVisible()
                keepSelectionVisible()
                return
            }

            textView.attributedText = built.text
            textView.layoutIfNeeded()
            let target = previousVerse ?? viewModel.focusVerse
            scroll(to: target, animated: false)
        }

        /// The selection bar's height: room below the text while it shows, so
        /// the last verses can scroll above it.
        func setObstruction(_ height: CGFloat) {
            guard let textView, abs(height - obstruction) > 0.5 else { return }
            let appeared = obstruction == 0 && height > 0
            obstruction = height
            textView.contentInset.bottom = height
            textView.verticalScrollIndicatorInsets.bottom = height
            if appeared || height > 0 { keepSelectionVisible() }
        }

        /// Scrolls just enough that the last selected verse ends above the
        /// selection bar, without pushing the first one off the top.
        private func keepSelectionVisible() {
            guard let textView, let built, obstruction > 0 else { return }
            let selected = viewModel.selection.filter { $0.chapterID == built.chapter.id }
            guard let first = selected.min(), let last = selected.max(),
                  let firstStart = built.verseOffsets[first], let lastStart = built.verseOffsets[last] else { return }
            let nextStart = built.verseOffsets.values.filter { $0 > lastStart }.min() ?? built.text.length
            let lastCharacter = min(max(lastStart, nextStart - 1), built.text.length - 1)
            guard lastCharacter >= 0 else { return }
            let lineHeight = (layout?.style.fontSize ?? 18) * 1.8
            let bottom = textView.yOffset(ofCharacter: lastCharacter) + lineHeight
            let visibleBottom = textView.contentOffset.y + textView.bounds.height - obstruction - 12
            guard bottom > visibleBottom else { return }
            let firstTop = textView.yOffset(ofCharacter: firstStart) - 12
            let maxY = max(0, textView.contentSize.height + obstruction - textView.bounds.height)
            let target = min(textView.contentOffset.y + bottom - visibleBottom, firstTop, maxY)
            guard target > textView.contentOffset.y else { return }
            textView.setContentOffset(CGPoint(x: 0, y: target), animated: !UIAccessibility.isReduceMotionEnabled)
        }

        /// Listening with follow-along: scroll when the verse being read is off screen.
        private func keepPlayingVerseVisible() {
            guard let textView, let built, let playing = viewModel.playingVerse, playing != followedVerse,
                  playing.chapterID == built.chapter.id, let offset = built.verseOffsets[playing] else { return }
            followedVerse = playing
            let y = textView.yOffset(ofCharacter: offset)
            let top = textView.contentOffset.y + textView.textContainerInset.top
            let bottom = textView.contentOffset.y + textView.bounds.height - textView.textContainerInset.bottom - 60
            guard y < top || y > bottom else { return }
            scroll(to: playing, animated: !UIAccessibility.isReduceMotionEnabled)
        }

        private func scroll(to verse: VerseID, animated: Bool) {
            guard let textView, let built else { return }
            guard verse.chapterID == built.chapter.id, verse.verse > 1, let offset = built.verseOffsets[verse] else {
                textView.setContentOffset(.zero, animated: animated)
                return
            }
            let y = max(0, textView.yOffset(ofCharacter: offset) - (layout?.textInsets.top ?? 0))
            let maxY = max(0, textView.contentSize.height - textView.bounds.height)
            textView.setContentOffset(CGPoint(x: 0, y: min(y, maxY)), animated: animated)
        }

        func handle(_ event: ReaderTextEvent) {
            switch event {
            case let .longPress(verse):
                viewModel.toggleSelection(verse)
            case let .footnote(text, verse):
                viewModel.showFootnote(text, verse: verse)
            case let .link(url):
                UIApplication.shared.open(url)
            case let .tap(point, bounds, verse):
                // No page edges here: scrolling moves through the chapter.
                let action = ReaderTap.action(
                    x: point.x, pageWidth: bounds.width, leftMargin: 0, rightMargin: 0,
                    verse: verse, isSelecting: viewModel.isSelecting, turnsPages: false, leftHanded: false
                )
                switch action {
                case let .toggleSelection(verse): viewModel.toggleSelection(verse)
                case .clearSelection: viewModel.clearSelection()
                case .toggleControls, .turnPage: viewModel.toggleControls()
                }
            }
        }

        @objc func swipedNext() { viewModel.goToNextChapter() }
        @objc func swipedPrevious() { viewModel.goToPreviousChapter() }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        // MARK: UIScrollViewDelegate

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { reportPosition() }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { reportPosition() }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            if viewModel.showsControls { viewModel.showsControls = false }
        }

        private func reportPosition() {
            guard let textView, let built else { return }
            viewModel.didShow(chapter: built.chapter.id, firstVerse: textView.firstVisibleVerse())
            // Scrolled to the end of a chapter longer than the screen.
            let visibleBottom = textView.contentOffset.y + textView.bounds.height
            // Only the person's own scrolling counts, not restoring a position.
            if textView.isTracking || textView.isDecelerating,
               textView.contentSize.height > textView.bounds.height * 1.2,
               visibleBottom >= textView.contentSize.height - textView.textContainerInset.bottom {
                viewModel.didReachEnd(of: built.chapter.id)
            }
        }
    }
}
