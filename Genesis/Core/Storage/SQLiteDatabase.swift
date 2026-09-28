import Foundation
import SQLite3

/// A minimal, read-only SQLite wrapper for the bundled Bible databases.
///
/// Opened with `immutable=1`, so SQLite skips locking and journal checks, which
/// keeps first reads fast. Access is serialised with a lock so one connection
/// can be shared across tasks.
final class SQLiteDatabase: @unchecked Sendable {
    enum Failure: Error, CustomStringConvertible {
        case open(path: String, message: String)
        case prepare(sql: String, message: String)
        case step(message: String)

        var description: String {
            switch self {
            case let .open(path, message): "Could not open \(path): \(message)"
            case let .prepare(sql, message): "Could not prepare \(sql): \(message)"
            case let .step(message): "Query failed: \(message)"
            }
        }
    }

    enum Value: Sendable {
        case int(Int)
        case text(String)
    }

    /// Read access to the current result row.
    struct Row {
        fileprivate let statement: OpaquePointer

        func int(_ column: Int32) -> Int {
            Int(sqlite3_column_int64(statement, column))
        }

        func bool(_ column: Int32) -> Bool {
            sqlite3_column_int64(statement, column) != 0
        }

        func text(_ column: Int32) -> String {
            guard let pointer = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: pointer)
        }
    }

    private let handle: OpaquePointer
    private let lock = NSLock()

    /// SQLite should copy bound strings, since Swift may free them before the step.
    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    init(readOnly url: URL) throws {
        var connection: OpaquePointer?
        let uri = url.absoluteString + "?immutable=1"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(uri, &connection, flags, nil)
        guard status == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "status \(status)"
            if let connection { sqlite3_close(connection) }
            throw Failure.open(path: url.lastPathComponent, message: message)
        }
        handle = connection
    }

    deinit {
        sqlite3_close(handle)
    }

    /// Runs a query and maps every result row.
    func query<T>(_ sql: String, _ arguments: [Value] = [], map: (Row) throws -> T) throws -> [T] {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Failure.prepare(sql: sql, message: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        for (index, argument) in arguments.enumerated() {
            let position = Int32(index + 1)
            switch argument {
            case let .int(value):
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case let .text(value):
                sqlite3_bind_text(statement, position, value, -1, Self.transient)
            }
        }

        var results: [T] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_ROW {
                results.append(try map(Row(statement: statement)))
            } else if status == SQLITE_DONE {
                break
            } else {
                throw Failure.step(message: String(cString: sqlite3_errmsg(handle)))
            }
        }
        return results
    }
}
