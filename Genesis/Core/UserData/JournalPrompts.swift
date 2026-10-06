import Foundation

/// Gentle, optional reflection prompts offered when a journal entry starts.
/// They are the app's own questions, never Scripture, and suit any tradition.
enum JournalPrompts {
    static var all: [String] { [
        String(localized: "What stood out to you in today's reading?"),
        String(localized: "What are you grateful for today?"),
        String(localized: "Where did you notice hope this week?"),
        String(localized: "What is weighing on your heart right now?"),
        String(localized: "Which words from your reading would you like to carry into tomorrow?"),
        String(localized: "What question would you like to sit with for a while?"),
        String(localized: "Who could you encourage this week, and how?"),
        String(localized: "What brought you peace today?"),
        String(localized: "What is something you are learning to let go of?"),
        String(localized: "Where do you need patience right now?"),
        String(localized: "What did today's reading show you about love?"),
        String(localized: "What would you like to remember about this season of your life?"),
        String(localized: "When did you feel most at rest recently?"),
        String(localized: "What small kindness did you receive or give today?"),
        String(localized: "What is one hope you have for the week ahead?"),
        String(localized: "Which part of your reading felt hard to understand?"),
        String(localized: "How have you grown since this time last year?"),
        String(localized: "What would you like to pray or reflect on for someone else?"),
        String(localized: "What does a quiet, faithful day look like for you?"),
        String(localized: "What surprised you in your reading today?"),
    ] }

    /// Today's prompt: the same all day, a different one the next day.
    static func prompt(on date: Date = .now, calendar: Calendar = .current) -> String {
        let prompts = all
        // Whole days between two local midnights, so the prompt changes at
        // midnight where the person is, not partway through their day.
        let reference = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let day = calendar.dateComponents([.day], from: reference, to: calendar.startOfDay(for: date)).day ?? 0
        return prompts[((day % prompts.count) + prompts.count) % prompts.count]
    }

    /// The prompt after `current`, wrapping round, for "Another prompt".
    static func prompt(after current: String) -> String {
        let prompts = all
        guard let index = prompts.firstIndex(of: current) else { return prompts[0] }
        return prompts[(index + 1) % prompts.count]
    }

    /// The prompt as the entry's opening line, keeping anything already written.
    static func inserting(_ prompt: String, into body: String) -> String {
        let rest = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? prompt + "\n" : prompt + "\n" + body
    }
}
