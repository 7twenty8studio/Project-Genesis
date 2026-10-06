import Foundation
import PencilKit

/// Saves the handwritten page a moment after the last stroke rather than on
/// every stroke, and right away when the editor closes or the app leaves the
/// foreground.
@MainActor
final class DrawingAutosave {
    private var pending: PKDrawing?
    private var write: ((Data?) -> Void)?
    private var task: Task<Void, Never>?
    private let delay: Duration

    init(delay: Duration = .seconds(1)) {
        self.delay = delay
    }

    /// Remembers the newest drawing and writes it once strokes pause.
    func drawingChanged(_ drawing: PKDrawing, write: @escaping (Data?) -> Void) {
        pending = drawing
        self.write = write
        task?.cancel()
        let delay = delay
        task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes any unsaved drawing now. An empty page is written as nil.
    func flush() {
        task?.cancel()
        task = nil
        guard let drawing = pending, let write else { return }
        pending = nil
        write(drawing.strokes.isEmpty ? nil : drawing.dataRepresentation())
    }

    /// Drops any unsaved drawing, e.g. when the note is being deleted.
    func cancel() {
        task?.cancel()
        task = nil
        pending = nil
    }
}
