import SwiftUI
import UIKit

/// Where a page sits: a chapter and a page index within it.
struct PageLocation: Hashable {
    let chapter: ChapterID
    let index: Int
}

/// Kindle-style page mode, built on UIPageViewController for native slide
/// and page-curl transitions. Pages flow across chapter and book boundaries.
struct PagedReaderView: UIViewControllerRepresentable {
    let viewModel: ReaderViewModel
    let layout: ReaderLayout
    let pageTurn: PageTurnStyle
    let leftHanded: Bool
    // Passed explicitly so SwiftUI calls `updateUIViewController` when they change.
    let navigationToken: Int
    let decorationsVersion: Int
    let translationID: String
    let pageTurnToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        var options: [UIPageViewController.OptionsKey: Any] = [:]
        if pageTurn == .curl {
            options[.spineLocation] = UIPageViewController.SpineLocation.min.rawValue
        } else {
            options[.interPageSpacing] = 0
        }
        let controller = UIPageViewController(
            transitionStyle: pageTurn == .curl ? .pageCurl : .scroll,
            navigationOrientation: .horizontal,
            options: options
        )
        controller.isDoubleSided = false
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = layout.style.palette.uiBackground
        context.coordinator.pageController = controller
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.leftHanded = leftHanded
        controller.view.backgroundColor = layout.style.palette.uiBackground
        coordinator.update(
            layout: layout,
            navigationToken: navigationToken,
            decorationsVersion: decorationsVersion,
            translationID: translationID
        )
        if coordinator.pageTurnToken != pageTurnToken {
            let isFirstUpdate = coordinator.pageTurnToken < 0
            coordinator.pageTurnToken = pageTurnToken
            if !isFirstUpdate { coordinator.turnPage(forward: viewModel.pageTurnForward) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        let viewModel: ReaderViewModel
        weak var pageController: UIPageViewController?
        var leftHanded = false
        var pageTurnToken = -1

        private var layout: ReaderLayout?
        private var cache: [ChapterID: PaginatedChapter] = [:]
        private var navigationToken = -1
        private var decorationsVersion = -1
        private var translationID = ""

        init(viewModel: ReaderViewModel) {
            self.viewModel = viewModel
        }

        // MARK: Updates from SwiftUI

        func update(layout newLayout: ReaderLayout, navigationToken token: Int, decorationsVersion version: Int, translationID translation: String) {
            guard newLayout.pageTextSize.width > 0, newLayout.pageTextSize.height > 0 else { return }

            if newLayout != layout || translation != translationID {
                // Size, style or translation changed: everything must re-paginate.
                // Keep the first verse on screen in view, unless the person
                // also navigated somewhere new.
                let navigated = token != navigationToken
                let anchor = currentLocation.flatMap { cache[$0.chapter]?.anchorVerse(onPage: $0.index) } ?? viewModel.focusVerse
                layout = newLayout
                translationID = translation
                navigationToken = token
                decorationsVersion = version
                cache.removeAll()
                show(verse: navigated ? viewModel.focusVerse : anchor)
                return
            }

            if token != navigationToken {
                navigationToken = token
                decorationsVersion = version
                cache.removeAll()
                show(verse: viewModel.focusVerse)
                return
            }

            if version != decorationsVersion {
                decorationsVersion = version
                // Highlights, notes or selection changed on the visible chapter.
                // These don't move text, so the same page index stays correct.
                guard let location = currentLocation else { return }
                cache[location.chapter] = nil
                if let chapter = paginated(location.chapter) {
                    show(location: PageLocation(chapter: location.chapter, index: min(location.index, chapter.pages.count - 1)))
                }
            }
        }

        private var currentLocation: PageLocation? {
            (pageController?.viewControllers?.first as? ReaderPageViewController)?.location
        }

        // MARK: Pages

        private func paginated(_ chapterID: ChapterID) -> PaginatedChapter? {
            if let cached = cache[chapterID] { return cached }
            guard let layout, let chapter = viewModel.loadChapter(chapterID) else { return nil }
            let built = ChapterTextBuilder.build(chapter, style: layout.style, decorations: viewModel.decorations(for: chapterID))
            let pages = Paginator.pages(for: built.text, pageSize: layout.pageTextSize)
            let result = PaginatedChapter(built: built, pages: pages)
            cache[chapterID] = result
            // Keep memory bounded: current chapter and its neighbours.
            if cache.count > 5 {
                let keep = Set([chapterID, chapterID.next, chapterID.previous].compactMap { $0 })
                cache = cache.filter { keep.contains($0.key) }
            }
            return result
        }

        private func page(at location: PageLocation) -> ReaderPageViewController? {
            guard let layout, let chapter = paginated(location.chapter), chapter.pages.indices.contains(location.index) else { return nil }
            let page = ReaderPageViewController(location: location)
            page.configure(
                text: chapter.built.text.attributedSubstring(from: chapter.pages[location.index]),
                layout: layout,
                header: chapter.built.chapter.id.description,
                footer: footerText(pageIndex: location.index, pageCount: chapter.pages.count)
            )
            page.onEvent = { [weak self] event in self?.handle(event) }
            return page
        }

        private func footerText(pageIndex: Int, pageCount: Int) -> String {
            let remaining = pageCount - pageIndex - 1
            switch remaining {
            case 0: return "Last page in chapter"
            case 1: return "1 page left in chapter"
            default: return "\(remaining) pages left in chapter"
            }
        }

        private func location(after location: PageLocation) -> PageLocation? {
            guard let chapter = paginated(location.chapter) else { return nil }
            if location.index + 1 < chapter.pages.count {
                return PageLocation(chapter: location.chapter, index: location.index + 1)
            }
            guard let next = location.chapter.next else { return nil }
            return PageLocation(chapter: next, index: 0)
        }

        private func location(before location: PageLocation) -> PageLocation? {
            if location.index > 0 {
                return PageLocation(chapter: location.chapter, index: location.index - 1)
            }
            guard let previous = location.chapter.previous, let chapter = paginated(previous) else { return nil }
            return PageLocation(chapter: previous, index: max(chapter.pages.count - 1, 0))
        }

        private func show(verse: VerseID) {
            guard let chapter = paginated(verse.chapterID) else { return }
            show(location: PageLocation(chapter: verse.chapterID, index: chapter.pageIndex(containing: verse)))
        }

        private func show(location: PageLocation, direction: UIPageViewController.NavigationDirection = .forward, animated: Bool = false) {
            guard let page = page(at: location) ?? page(at: PageLocation(chapter: location.chapter, index: 0)) else { return }
            pageController?.setViewControllers([page], direction: direction, animated: animated)
            didSettle(on: page.location)
        }

        private func didSettle(on location: PageLocation) {
            let firstVerse = cache[location.chapter]?.anchorVerse(onPage: location.index)
            // Deferred: this can run inside a SwiftUI update, which must not
            // change observed state synchronously.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.viewModel.didShow(chapter: location.chapter, firstVerse: firstVerse)
                // Warm the neighbouring chapters once the page has settled.
                if let next = location.chapter.next { _ = self.paginated(next) }
                if let previous = location.chapter.previous { _ = self.paginated(previous) }
            }
        }

        // MARK: Taps

        private func handle(_ event: ReaderTextEvent) {
            switch event {
            case let .longPress(verse):
                viewModel.toggleSelection(verse)
            case let .tap(point, bounds, verse):
                if viewModel.isSelecting {
                    if let verse { viewModel.toggleSelection(verse) } else { viewModel.clearSelection() }
                    return
                }
                let fraction = bounds.width > 0 ? point.x / bounds.width : 0.5
                let edge: CGFloat = 0.22
                if fraction < edge {
                    turnPage(forward: leftHanded)
                } else if fraction > 1 - edge {
                    turnPage(forward: !leftHanded)
                } else {
                    viewModel.toggleControls()
                }
            }
        }

        /// Turns one page, as a tap in the margin or a keyboard arrow does.
        func turnPage(forward: Bool) {
            guard let current = currentLocation,
                  let target = forward ? location(after: current) : location(before: current) else { return }
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            show(location: target, direction: forward ? .forward : .reverse, animated: !reduceMotion)
        }

        // MARK: UIPageViewControllerDataSource

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let current = (viewController as? ReaderPageViewController)?.location,
                  let target = location(before: current) else { return nil }
            return page(at: target)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let current = (viewController as? ReaderPageViewController)?.location,
                  let target = location(after: current) else { return nil }
            return page(at: target)
        }

