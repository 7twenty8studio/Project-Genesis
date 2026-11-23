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
    /// Two pages side by side (`PageSpread`). Fixed for a controller's
    /// life: ReaderView builds a new one when it changes.
    var spread = false
    let leftHanded: Bool
    // Passed explicitly so SwiftUI calls `updateUIViewController` when they change.
    let navigationToken: Int
    let decorationsVersion: Int
    let translationID: String
    let pageTurnToken: Int
    /// Fades the running head and "pages left" footer (while the controls show).
    var hidesPageChrome = false
    /// Reading touches: a paper rustle and a light tap as a page turns.
    var pageTurnSound = false
    var pageTurnHaptic = false
    var pageTurnVolume = 0.5
    var pageTurnHapticStrength = 0.9
    /// The scene (Forest, Ocean, Hearth) is moving right now, so a still
    /// painted for a curl is taken at this moment rather than the composed one.
    var sceneMoves = false

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    /// The scene pages curl over (Forest, Ocean or Hearth): the pages stay
    /// clear, showing the live scene, and are painted with its still only
    /// while a page turns (a curl needs opaque pages). Nil for a slide,
    /// which always shows the live scene through clear pages.
    private var curlScene: ThemeScene? {
        pageTurn == .curl ? layout.style.theme.scene : nil
    }

    func makeUIViewController(context: Context) -> ReaderPagesController {
        var options: [UIPageViewController.OptionsKey: Any] = [:]
        if pageTurn == .curl {
            // A spread curls a leaf over the spine in the middle, as a book does.
            options[.spineLocation] = (spread ? UIPageViewController.SpineLocation.mid : .min).rawValue
        } else {
            options[.interPageSpacing] = 0
        }
        let controller = ReaderPagesController(
            transitionStyle: pageTurn == .curl ? .pageCurl : .scroll,
            navigationOrientation: .horizontal,
            options: options
        )
        // The middle spine shows two pages at once and needs both sides.
        controller.isDoubleSided = spread && pageTurn == .curl
        context.coordinator.spread = spread
        context.coordinator.curlsSpread = spread && pageTurn == .curl
        controller.onSizeTransition = { [weak coordinator = context.coordinator] resizing in
            coordinator?.sizeTransition(inProgress: resizing)
        }
        controller.onSizeChange = { [weak coordinator = context.coordinator] in
            coordinator?.viewSizeChanged()
        }
        controller.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.pagesDidLayout()
        }
        // Page curl adds its own edge-tap recognisers. Our taps already turn
        // pages (and respect left-handed mode), so keep only the drag-to-curl.
        for recognizer in controller.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        if pageTurn == .curl {
            // A finger down on a curling page over a scene: the still is
            // painted before any curl can start (see `paintStill`).
            let touch = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.touchChanged(_:)))
            touch.minimumPressDuration = 0
            touch.cancelsTouchesInView = false
            touch.delaysTouchesBegan = false
            touch.delaysTouchesEnded = false
            touch.delegate = context.coordinator
            controller.view.addGestureRecognizer(touch)
        }
        controller.view.backgroundColor = PaperTexture.surroundColor(for: layout.style.theme)
        // A new controller's view starts out the size of the screen. Page
        // curl lays its first page out for that size and doesn't redo it,
        // so a page beside the side panel (narrower than the screen) came
        // up blank. Start it at the size it will be shown at.
        controller.view.frame = CGRect(origin: .zero, size: layout.size)
        context.coordinator.curlScene = curlScene
        context.coordinator.sceneMoves = sceneMoves
        context.coordinator.pageController = controller
        // A new controller is often built in the middle of a size change
        // (turning the phone, opening an iPhone Duo: see the `.id` in
        // ReaderView). Give it its page now, before it's on screen, where
        // that's always safe, and never leave it with no page at all:
        // page curl throws "No view controllers" if UIKit asks it to lay
        // out empty.
        context.coordinator.update(
            layout: layout,
            navigationToken: navigationToken,
            decorationsVersion: decorationsVersion,
            translationID: translationID
        )
        if controller.viewControllers?.isEmpty ?? true {
            // A curling spread needs a stand-in for each side.
            let blanks = (0..<(context.coordinator.curlsSpread ? 2 : 1)).map { _ in
                let blank = UIViewController()
                blank.view.backgroundColor = PaperTexture.pageColor(for: layout.style.theme)
                return blank
            }
            controller.setViewControllers(blanks, direction: .forward, animated: false)
        }
        context.coordinator.settleAfterCreation()
        return controller
    }

    /// Torn down (often mid-resize, when the `.id` changes): nothing may
    /// call back into the coordinator from the old controller.
    static func dismantleUIViewController(_ controller: ReaderPagesController, coordinator: Coordinator) {
        controller.onSizeTransition = nil
        controller.onSizeChange = nil
        controller.onLayout = nil
        controller.dataSource = nil
        controller.delegate = nil
        if coordinator.pageController === controller {
            coordinator.pageController = nil
        }
    }

    func updateUIViewController(_ controller: ReaderPagesController, context: Context) {
        let coordinator = context.coordinator
        coordinator.leftHanded = leftHanded
        coordinator.pageTurnSound = pageTurnSound
        coordinator.pageTurnHaptic = pageTurnHaptic
        coordinator.pageTurnVolume = pageTurnVolume
        coordinator.pageTurnHapticStrength = pageTurnHapticStrength
        coordinator.feedback.prepare(in: controller.view, haptic: pageTurnHaptic)
        coordinator.setPageChromeHidden(hidesPageChrome)
        controller.view.backgroundColor = PaperTexture.surroundColor(for: layout.style.theme)
        coordinator.curlScene = curlScene
        coordinator.sceneMoves = sceneMoves
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
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        let viewModel: ReaderViewModel
        weak var pageController: UIPageViewController?
        var leftHanded = false
        var pageTurnToken = -1
        var pageTurnSound = false
        var pageTurnHaptic = false
        var pageTurnVolume = 0.5
        var pageTurnHapticStrength = 0.9
        let feedback = PageTurnFeedback.shared
        /// Two pages at once: a pair of pages under a curl, or one
        /// `ReaderSpreadViewController` that slides.
        var spread = false
        var curlsSpread = false
        /// Pages that curl over Forest, Ocean or Hearth.
        var curlScene: ThemeScene? {
            didSet { if curlScene == nil { paintStill(false) } }
        }
        var sceneMoves = false
        /// While a page curls over a scene: the scene's still, painted on
        /// each page so the curl turns a whole, opaque page of it. Nil the
        /// rest of the time, so the pages are clear and the scene moves.
        private var sceneStill: UIImage?
        /// The moving scene laid over the still while the scene moves.
        private var liveScene: AnyView?
        /// Every page given the still, shown or not (a page UIKit was
        /// still curling into place when the still came off), so taking
        /// it off reaches them all and none keeps a stale scene.
        private let paintedPages = NSHashTable<ReaderPageViewController>.weakObjects()
        /// A finger is on the pages (from the touch recognizer).
        private var fingerDown = false
        private var stillCheckScheduled = false

        /// Paints the scene's still on the pages (a turn is starting), or
        /// takes it off again (the turn is over). Taken at this moment when
        /// the scene moves, so the picture doesn't jump.
        private func paintStill(_ on: Bool, also extra: [UIViewController] = []) {
            if on {
                // Already painted (a finger went down, then tapped a margin
                // to turn): only the turn's new pages need it.
                if sceneStill == nil {
                    guard let curlScene, let layout, let pageController else { return }
                    let size = pageController.view.bounds.size
                    let pageSize = size.width > 1 && size.height > 1 ? size : layout.size
                    sceneStill = SceneStill.image(
                        scene: curlScene, layout: layout, size: pageSize,
                        time: sceneMoves ? Date().timeIntervalSinceReferenceDate : nil
                    )
                    let safeBottom = layout.safeArea.bottom
                    let textBottom = layout.size.height - layout.textInsets.bottom
                    liveScene = sceneMoves ? AnyView(
                        // Sized by the space it's given (the whole reading
                        // area, see `setLiveScene`), never centred in it.
                        GeometryReader { proxy in
                            ThemeSceneView(
                                scene: curlScene,
                                size: proxy.size,
                                safeBottom: safeBottom,
                                textBottom: textBottom,
                                animates: true,
                                reduceMotion: false,
                                lowPower: false
                            )
                        }
                        .ignoresSafeArea()
                        // Turns only happen while the app is active.
                        .environment(\.scenePhase, .active)
                    ) : nil
                }
                guard sceneStill != nil else { return }
            } else {
                sceneStill = nil
                liveScene = nil
                for page in paintedPages.allObjects {
                    page.setSceneStill(nil, part: nil)
                    page.setLiveScene(nil, part: nil)
                }
                paintedPages.removeAllObjects()
                return
            }
            let shown = pageController?.viewControllers ?? []
            for page in (shown + extra).flatMap({ Self.pages(in: $0) }) {
                paint(page)
            }
        }

        /// Gives one page the still (and the moving scene), when a turn is
        /// under way.
        private func paint(_ page: ReaderPageViewController) {
            guard sceneStill != nil else { return }
            let part: PageSpread.Half? = spread ? (PageSpread.isLeft(page.location.index) ? .left : .right) : nil
            page.setSceneStill(sceneStill, part: part)
            page.setLiveScene(liveScene, part: part)
            paintedPages.add(page)
        }

        /// A finger on the pages: the still goes on before a curl can start,
        /// and comes off when the finger lifts without turning a page (a
        /// turn takes it off when it finishes).
        @objc func touchChanged(_ recognizer: UIGestureRecognizer) {
            switch recognizer.state {
            case .began:
                fingerDown = true
                paintStill(true)
            case .ended, .cancelled, .failed:
                fingerDown = false
                // A curl held a while still has to finish once the finger
                // lifts: trust the turn a little longer.
                if turnStartedAt != nil { turnStartedAt = Date() }
                takeStillOffWhenIdle()
            default:
                break
            }
        }

        /// Before a curl hands UIKit a page: the still goes on first, so
        /// the new page is opaque however quickly the drag began.
        private func paintStillForTurn() {
            guard curlScene != nil else { return }
            paintStill(true)
            takeStillOffWhenIdle()
        }

        /// Takes the still off once nothing is turning and no finger is
        /// down, looking again a moment later while something still is.
        /// Quick turns one after another (a new drag before the last
        /// curl's callback) keep it on, and it can never be left on.
        private func takeStillOffWhenIdle() {
            guard sceneStill != nil, !stillCheckScheduled else { return }
            stillCheckScheduled = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self else { return }
                self.stillCheckScheduled = false
                if self.fingerDown || self.isTurning || self.isTurningByHand {
                    self.takeStillOffWhenIdle()
                } else {
                    self.paintStill(false)
                }
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
        private var pageChromeHidden = false

        func setPageChromeHidden(_ hidden: Bool) {
            guard hidden != pageChromeHidden else { return }
            pageChromeHidden = hidden
            for controller in pageController?.viewControllers ?? [] {
                for page in Self.pages(in: controller) {
                    page.setChromeHidden(hidden, animated: true)
                }
            }
        }

        /// The reader pages a page controller's child holds: itself, or
        /// both halves of a sliding spread.
        static func pages(in controller: UIViewController?) -> [ReaderPageViewController] {
            if let page = controller as? ReaderPageViewController { return [page] }
            if let spread = controller as? ReaderSpreadViewController { return [spread.left, spread.right] }
            return []
        }

        /// Where a page controller's child sits (a spread: its left page).
        static func location(of controller: UIViewController?) -> PageLocation? {
            pages(in: controller).first?.location
        }

        private var layout: ReaderLayout?
        private var cache: [ChapterID: PaginatedChapter] = [:]
        private var navigationToken = -1
        private var decorationsVersion = -1
        private var translationID = ""
        private var followedVerse: VerseID?

        init(viewModel: ReaderViewModel) {
            self.viewModel = viewModel
        }

        // MARK: Waiting out size changes and page turns
        //
        // UIPageViewController (page curl above all) throws if its pages are
        // replaced while it's rotating, resizing (an iPhone Duo opening or
        // folding) or still turning a page: "No view controllers" and
        // "insertObject:atIndex: object cannot be nil". So nothing replaces
        // the pages then; the latest update waits and runs once it's over.

        private var resizeStartedAt: Date?
        /// The last time the page size changed (seen by SwiftUI's layout or
        /// UIKit's), or the controller was built. Sizes often change several
        /// times in a row (an iPhone Duo opening, then the side panel
        /// appearing, then the tab bar changing), sometimes without UIKit's
        /// size transition: new pages wait until it has been still a moment.
        private var sizeChangedAt: Date?
        private static let settleTime: TimeInterval = 0.4
        /// The last size SwiftUI asked for (applied or still waiting).
        private var seenSize: CGSize?
        private var turnStartedAt: Date?
        private var pendingUpdate: (() -> Void)?
        private var flushScheduled = false

        /// A page turn under way. Not trusted for more than a second and a
        /// half, so a missed callback can never freeze the reader.
        private var isTurning: Bool {
            guard let turnStartedAt else { return false }
            return Date().timeIntervalSince(turnStartedAt) < 1.5
        }

        /// A size change under way (trusted for at most three seconds), or
        /// one so recent that another may follow.
        private var isResizing: Bool {
            if let sizeChangedAt, Date().timeIntervalSince(sizeChangedAt) < Self.settleTime { return true }
            guard let resizeStartedAt else { return false }
            return Date().timeIntervalSince(resizeStartedAt) < 3
        }

        /// Once the size has settled, the page showing is set again, laid
        /// out for the final size. A page put in place mid-change (or a
        /// blank one) could otherwise stay empty after an iPhone Duo opens.
        private var needsRefresh = false

        /// A controller built mid-change waits for the change to settle too.
        func settleAfterCreation() {
            sizeChangedAt = Date()
            needsRefresh = true
            flushPendingUpdate()
        }

        /// The controller's own view changed size (UIKit's layout pass),
        /// with or without a size transition.
        func viewSizeChanged() {
            sizeChangedAt = Date()
            needsRefresh = true
            flushPendingUpdate()
        }

        /// A page being turned by hand right now: page curl's drag still
        /// held (even when it stops moving, and for longer than `isTurning`
        /// trusts), or the sliding pages still tracking a finger or settling.
        /// Read live from UIKit, so it can never go stale. Replacing the pages
        /// under a held curl throws "insertObject:atIndex: object cannot be
        /// nil" (Sentry APPLE-IOS-9), as when listening's follow-along or a
        /// new highlight redrew the page mid-drag.
        private var isTurningByHand: Bool {
            guard let pageController else { return false }
            if pageController.gestureRecognizers.contains(where: { $0.isEnabled && ($0.state == .began || $0.state == .changed) }) {
                return true
            }
            if let scroll = pageController.view.subviews.lazy.compactMap({ $0 as? UIScrollView }).first {
                return scroll.isTracking || scroll.isDragging || scroll.isDecelerating
            }
            return false
        }

        private var isBusy: Bool { isResizing || isTurning || isTurningByHand }

        /// UIKit laid the pages out. If no real page is on screen (the
        /// blank stand-in, or a page curl left without its page's view,
        /// as after an iPhone Duo opens beside the side panel), the page
        /// is put in place again once things are still.
        func pagesDidLayout() {
            guard layout != nil, !needsRefresh, !isTurning, !isTurningByHand,
                  let controller = pageController, controller.view.window != nil else { return }
            let page = controller.viewControllers?.first
            if let page, Self.location(of: page) != nil, page.isViewLoaded, page.view.window != nil, !page.view.isHidden,
               page.view.bounds.width > 0, page.view.bounds.height > 0 {
                return
            }
            needsRefresh = true
            flushPendingUpdate()
        }

        func sizeTransition(inProgress: Bool) {
            resizeStartedAt = inProgress ? Date() : nil
            if !inProgress {
                needsRefresh = true
                flushPendingUpdate()
            }
        }

        private func turnFinished() {
            turnStartedAt = nil
            if sceneStill == nil, paintedPages.count > 0 { paintStill(false) }
            takeStillOffWhenIdle()
            flushPendingUpdate()
        }

        private func flushPendingUpdate() {
            guard pendingUpdate != nil || needsRefresh, !flushScheduled else { return }
            flushScheduled = true
            // Next run loop turn, once UIKit has finished its own work.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isBusy {
                    // Still busy (or a callback was missed): look again shortly.
                    try? await Task.sleep(for: .milliseconds(150))
                    self.flushScheduled = false
                    self.flushPendingUpdate()
                    return
                }
                self.flushScheduled = false
                let update = self.pendingUpdate
                let refresh = self.needsRefresh
                self.pendingUpdate = nil
                self.needsRefresh = false
                update?()
                if refresh { self.refreshPage() }
            }
        }

        /// Puts the page showing (or, if there's none yet, the reader's
        /// verse) in place again, without animation.
        private func refreshPage() {
            guard layout != nil else { return }
            if let location = currentLocation {
                show(location: location)
            } else {
                show(verse: viewModel.focusVerse)
            }
        }

        // MARK: Updates from SwiftUI

        func update(layout newLayout: ReaderLayout, navigationToken token: Int, decorationsVersion version: Int, translationID translation: String) {
            guard newLayout.pageTextSize.width > 0, newLayout.pageTextSize.height > 0 else { return }
            // A new size: re-paginate only once the size has settled, never
            // in the middle of the change.
            if let seenSize, seenSize != newLayout.size {
                sizeChangedAt = Date()
            }
            seenSize = newLayout.size
            if isBusy {
                // Only the latest matters: it carries every change so far.
                pendingUpdate = { [weak self] in
                    self?.update(layout: newLayout, navigationToken: token, decorationsVersion: version, translationID: translation)
                }
                flushPendingUpdate()
                return
            }

            // No real page yet (a blank one, or none): one must be shown.
            let needsPage = currentLocation == nil
            if newLayout != layout || translation != translationID || needsPage {
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
                guard let chapter = paginated(location.chapter) else { return }
                var index = min(location.index, chapter.pages.count - 1)
                // Listening with follow-along: turn to the verse being read
                // when it moves onto another page (or spread).
                if let playing = viewModel.playingVerse, playing != followedVerse, playing.chapterID == location.chapter {
                    followedVerse = playing
                    let target = chapter.pageIndex(containing: playing)
                    if shownIndex(target) != shownIndex(index) {
                        let forward = target > index
                        index = target
                        show(location: PageLocation(chapter: location.chapter, index: index), direction: forward ? .forward : .reverse, animated: !UIAccessibility.isReduceMotionEnabled)
                        return
                    }
                }
                show(location: PageLocation(chapter: location.chapter, index: index))
            }
        }

        /// The page showing (in a spread, the left one).
        private var currentLocation: PageLocation? {
            Self.location(of: pageController?.viewControllers?.first)
        }

        /// The first page of the view that shows a page: in a spread, its left page.
        private func shownIndex(_ index: Int) -> Int {
            spread ? PageSpread.leftIndex(of: index) : index
        }

        /// The last page a view starting at `location` shows.
        private func lastShown(from location: PageLocation) -> PageLocation {
            spread ? PageLocation(chapter: location.chapter, index: location.index + 1) : location
        }

        // MARK: Pages

        /// The layout for one page: the whole reading area, or in a spread
        /// its left (even index) or right half.
        private func pageLayout(for index: Int) -> ReaderLayout? {
            guard let layout else { return nil }
            return spread ? layout.spreadPage(left: PageSpread.isLeft(index)) : layout
        }

        /// Pages a chapter takes, the blank right page of a spread included.
        private func slotCount(_ chapter: PaginatedChapter) -> Int {
            spread ? PageSpread.slotCount(pages: chapter.pages.count) : chapter.pages.count
        }

        private func paginated(_ chapterID: ChapterID) -> PaginatedChapter? {
            if let cached = cache[chapterID] { return cached }
            guard let layout = pageLayout(for: 0), let chapter = viewModel.loadChapter(chapterID) else { return nil }
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
            guard let layout = pageLayout(for: location.index), let chapter = paginated(location.chapter) else { return nil }
            guard chapter.pages.indices.contains(location.index) else {
                // The blank right page after a chapter that ends on a left page.
                return spread && location.index >= 0 && location.index < slotCount(chapter) ? blankPage(at: location) : nil
            }
            let page = ReaderPageViewController(location: location)
            let isLeft = PageSpread.isLeft(location.index)
            page.configure(
                text: chapter.built.text.attributedSubstring(from: chapter.pages[location.index]),
                layout: layout,
                header: chapter.built.chapter.id.description(in: layout.style.bibleLanguage),
                // The chapter's first page already shows its title in the text.
                showsHeader: location.index > 0,
                footer: footer(for: location, in: chapter),
                // A book's page numbers sit on the outer corners, with the
                // spine's shadow on the inner edge.
                footerAlignment: spread ? (isLeft ? .left : .right) : .center,
                spineEdge: spread ? (isLeft ? .right : .left) : nil
            )
            paint(page)
            page.onEvent = { [weak self, weak page] event in self?.handle(event, on: page) }
            page.setChromeHidden(pageChromeHidden, animated: false)
            return page
        }

        /// An empty page of paper: the right half of a spread with nothing on it.
        private func blankPage(at location: PageLocation) -> ReaderPageViewController? {
            guard let layout = pageLayout(for: location.index) else { return nil }
            let page = ReaderPageViewController(location: location)
            page.configure(text: NSAttributedString(), layout: layout, header: "", showsHeader: false, footer: "",
                           spineEdge: PageSpread.isLeft(location.index) ? .right : .left)
            paint(page)
            page.onEvent = { [weak self, weak page] event in self?.handle(event, on: page) }
            page.setChromeHidden(pageChromeHidden, animated: false)
            return page
        }

        /// One page: "3 pages left in chapter". In a spread the left page
        /// shows its number and the right one what's left, after it.
        private func footer(for location: PageLocation, in chapter: PaginatedChapter) -> String {
            let count = chapter.pages.count
            if spread, PageSpread.isLeft(location.index), location.index + 1 < count {
                return (location.index + 1).formatted()
            }
            return footerText(pageIndex: location.index, pageCount: count)
        }

        private func footerText(pageIndex: Int, pageCount: Int) -> String {
            let remaining = pageCount - pageIndex - 1
            switch remaining {
            case 0: return String(localized: "Last page in chapter")
            case 1: return String(localized: "1 page left in chapter")
            default: return String(localized: "\(remaining) pages left in chapter")
            }
        }

        /// The page after this one (page by page, also in a spread).
        private func location(after location: PageLocation) -> PageLocation? {
            guard let chapter = paginated(location.chapter) else { return nil }
            if location.index + 1 < slotCount(chapter) {
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
            return PageLocation(chapter: previous, index: max(slotCount(chapter) - 1, 0))
        }

        /// What the page controller shows for a location: one page; a
        /// spread's two pages under a curl; or the spread as one view that
        /// slides. A spread always starts on its left page.
        private func viewControllers(at location: PageLocation) -> [UIViewController]? {
            let first = PageLocation(chapter: location.chapter, index: shownIndex(location.index))
            guard let page = page(at: first) ?? page(at: PageLocation(chapter: location.chapter, index: 0)) else { return nil }
            guard spread else { return [page] }
            let next = PageLocation(chapter: page.location.chapter, index: page.location.index + 1)
            guard let right = self.page(at: next) ?? blankPage(at: next) else { return nil }
            if curlsSpread { return [page, right] }
            return [ReaderSpreadViewController(left: page, right: right)]
        }

        private func show(verse: VerseID) {
            guard let chapter = paginated(verse.chapterID) else { return }
            show(location: PageLocation(chapter: verse.chapterID, index: chapter.pageIndex(containing: verse)))
        }

        private func show(location: PageLocation, direction: UIPageViewController.NavigationDirection = .forward, animated: Bool = false) {
            guard let pageController,
                  let controllers = viewControllers(at: location),
                  let shown = Self.location(of: controllers.first) else { return }
            if animated {
                turnStartedAt = Date()
                paintStill(true, also: controllers)
                // No hand may start a turn while this one animates: a drag
                // begun under an animated turn leaves UIPageViewController
                // asking for a page it no longer has, and it throws.
                pageController.view.isUserInteractionEnabled = false
                let resync = pageController.transitionStyle == .scroll
                pageController.setViewControllers(controllers, direction: direction, animated: true) { [weak self, weak pageController] finished in
                    // Next run loop turn, once UIKit has finished its own work.
                    Task { @MainActor [weak self, weak pageController] in
                        // Sliding pages keep stale neighbours after an animated
                        // set and can later insert a missing one; setting the
                        // same pages again without animation resets them.
                        if resync, finished, let pageController, let shown = pageController.viewControllers, !shown.isEmpty {
                            pageController.setViewControllers(shown, direction: direction, animated: false)
                        }
                        pageController?.view.isUserInteractionEnabled = true
                        self?.turnFinished()
                    }
                }
                // Never leave the reader untouchable if UIKit drops the completion.
                Task { @MainActor [weak pageController] in
                    try? await Task.sleep(for: .seconds(1.5))
                    pageController?.view.isUserInteractionEnabled = true
                }
            } else {
                pageController.setViewControllers(controllers, direction: direction, animated: false)
            }
            didSettle(on: shown)
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

        private func handle(_ event: ReaderTextEvent, on page: ReaderPageViewController?) {
            switch event {
            case let .longPress(verse):
                viewModel.toggleSelection(verse)
            case let .footnote(text, verse):
                viewModel.showFootnote(text, verse: verse)
            case let .link(url):
                UIApplication.shared.open(url)
            case let .tap(point, bounds, verse):
                // The outer margins: in a spread, the left page's left and
                // the right page's right.
                let leftInset = pageLayout(for: 0)?.textInsets.left ?? 0
                let rightInset = pageLayout(for: 1)?.textInsets.right ?? 0
                // The edges are the reading area's, as seen: beside the side
                // panel the page's own view can be wider than what shows, which
                // put the turning edge under the panel. In a spread the tap may
                // be on either page, so it's measured from the page tapped.
                var x = point.x
                var width = bounds.width
                if let container = pageController?.view,
                   let pageView = page?.view ?? pageController?.viewControllers?.first?.view,
                   pageView.isDescendant(of: container) {
                    x = pageView.convert(point, to: container).x
                    width = container.bounds.width
                }
                let action = ReaderTap.action(
                    x: x, pageWidth: width,
                    leftMargin: leftInset, rightMargin: rightInset,
                    verse: verse, isSelecting: viewModel.isSelecting,
                    turnsPages: true, leftHanded: leftHanded
                )
                switch action {
                case let .turnPage(forward): turnPage(forward: forward)
                case let .toggleSelection(verse): viewModel.toggleSelection(verse)
                case .clearSelection: viewModel.clearSelection()
                case .toggleControls: viewModel.toggleControls()
                }
            }
        }

        /// Turns one page, as a tap in the margin or a keyboard arrow does.
        func turnPage(forward: Bool) {
            // One turn at a time: a second tap mid-curl is let go.
            guard !isBusy,
                  let current = currentLocation,
                  let next = forward ? location(after: lastShown(from: current)) : location(before: current) else { return }
            // A spread turns to the next spread, which starts on its left page.
            let target = PageLocation(chapter: next.chapter, index: shownIndex(next.index))
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            show(location: target, direction: forward ? .forward : .reverse, animated: !reduceMotion)
            if forward { reportChapterEnd(from: current, to: target) }
            feedback.pageTurned(sound: pageTurnSound, volume: pageTurnVolume, haptic: pageTurnHaptic, strength: pageTurnHapticStrength)
            hideControlsForReading()
        }

        /// A forward page turn that reaches a chapter's last page (or turns
        /// past a chapter that fit on one page, or one spread) finishes that
        /// chapter by reading.
        private func reportChapterEnd(from previous: PageLocation, to location: PageLocation) {
            let isForward = location.chapter > previous.chapter || (location.chapter == previous.chapter && location.index > previous.index)
            guard isForward, let pages = cache[location.chapter]?.pages.count else { return }
            let finished: ChapterID
            let pagesShown = spread ? 2 : 1
            if location.index > 0, lastShown(from: location).index >= pages - 1 {
                finished = location.chapter
            } else if location.chapter != previous.chapter, let previousPages = cache[previous.chapter]?.pages.count,
                      previousPages <= pagesShown {
                finished = previous.chapter
            } else {
                return
            }
            // Deferred: a keyboard turn arrives inside a SwiftUI update.
            Task { @MainActor [weak self] in
                self?.viewModel.didReachEnd(of: finished)
            }
        }

        /// Turning a page means reading: put the controls, tab bar and
        /// players away so they don't cover the text (a tap brings them back).
        private func hideControlsForReading() {
            Task { @MainActor [weak self] in
                guard let self, self.viewModel.showsControls, !self.viewModel.isSelecting else { return }
                self.viewModel.showsControls = false
            }
        }

        // MARK: UIPageViewControllerDataSource

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let current = Self.location(of: viewController),
                  let target = location(before: current) else { return nil }
            paintStillForTurn()
            // A sliding spread: the whole spread before, from its left page.
            if viewController is ReaderSpreadViewController { return viewControllers(at: target)?.first }
            return page(at: target)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let current = Self.location(of: viewController) else { return nil }
            paintStillForTurn()
            // A sliding spread: the spread after its right page.
            if viewController is ReaderSpreadViewController {
                guard let target = location(after: lastShown(from: current)) else { return nil }
                return viewControllers(at: target)?.first
            }
            guard let target = location(after: current) else { return nil }
            return page(at: target)
        }

        // MARK: UIPageViewControllerDelegate

        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            // A page dragged by hand.
            turnStartedAt = Date()
            if curlScene != nil { paintStill(true, also: pendingViewControllers) }
        }

        /// Page curl asks this as the device turns. Keep one page, spine on
        /// the left, and give it the page already showing: left to itself,
        /// UIPageViewController can be left with no pages and throw. A
        /// spread keeps its two pages and middle spine until ReaderView
        /// builds the single-page controller for the new shape.
        func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation {
            if curlsSpread {
                var pair = pageViewController.viewControllers ?? []
                if pair.count != 2 {
                    pair = viewControllers(at: currentLocation ?? PageLocation(chapter: viewModel.focusVerse.chapterID, index: 0)) ?? []
                }
                if pair.count != 2 { pair = [UIViewController(), UIViewController()] }
                pageViewController.isDoubleSided = true
                pageViewController.setViewControllers(pair, direction: .forward, animated: false)
                return .mid
            }
            let current = pageViewController.viewControllers?.first
                ?? page(at: currentLocation ?? PageLocation(chapter: viewModel.focusVerse.chapterID, index: 0))
                ?? UIViewController()
            pageViewController.setViewControllers([current], direction: .forward, animated: false)
            pageViewController.isDoubleSided = false
            return .min
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            defer { turnFinished() }
            // A selection survives the page turn, so verses can be gathered
            // across pages and nothing chosen is lost.
            guard completed, let location = currentLocation else { return }
            feedback.pageTurned(sound: pageTurnSound, volume: pageTurnVolume, haptic: pageTurnHaptic, strength: pageTurnHapticStrength)
            didSettle(on: location)
            if let previous = Self.location(of: previousViewControllers.first) {
                reportChapterEnd(from: previous, to: location)
            }
            hideControlsForReading()
        }
    }
}

