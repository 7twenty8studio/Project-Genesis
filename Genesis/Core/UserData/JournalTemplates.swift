import Foundation

/// Starting shapes for a prayer or sermon notes (Premium, `.journalExtras`):
/// headings with a short prompt under each, in the app's language. The
/// app's own words, never Scripture.
enum JournalTemplate: String, CaseIterable, Identifiable, Sendable {
    // Prayer
    case acts, gratitude, forOthers, lament, morningOffering
    // Sermon
    case mainPoints, observation, discussion, outline

    var id: String { rawValue }

    struct Part: Hashable, Sendable {
        let heading: String
        let prompt: String
    }

    var owner: AttachmentOwner {
        switch self {
        case .acts, .gratitude, .forOthers, .lament, .morningOffering: .prayer
        case .mainPoints, .observation, .discussion, .outline: .sermon
        }
    }

    static func templates(for owner: AttachmentOwner) -> [JournalTemplate] {
        allCases.filter { $0.owner == owner }
    }

    var systemImage: String {
        switch self {
        case .acts: "hands.and.sparkles"
        case .gratitude: "heart.text.square"
        case .forOthers: "person.2"
        case .lament: "cloud.rain"
        case .morningOffering: "sunrise"
        case .mainPoints: "list.bullet.rectangle"
        case .observation: "eye"
        case .discussion: "bubble.left.and.bubble.right"
        case .outline: "list.number"
        }
    }

    /// `bundle` is for tests that read another language's strings.
    func title(bundle: Bundle? = nil) -> String {
        switch self {
        case .acts: String(localized: "ACTS (Adoration, Confession, Thanksgiving, Supplication)", bundle: bundle, comment: "Prayer template")
        case .gratitude: String(localized: "Gratitude List", bundle: bundle, comment: "Prayer template")
        case .forOthers: String(localized: "Praying for Others", bundle: bundle, comment: "Prayer template")
        case .lament: String(localized: "Lament", bundle: bundle, comment: "Prayer template: a prayer of sorrow")
        case .morningOffering: String(localized: "Morning Offering", bundle: bundle, comment: "Prayer template")
        case .mainPoints: String(localized: "Main Points", bundle: bundle, comment: "Sermon template")
        case .observation: String(localized: "Scripture, Observation, Application", bundle: bundle, comment: "Sermon template")
        case .discussion: String(localized: "Questions to Discuss", bundle: bundle, comment: "Sermon template")
        case .outline: String(localized: "Simple Outline", bundle: bundle, comment: "Sermon template")
        }
    }

    func parts(bundle: Bundle? = nil) -> [Part] {
        switch self {
        case .acts: actsParts(bundle)
        case .gratitude: gratitudeParts(bundle)
        case .forOthers: othersParts(bundle)
        case .lament: lamentParts(bundle)
        case .morningOffering: morningParts(bundle)
        case .mainPoints: mainPointsParts(bundle)
        case .observation: observationParts(bundle)
        case .discussion: discussionParts(bundle)
        case .outline: outlineParts(bundle)
        }
    }

    /// The template as text: plain headings for a prayer, Markdown ("## ",
    /// italic prompt) for sermon notes, with room to write under each.
    func text(bundle: Bundle? = nil) -> String {
        let blocks = parts(bundle: bundle).map { part in
            owner == .sermon
                ? "## \(part.heading)\n*\(part.prompt)*\n"
                : "\(part.heading)\n\(part.prompt)\n"
        }
        return blocks.joined(separator: "\n")
    }

    /// The template in place of an empty body, or as new paragraphs at
    /// `offset` (the cursor, in Characters) or at the end. Returns the text
    /// and where the cursor goes (the end of the inserted template).
    static func inserting(_ template: String, into body: String, at offset: Int? = nil) -> (text: String, cursor: Int) {
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (template, template.count)
        }
        let characters = Array(body)
        let position = min(max(0, offset ?? characters.count), characters.count)
        let before = String(characters[..<position])
        let after = String(characters[position...])
        let (prefix, suffix) = separators(before: before, after: after)
        let text = before + prefix + template + suffix + after
        return (text, before.count + prefix.count + template.count)
    }

    /// The line breaks around a template put between `before` and `after`:
    /// a blank line before it, unless it starts a paragraph already, and one
    /// after it when text follows on the same line.
    static func separators(before: String, after: String) -> (prefix: String, suffix: String) {
        var prefix = ""
        if !before.isEmpty, !before.hasSuffix("\n\n") {
            prefix = before.hasSuffix("\n") ? "\n" : "\n\n"
        }
        let suffix = !after.isEmpty && !after.hasPrefix("\n") ? "\n" : ""
        return (prefix, suffix)
    }
}

// MARK: Prayer templates

private extension JournalTemplate {
    func actsParts(_ bundle: Bundle?) -> [Part] {
        [
            Part(heading: String(localized: "Adoration", bundle: bundle, comment: "ACTS prayer heading"),
                 prompt: String(localized: "Praise God for who he is.", bundle: bundle)),
            Part(heading: String(localized: "Confession", bundle: bundle, comment: "ACTS prayer heading"),
                 prompt: String(localized: "Name what you need forgiveness for, honestly and without fear.", bundle: bundle)),
            Part(heading: String(localized: "Thanksgiving", bundle: bundle, comment: "ACTS prayer heading"),
                 prompt: String(localized: "Thank God for what he has done and given.", bundle: bundle)),
            Part(heading: String(localized: "Supplication", bundle: bundle, comment: "ACTS prayer heading: asking"),
                 prompt: String(localized: "Ask for what you and others need.", bundle: bundle)),
        ]
    }

