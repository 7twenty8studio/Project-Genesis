import PencilKit
import SwiftUI
import UIKit

/// A PencilKit page for a note: Apple Pencil on iPad (fingers too, unless the
/// person chose "Only Draw with Apple Pencil"), a finger on iPhone. The tool
/// picker, with its undo and redo, shows while the page is being written on.
struct HandwritingCanvas: UIViewRepresentable {
    /// The note's saved drawing, read once when the page appears.
    let initialData: Data?
    let paper: PaperStyle
    let palette: ThemePalette
    /// Incremented by the "Clear Page" button.
    let clearRequest: Int
    let onChange: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(clearRequest: clearRequest, onChange: onChange)
    }

    func makeUIView(context: Context) -> HandwritingPageView {
        let page = HandwritingPageView()
        let canvas = page.canvas
        if let initialData, let drawing = try? PKDrawing(data: initialData) {
            canvas.drawing = drawing
        }
        // Fingers draw on iPhone; on iPad, follow the system's Apple Pencil setting.
        canvas.drawingPolicy = UIDevice.current.userInterfaceIdiom == .phone ? .anyInput : .default
        canvas.isAccessibilityElement = true
        canvas.accessibilityLabel = String(localized: "Handwriting page")
        canvas.accessibilityHint = String(localized: "Write or sketch with Apple Pencil or your finger.")
        canvas.accessibilityTraits = .allowsDirectInteraction
        canvas.accessibilityIdentifier = "note.canvas"
        // Set the delegate after the saved drawing, so loading it isn't an edit.
        canvas.delegate = context.coordinator
        context.coordinator.page = page
        page.apply(paper: paper, palette: palette)
        return page
    }

    func updateUIView(_ page: HandwritingPageView, context: Context) {
        context.coordinator.onChange = onChange
        page.apply(paper: paper, palette: palette)
        context.coordinator.clearIfRequested(clearRequest)
    }

    static func dismantleUIView(_ page: HandwritingPageView, coordinator: Coordinator) {
        page.hideToolPicker()
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onChange: (PKDrawing) -> Void
        weak var page: HandwritingPageView?
        private var clearRequest: Int

        init(clearRequest: Int, onChange: @escaping (PKDrawing) -> Void) {
            self.clearRequest = clearRequest
            self.onChange = onChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            page?.updateContentSize()
            onChange(canvasView.drawing)
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            // Writing again after tapping the title brings the tools back.
            if !canvasView.isFirstResponder { canvasView.becomeFirstResponder() }
        }

        func clearIfRequested(_ request: Int) {
            guard request != clearRequest else { return }
            clearRequest = request
            // Not during SwiftUI's view update: clearing reports a change.
            Task { [weak self] in self?.clear() }
        }

        private func clear() {
            guard let canvas = page?.canvas else { return }
            canvas.drawing = PKDrawing()
            canvas.undoManager?.removeAllActions()
            page?.updateContentSize()
            onChange(canvas.drawing)
        }
    }
}

/// The canvas with ruled paper under the ink, scaled so the fixed-width page
/// fits the available width and scrolls down as the writing grows.
final class HandwritingPageView: UIView {
    let canvas = PKCanvasView()
    private let lines = PaperLinesView()
    private let toolPicker = PKToolPicker()
    private var paper: PaperStyle = .lined
    private var palette: ThemePalette = ReaderTheme.paper.palette

    override init(frame: CGRect) {
        super.init(frame: frame)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true
        canvas.showsHorizontalScrollIndicator = false
        canvas.insertSubview(lines, at: 0)
        addSubview(canvas)
        toolPicker.addObserver(canvas)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func apply(paper newPaper: PaperStyle, palette newPalette: ThemePalette) {
        paper = newPaper
        palette = newPalette
        backgroundColor = newPalette.uiSurface
        // PencilKit shows ink for the interface style (dark ink turns light).
        let style: UIUserInterfaceStyle = newPalette.isDarkPaper ? .dark : .light
        overrideUserInterfaceStyle = style
        toolPicker.colorUserInterfaceStyle = style
        toolPicker.overrideUserInterfaceStyle = style
        updateLines()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        guard bounds.width > 0 else { return }
        let zoom = bounds.width / HandwritingLayout.pageWidth
        if abs(canvas.zoomScale - zoom) > 0.0001 || abs(canvas.minimumZoomScale - zoom) > 0.0001 {
            canvas.minimumZoomScale = zoom
            canvas.maximumZoomScale = zoom
            canvas.zoomScale = zoom
        }
        updateContentSize()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        toolPicker.setVisible(true, forFirstResponder: canvas)
        canvas.becomeFirstResponder()
    }

    func hideToolPicker() {
        toolPicker.setVisible(false, forFirstResponder: canvas)
        toolPicker.removeObserver(canvas)
        canvas.resignFirstResponder()
    }

    /// Tall enough for the writing plus room below it, and never shorter than the view.
    func updateContentSize() {
        let zoom = canvas.zoomScale
        let drawingBounds = canvas.drawing.bounds
        let writtenHeight = drawingBounds.isNull ? 0 : (drawingBounds.maxY + HandwritingLayout.overscroll) * zoom
        let size = CGSize(width: HandwritingLayout.pageWidth * zoom, height: max(bounds.height, writtenHeight))
        if canvas.contentSize != size { canvas.contentSize = size }
        lines.frame = CGRect(origin: .zero, size: size)
        updateLines()
    }

    private func updateLines() {
        let spacing = HandwritingLayout.lineSpacing * canvas.zoomScale
        lines.configure(style: paper, lineColor: palette.uiSeparator, spacing: spacing)
    }
}
