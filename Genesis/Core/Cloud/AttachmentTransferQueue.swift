import Foundation

/// The pending file transfers to cloud storage, as a pure value so the retry
/// rules can be tested: uploads of attachment files (after their row is
/// pushed) and removals of deleted ones. Saved between launches by
/// `AttachmentTransfers`.
///
/// Each operation is tried when due; a failure waits longer each time
/// (30 seconds, doubling, at most 6 hours) and keeps retrying, since a file
/// that never reaches the server can't be seen on the person's other devices.
struct AttachmentTransferQueue: Codable, Equatable, Sendable {
    enum Operation: Codable, Hashable, Sendable {
        /// Upload the file of the attachment with this id.
        case upload(UUID)
        /// Remove this file ("<id>.<ext>") from the person's storage folder.
        case remove(String)
    }

    struct Entry: Codable, Equatable, Sendable {
        var operation: Operation
        var attempts: Int
        /// Not tried again before this moment.
        var notBefore: Date
    }

    private(set) var entries: [Entry] = []

    static let firstRetry: TimeInterval = 30
    static let longestWait: TimeInterval = 6 * 60 * 60

    var isEmpty: Bool { entries.isEmpty }

    /// Adds an operation, once. Removing a file drops any upload of it still
    /// waiting (the attachment is gone).
    mutating func enqueue(_ operation: Operation, now: Date = .now) {
        guard !entries.contains(where: { $0.operation == operation }) else { return }
        if case let .remove(fileName) = operation {
            entries.removeAll { entry in
                guard case let .upload(id) = entry.operation else { return false }
                return fileName.hasPrefix(id.uuidString.lowercased() + ".")
            }
        }
        entries.append(Entry(operation: operation, attempts: 0, notBefore: now))
    }

    /// Operations to try now, oldest first.
    func due(at now: Date = .now) -> [Operation] {
        entries.filter { $0.notBefore <= now }.map(\.operation)
    }

    /// When the next waiting operation becomes due, if any.
    var nextDue: Date? { entries.map(\.notBefore).min() }

    mutating func succeeded(_ operation: Operation) {
        entries.removeAll { $0.operation == operation }
    }

    /// Records a failed try and when to try again.
    mutating func failed(_ operation: Operation, at now: Date = .now) {
        guard let index = entries.firstIndex(where: { $0.operation == operation }) else { return }
        entries[index].attempts += 1
        entries[index].notBefore = now.addingTimeInterval(Self.wait(afterAttempts: entries[index].attempts))
    }

    /// 30 s after the first failure, then doubling, never more than 6 hours.
    static func wait(afterAttempts attempts: Int) -> TimeInterval {
        guard attempts > 0 else { return 0 }
        let exponent = Double(min(attempts - 1, 20))
        return min(firstRetry * pow(2, exponent), longestWait)
    }

    func attempts(for operation: Operation) -> Int {
        entries.first { $0.operation == operation }?.attempts ?? 0
    }
}
