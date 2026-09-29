import Foundation

/// JSON coding shared by every Supabase request: snake_case keys and
/// Postgres timestamps (which carry microseconds) in both directions.
enum SupabaseCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Timestamp.string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = Timestamp.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(text)")
            }
            return date
        }
        return decoder
    }
}

/// Converts between `Date` and the timestamp formats Postgres and GoTrue use,
/// e.g. "2026-09-29T17:46:00.123456+00:00" or a plain "2026-09-29".
enum Timestamp {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from text: String) -> Date? {
        // Date only (Postgres `date` columns), read as midnight UTC.
        if text.count == 10 {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            return formatter.date(from: text)
        }
        // Postgres may use a space instead of "T" and six fractional digits;
        // Foundation reliably parses exactly three.
        var normalized = text.replacingOccurrences(of: " ", with: "T")
        var hasFraction = false
        if let dot = normalized.firstIndex(of: ".") {
            var end = normalized.index(after: dot)
            while end < normalized.endIndex, normalized[end].isNumber {
                end = normalized.index(after: end)
            }
            let digits = String(normalized[normalized.index(after: dot)..<end])
            let millis = String((digits + "000").prefix(3))
            normalized.replaceSubrange(dot..<end, with: "." + millis)
            hasFraction = true
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = hasFraction ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter.date(from: normalized)
    }

    /// "yyyy-MM-dd" for Postgres `date` columns, using the given calendar's day.
    static func dayString(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Parses "yyyy-MM-dd" as the start of that day in the given calendar.
    static func day(from text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
