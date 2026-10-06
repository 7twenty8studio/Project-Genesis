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
                return
            }

            textView.attributedText = built.text
            textView.layoutIfNeeded()
            let target = previousVerse ?? viewModel.focusVerse
            scroll(to: target, animated: false)
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
            case let .tap(_, _, verse):
                if viewModel.isSelecting {
                    if let verse { viewModel.toggleSelection(verse) } else { viewModel.clearSelection() }
                } else {
                    viewModel.toggleControls()
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
        }
    }
}
