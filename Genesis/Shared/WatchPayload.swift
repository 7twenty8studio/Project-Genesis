import Foundation

/// What the iPhone sends to Apple Watch (WatchConnectivity application
/// context): two weeks of verses of the day, verbatim from the Bible on the
/// phone. The watch saves it where its app and complications can read it.
/// Shared by the iPhone app, the watch app and the watch widgets.
struct WatchPayload: Codable, Equatable, Sendable {
    var generatedAt: Date
    var translation: String
    /// Verse of the day on Apple Watch is part of Premium.
    var isPremium: Bool
    var verses: [WidgetSnapshot.DailyVerse]

    static let contextKey = "payload"
    static let fileName = "watch-payload.json"

    static var fileURL: URL? {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return container?.appending(path: fileName)
    }

    static func load() -> WatchPayload? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }

    func save() throws {
        guard let url = Self.fileURL else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// The verse for a calendar day, falling back to the most recent one.
    func verse(on date: Date, calendar: Calendar = .current) -> WidgetSnapshot.DailyVerse? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return verses.first { $0.day == day } ?? verses.last { $0.day < day } ?? verses.first
    }
}
