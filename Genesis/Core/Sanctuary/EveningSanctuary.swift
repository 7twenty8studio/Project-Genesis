import Foundation

/// Rules for Evening Sanctuary (Premium): when Home offers it, and the sleep
/// timer's choices. The view lives in Features/Sanctuary.
enum EveningSanctuary {
    /// Home offers the sanctuary from 6 pm until 4 am, local time.
    static let eveningStartHour = 18
    static let eveningEndHour = 4

    /// Sleep timer lengths, in minutes.
    static let sleepTimerChoices = [15, 30, 45, 60]

    /// How long the room takes to go dark when the sleep timer ends.
    static let closingFade: TimeInterval = 4

    static func isEvening(_ date: Date = .now, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= eveningStartHour || hour < eveningEndHour
    }

    /// When a sleep timer started at `start` ends (nil for no timer or a
    /// length that isn't offered).
    static func sleepTimerEnd(minutes: Int?, from start: Date) -> Date? {
        guard let minutes, sleepTimerChoices.contains(minutes) else { return nil }
        return start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// Home's card and the reader's moon button show in the evening (the More
    /// menu offers it at any hour). UI tests never see them unless launched
    /// with `-uiTestingEvening`, which shows them at any hour.
    static func showsHomeCard(
        now: Date = .now,
        calendar: Calendar = .current,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if arguments.contains("-uiTesting") {
            return arguments.contains("-uiTestingEvening")
        }
        return isEvening(now, calendar: calendar)
    }
}