        // MARK: UIPageViewControllerDelegate

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let location = currentLocation else { return }
            if viewModel.isSelecting { viewModel.clearSelection() }
            didSettle(on: location)
        }
    }
}

/// One page of reader text with a running head and a footer.
final class ReaderPageViewController: UIViewController {
    let location: PageLocation
    var onEvent: ((ReaderTextEvent) -> Void)? {
        didSet { textView.onEvent = onEvent }
    }

    private let textView = ReaderTextView(scrollable: false)
    private let headerLabel = UILabel()
    private let footerLabel = UILabel()
    private var layout: ReaderLayout?

    init(location: PageLocation) {
        self.location = location
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(text: NSAttributedString, layout: ReaderLayout, header: String, footer: String) {
        self.layout = layout
        loadViewIfNeeded()
        let palette = layout.style.palette
        view.backgroundColor = palette.uiBackground
        textView.attributedText = text
        textView.textContainerInset = layout.textInsets
        textView.accessibilityLabel = header

        for label in [headerLabel, footerLabel] {
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = palette.uiSecondaryText
            label.textAlignment = .center
            label.adjustsFontForContentSizeCategory = false
        }
        headerLabel.attributedText = NSAttributedString(string: header.uppercased(), attributes: [.kern: 1.2])
        footerLabel.text = footer
        view.setNeedsLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(textView)
        view.addSubview(headerLabel)
        view.addSubview(footerLabel)
        headerLabel.isAccessibilityElement = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let layout else { return }
        // The text view fills the page so taps in the margins still land on it;
        // insets keep text inside the measured page area. A little slack at the
        // bottom means a rounding difference can never clip the last line.
        textView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height + layout.style.fontSize)
        let insets = layout.textInsets
        headerLabel.frame = CGRect(x: insets.left, y: layout.safeArea.top + 10, width: view.bounds.width - insets.left - insets.right, height: 20)
        footerLabel.frame = CGRect(x: insets.left, y: view.bounds.height - layout.safeArea.bottom - 28, width: view.bounds.width - insets.left - insets.right, height: 20)
    }
}
