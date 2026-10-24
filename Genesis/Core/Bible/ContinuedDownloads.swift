@preconcurrency import BackgroundTasks
import Foundation

/// Keeps a YouVersion Bible downloading after the person leaves Versely,
/// with iOS's own progress shown (BGContinuedProcessingTask, iOS 26). A
/// YouVersion download takes several minutes (the server paces every
/// request to the Platform), and without this iOS suspends the app as soon
/// as it's left, which stopped the download.
///
/// The download itself runs as before (BibleLibrary); this only asks iOS to
/// keep the app running while it does, reports its progress (iOS ends a
/// task that reports none) and, if the person stops it from the system's
/// progress UI or iOS needs the time back, calls `onExpire` so the download
/// stops cleanly. Books already fetched are kept, so it can be continued.
/// The identifier's suffix is allowed by the wildcard in project.yml
/// (BGTaskSchedulerPermittedIdentifiers).
@MainActor
final class ContinuedDownloads {
    static let shared = ContinuedDownloads()

    /// Called with a translation id when its background time ends early.
    var onExpire: (@MainActor (String) -> Void)?

    private static let prefix = "com.7twenty8studio.versely.download."
    /// Progress units per book: room for small steps within a book.
    private static let unitsPerBook: Int64 = 100

    private var registered: Set<String> = []
    private var running: [String: BGContinuedProcessingTask] = [:]
    private var books: [String: Int] = [:]
    private var totalBooks: [String: Int] = [:]
    private var ended: Set<String> = []
    private var heartbeat: Task<Void, Never>?

    /// Starts keeping the app running for a download the person just began
    /// (it must be asked for while Versely is in front).
    func begin(id: String, title: String, books done: Int, of total: Int) {
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        let identifier = Self.prefix + id.filter { $0.isLetter || $0.isNumber }
        ended.remove(id)
        books[id] = done
        totalBooks[id] = total
        if !registered.contains(identifier) {
            let accepted = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
                MainActor.assumeIsolated {
                    guard let task = task as? BGContinuedProcessingTask else {
                        task.setTaskCompleted(success: false)
                        return
                    }
                    self?.started(task, id: id)
                }
            }
            guard accepted else { return }
            registered.insert(identifier)
        }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: title,
            subtitle: String(localized: "Downloading for offline reading")
        )
        // Now or not at all: a download that already finished needs no
        // background time later.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Not granted (or not supported here): the download still runs
            // while Versely is open, as before.
        }
    }

    /// Books in hand so far.
    func update(id: String, books done: Int) {
        books[id] = done
        guard let task = running[id] else { return }
        let floor = Int64(done) * Self.unitsPerBook
        if task.progress.completedUnitCount < floor { task.progress.completedUnitCount = floor }
    }

    /// The download finished, failed or stopped.
    func end(id: String, success: Bool) {
        ended.insert(id)
        if let task = running.removeValue(forKey: id) {
            if success { task.progress.completedUnitCount = task.progress.totalUnitCount }
            task.setTaskCompleted(success: success)
        }
        books[id] = nil
        totalBooks[id] = nil
        if running.isEmpty {
            heartbeat?.cancel()
            heartbeat = nil
        }
    }

    private func started(_ task: BGContinuedProcessingTask, id: String) {
        // Finished before iOS started the task.
        if ended.contains(id) {
            task.setTaskCompleted(success: true)
            return
        }
        running[id] = task
        let total = Int64(max(totalBooks[id] ?? 66, 1))
        task.progress.totalUnitCount = total * Self.unitsPerBook
        task.progress.completedUnitCount = Int64(books[id] ?? 0) * Self.unitsPerBook
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                guard let self, let task = self.running.removeValue(forKey: id) else { return }
                task.setTaskCompleted(success: false)
                self.onExpire?(id)
            }
        }
        startHeartbeat()
    }

    /// A book can take a minute or more while the server waits its turn, so
    /// progress moves a little within the book meanwhile (never past it), and
    /// iOS doesn't take a quiet download for a stuck one.
    private func startHeartbeat() {
        guard heartbeat == nil else { return }
        heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard let self else { return }
                for (id, task) in self.running {
                    let ceiling = Int64((self.books[id] ?? 0) + 1) * Self.unitsPerBook - 1
                    if task.progress.completedUnitCount < ceiling {
                        task.progress.completedUnitCount += 1
                    }
                }
            }
        }
    }
}