/// The reader's UIPageViewController, which says when its size starts and
/// stops changing (rotating, or an iPhone Duo opening or folding), so its
/// pages are only replaced once the change is over.
final class ReaderPagesController: UIPageViewController {
    var onSizeTransition: ((Bool) -> Void)?
    /// Every change of the view's size, transition or not (an iPhone Duo
    /// opening can resize the window without one reaching this controller).
    var onSizeChange: (() -> Void)?
    /// Every layout pass, so a page that went missing is noticed.
    var onLayout: (() -> Void)?
    private var lastSize: CGSize = .zero

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let size = view.bounds.size
        guard size != lastSize else { return }
        let first = lastSize == .zero
        lastSize = size
        if !first { onSizeChange?() }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        onSizeTransition?(true)
        let animates = coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.onSizeTransition?(false)
        }
        // No animation: the completion may never come, so it's over now.
        if !animates { onSizeTransition?(false) }
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
    /// In a spread, a soft shade along the edge at the spine.
    private let spineShade = CAGradientLayer()
    private var spineEdge: UIRectEdge?
    private var layout: ReaderLayout?
    private var chromeHidden = false
    /// The scene's still behind the text, under a curl (see `setSceneStill`).
    private let sceneLayer = CALayer()
    /// The moving scene over the still while a page turns and Gentle
    /// Motion is on, in step with the scene behind the pages, so nothing
    /// pauses under a held curl (see `setLiveScene`).
    private let liveSceneBox = UIView()
    private var liveScene: UIHostingController<AnyView>?
    private var liveScenePart: PageSpread.Half?

    init(location: PageLocation) {
        self.location = location
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(
        text: NSAttributedString, layout: ReaderLayout, header: String, showsHeader: Bool = true, footer: String,
        footerAlignment: NSTextAlignment = .center, spineEdge: UIRectEdge? = nil
    ) {
        self.layout = layout
        self.spineEdge = spineEdge
        loadViewIfNeeded()
        view.backgroundColor = PaperTexture.pageColor(for: layout.style.theme)
        textView.attributedText = text
        textView.textContainerInset = layout.textInsets
        textView.accessibilityLabel = header

        for label in [headerLabel, footerLabel] {
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = chromeColor
            label.textAlignment = .center
            label.adjustsFontForContentSizeCategory = false
        }
        headerLabel.attributedText = NSAttributedString(string: showsHeader ? header.uppercased() : "", attributes: [.kern: 1.2, .foregroundColor: chromeColor])
        // Still read out (and found by UI tests) on a chapter's first page.
        headerLabel.isAccessibilityElement = true
        headerLabel.accessibilityLabel = header.uppercased()
        footerLabel.textAlignment = footerAlignment
        footerLabel.text = footer
        // Over a scene (Forest, Ocean, Hearth), a soft shadow keeps the
        // running head and page number clear of the picture.
        for label in [headerLabel, footerLabel] {
            let overScene = layout.style.theme.scene != nil
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = overScene ? 0.75 : 0
            label.layer.shadowRadius = overScene ? 3 : 0
            label.layer.shadowOffset = .zero
        }
        // Darker toward the spine, gone a little way into the page.
        let shade = layout.style.theme.isDark ? 0.28 : 0.09
        spineShade.colors = [UIColor.black.withAlphaComponent(shade).cgColor, UIColor.black.withAlphaComponent(0).cgColor]
        spineShade.startPoint = CGPoint(x: spineEdge == .left ? 0 : 1, y: 0.5)
        spineShade.endPoint = CGPoint(x: spineEdge == .left ? 1 : 0, y: 0.5)
        spineShade.isHidden = spineEdge == nil
        view.setNeedsLayout()
    }

    /// Paints the scene's still behind the page (a curl over Forest, Ocean
    /// or Hearth): all of it, or in a spread the half this page shows.
    func setSceneStill(_ image: UIImage?, part: PageSpread.Half?) {
        loadViewIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sceneLayer.contents = image?.cgImage
        sceneLayer.isHidden = image == nil
        switch part {
        case .left: sceneLayer.contentsRect = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .right: sceneLayer.contentsRect = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case nil: sceneLayer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        CATransaction.commit()
    }

    /// Shows the moving scene behind the text (a turn over a scene while
    /// it moves), or takes it away. It covers the whole reading area,
    /// shifted so a spread's page shows its own half; it draws from the
    /// clock like the scene behind the pages, so the two match exactly.
    func setLiveScene(_ content: AnyView?, part: PageSpread.Half?) {
        loadViewIfNeeded()
        liveScenePart = part
        guard let content else {
            if let liveScene {
                liveScene.willMove(toParent: nil)
                liveScene.view.removeFromSuperview()
                liveScene.removeFromParent()
                self.liveScene = nil
            }
            liveSceneBox.isHidden = true
            return
        }
        if let liveScene {
            liveScene.rootView = content
        } else {
            let host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            host.view.accessibilityElementsHidden = true
            host.safeAreaRegions = []
            addChild(host)
            liveSceneBox.addSubview(host.view)
            host.didMove(toParent: self)
            liveScene = host
        }
        liveSceneBox.isHidden = false
        view.setNeedsLayout()
    }

    /// Hides the running head and footer by making their text clear rather
    /// than hiding the labels, so VoiceOver and the UI tests still find them.
    func setChromeHidden(_ hidden: Bool, animated: Bool) {
        chromeHidden = hidden
        guard isViewLoaded else { return }
        let apply = { [self] in
            headerLabel.textColor = chromeColor
            footerLabel.textColor = chromeColor
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            for label in [headerLabel, footerLabel] {
                UIView.transition(with: label, duration: 0.2, options: .transitionCrossDissolve, animations: apply)
            }
        } else {
            apply()
        }
    }

    private var chromeColor: UIColor {
        chromeHidden ? .clear : (layout?.style.palette.uiSecondaryText ?? .secondaryLabel)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(textView)
        view.addSubview(headerLabel)
        view.addSubview(footerLabel)
        spineShade.isHidden = true
        view.layer.addSublayer(spineShade)
        sceneLayer.isHidden = true
        sceneLayer.contentsGravity = .resize
        view.layer.insertSublayer(sceneLayer, at: 0)
        liveSceneBox.isHidden = true
        liveSceneBox.clipsToBounds = true
        liveSceneBox.isUserInteractionEnabled = false
        view.insertSubview(liveSceneBox, belowSubview: textView)
        textView.accessibilityIdentifier = "reader.page"
        headerLabel.accessibilityIdentifier = "reader.header"
        footerLabel.accessibilityIdentifier = "reader.footer"
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
        let shadeWidth: CGFloat = 28
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spineShade.frame = CGRect(
            x: spineEdge == .left ? 0 : view.bounds.width - shadeWidth, y: 0,
            width: shadeWidth, height: view.bounds.height
        )
        sceneLayer.frame = view.bounds
        CATransaction.commit()
        liveSceneBox.frame = view.bounds
        let width = view.bounds.width
        liveScene?.view.frame = CGRect(
            x: liveScenePart == .right ? -width : 0, y: 0,
            width: liveScenePart == nil ? width : width * 2, height: view.bounds.height
        )
    }
}

/// A spread that slides as one (Slide page turn): two pages side by side,
/// each its own `ReaderPageViewController`.
final class ReaderSpreadViewController: UIViewController {
    let left: ReaderPageViewController
    let right: ReaderPageViewController

    init(left: ReaderPageViewController, right: ReaderPageViewController) {
        self.left = left
        self.right = right
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = left.view.backgroundColor
        for page in [left, right] {
            addChild(page)
            view.addSubview(page.view)
            page.didMove(toParent: self)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let half = (view.bounds.width / 2).rounded(.down)
        left.view.frame = CGRect(x: 0, y: 0, width: half, height: view.bounds.height)
        right.view.frame = CGRect(x: half, y: 0, width: view.bounds.width - half, height: view.bounds.height)
    }
}
