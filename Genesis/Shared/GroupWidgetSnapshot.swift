import Foundation
import WidgetKit

/// A group's reading-plan progress for the Group Progress widget, written by
/// the app (the group opened most recently) into the App Group. Display
/// names only; nothing anyone wrote. Shared by the app and the widgets.
struct GroupWidgetSnapshot: Codable, Equatable, Sendable {
    struct Member: Codable, Equatable, Sendable {
        let name: String
        /// 0...1 of the plan's days read.
        let fraction: Double
        let readToday: Bool
    }

    let groupID: UUID
    let groupName: String
    let planTitle: String
    /// Today's day in the plan (0 before it starts).
    let day: Int
    let dayCount: Int
    let dayTitle: String?
    let readTodayCount: Int
    let memberCount: Int
    let members: [Member]
    let updatedAt: Date

    static let fileName = "group-widget.json"
    static let widgetKind = "GroupProgress"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?
            .appending(path: fileName)
    }

    static func load() -> GroupWidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GroupWidgetSnapshot.self, from: data)
    }

    func save() throws {
        guard let url = Self.fileURL else { return }
        // Unchanged apart from the time: leave the widget alone.
        if let saved = Self.load(), saved.isSame(as: self) { return }
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    func isSame(as other: GroupWidgetSnapshot) -> Bool {
        groupID == other.groupID && groupName == other.groupName && planTitle == other.planTitle && day == other.day
            && dayCount == other.dayCount && dayTitle == other.dayTitle && readTodayCount == other.readTodayCount
            && memberCount == other.memberCount && members == other.members
    }

    static func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static let placeholder = GroupWidgetSnapshot(
        groupID: UUID(),
        groupName: String(localized: "Tuesday Bible Study", comment: "Sample group name in the widget gallery"),
        planTitle: String(localized: "The Gospels in 30 Days"),
        day: 12,
        dayCount: 30,
        dayTitle: String(localized: "John 3\u{2013}5", comment: "Bible reference: the Gospel of John, chapters 3 to 5"),
        readTodayCount: 4,
        memberCount: 6,
        members: [
            Member(name: String(localized: "You"), fraction: 0.4, readToday: true),
            Member(name: "Ana", fraction: 0.4, readToday: true),
            Member(name: "David", fraction: 0.33, readToday: false),
            Member(name: "Grace", fraction: 0.3, readToday: true),
        ],
        updatedAt: .now
    )
}