    func gratitudeParts(_ bundle: Bundle?) -> [Part] {
        [
            Part(heading: String(localized: "Today I'm thankful for", bundle: bundle),
                 prompt: String(localized: "Three things, however small.", bundle: bundle)),
            Part(heading: String(localized: "People I'm grateful for", bundle: bundle),
                 prompt: String(localized: "Who has been a gift to you lately?", bundle: bundle)),
            Part(heading: String(localized: "Where I saw God's goodness", bundle: bundle),
                 prompt: String(localized: "A moment you don't want to forget.", bundle: bundle)),
        ]
    }

    func othersParts(_ bundle: Bundle?) -> [Part] {
        [
            Part(heading: String(localized: "Family", bundle: bundle),
                 prompt: String(localized: "Who at home needs prayer today?", bundle: bundle)),
            Part(heading: String(localized: "Friends and neighbors", bundle: bundle),
                 prompt: String(localized: "Name them and what they're carrying.", bundle: bundle)),
            Part(heading: String(localized: "Church and leaders", bundle: bundle),
                 prompt: String(localized: "Pray for your church, its leaders and those who serve.", bundle: bundle)),
            Part(heading: String(localized: "The world", bundle: bundle),
                 prompt: String(localized: "Places and people in need, near and far.", bundle: bundle)),
        ]
    }

    func lamentParts(_ bundle: Bundle?) -> [Part] {
        [
            Part(heading: String(localized: "Turn to God", bundle: bundle, comment: "Lament prayer heading"),
                 prompt: String(localized: "Speak to him plainly, as you are.", bundle: bundle)),
            Part(heading: String(localized: "Bring your complaint", bundle: bundle, comment: "Lament prayer heading"),
                 prompt: String(localized: "What hurts? What feels unfair or confusing?", bundle: bundle)),
            Part(heading: String(localized: "Ask boldly", bundle: bundle, comment: "Lament prayer heading"),
                 prompt: String(localized: "What do you long for him to do?", bundle: bundle)),
            Part(heading: String(localized: "Choose to trust", bundle: bundle, comment: "Lament prayer heading"),
                 prompt: String(localized: "Remember his faithfulness, even if only in a few words.", bundle: bundle)),
        ]
    }

    func morningParts(_ bundle: Bundle?) -> [Part] {
        [
            Part(heading: String(localized: "This day is yours", bundle: bundle, comment: "Morning offering heading"),
                 prompt: String(localized: "Offer God the hours ahead.", bundle: bundle)),
            Part(heading: String(localized: "What I'm facing", bundle: bundle, comment: "Morning offering heading"),
                 prompt: String(localized: "Meetings, tasks, conversations, worries.", bundle: bundle)),
            Part(heading: String(localized: "Help me to", bundle: bundle, comment: "Morning offering heading"),
                 prompt: String(localized: "The grace you need today: patience, courage, kindness.", bundle: bundle)),
        ]
    }
}

// MARK: Sermon templates

private extension JournalTemplate {
    func mainPointsParts(_ bundle: Bundle?) -> [Part] {
        [
            Part(heading: String(localized: "Big idea", bundle: bundle, comment: "Sermon template heading"),
                 prompt: String(localized: "The sermon in one sentence.", bundle: bundle)),
            Part(heading: String(localized: "Main points", bundle: bundle, comment: "Sermon template heading"),
                 prompt: String(localized: "What were the key points?", bundle: bundle)),
            Part(heading: String(localized: "Takeaway", bundle: bundle, comment: "Sermon template heading"),
                 prompt: String(localized: "One thing to remember this week.", bundle: bundle)),
        ]
    }

    func observationParts(_ bundle: Bundle?) -> [Part] {
        [
            Part(heading: String(localized: "Scripture", bundle: bundle, comment: "Sermon template heading"),
                 prompt: String(localized: "Which passage was preached? Attach it below.", bundle: bundle)),
            Part(heading: String(localized: "Observation", bundle: bundle, comment: "Sermon template heading"),
                 prompt: String(localized: "What does the passage say? What stood out?", bundle: bundle)),
            Part(heading: String(localized: "Application", bundle: bundle, comment: "Sermon template heading"),
                 prompt: String(localized: "What will you do differently because of it?", bundle: bundle)),
        ]
    }

    func discussionParts(_ bundle: Bundle?) -> [Part] {
        [
            Part(heading: String(localized: "What I learned", bundle: bundle, comment: "Sermon template heading"),
                 prompt: String(localized: "Something new, or something seen afresh.", bundle: bundle)),
            Part(heading: String(localized: "Questions to discuss", bundle: bundle, comment: "Sermon template heading"),
                 prompt: String(localized: "Questions for your group or family.", bundle: bundle)),
            Part(heading: String(localized: "To pray about", bundle: bundle, comment: "Sermon template heading"),
                 prompt: String(localized: "Turn what you heard into prayer.", bundle: bundle)),
        ]
    }

    func outlineParts(_ bundle: Bundle?) -> [Part] {
        [
            Part(heading: String(localized: "Introduction", bundle: bundle, comment: "Sermon template heading"),
                 prompt: String(localized: "How did the sermon begin?", bundle: bundle)),
            Part(heading: String(localized: "Points", bundle: bundle, comment: "Sermon template heading"),
                 prompt: String(localized: "First, second, third.", bundle: bundle)),
            Part(heading: String(localized: "Conclusion", bundle: bundle, comment: "Sermon template heading"),
                 prompt: String(localized: "How did it end? What was the call?", bundle: bundle)),
        ]
    }
}
