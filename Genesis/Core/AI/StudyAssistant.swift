import Foundation
import Observation

/// What the study assistant can do with a passage (mirrors the server's actions).
enum StudyAction: String, CaseIterable, Identifiable, Sendable {
    case explain, summarize, context, questions, children, comprehension

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explain: "Explain"
        case .summarize: "Summarize"
        case .context: "Background"
        case .questions: "Discussion"
        case .children: "For Children"
        case .comprehension: "Comprehension"
        }
    }

    var systemImage: String {
        switch self {
        case .explain: "sparkles"
        case .summarize: "text.alignleft"
        case .context: "building.columns"
        case .questions: "bubble.left.and.bubble.right"
        case .children: "figure.and.child.holdinghands"
        case .comprehension: "checklist"
        }
    }

    /// Free accounts can explain passages (a few a day); the rest is Premium.
    var isFree: Bool { self == .explain }
}

/// The passage the assistant is asked about. Verses must be in one book.
struct StudyPassage: Hashable, Sendable {
    let start: VerseID
    let end: VerseID

    init(start: VerseID, end: VerseID) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    init(chapter: ChapterID, lastVerse: Int) {
        self.init(start: chapter.firstVerse, end: VerseID(book: chapter.book, chapter: chapter.chapter, verse: max(lastVerse, 1)))
    }

    /// Where to open the reader: the first verse.
    var reference: PassageReference {
        PassageReference(
            book: .withNumber(start.book),
            chapter: start.chapter,
            verseStart: start.verse,
            verseEnd: start.chapterID == end.chapterID && end.verse != start.verse ? end.verse : nil
        )
    }

    /// "John 3:16–18", or "Genesis 1–2" across chapters. Plain hyphen for the server.
    var title: String {
        if start.chapterID == end.chapterID {
            return reference.description
        }
        return "\(BibleBook.withNumber(start.book).name) \(start.chapter):\(start.verse)\u{2013}\(end.chapter):\(end.verse)"
    }

    /// Matches the server's key; answers are kept per language.
    func cacheKey(_ action: StudyAction, language: String = AppLanguage.code) -> String {
        let base = "v1:\(action.rawValue):\(start.rawValue)-\(end.rawValue)"
        return language == "en" ? base : "\(base):\(language)"
    }
}

/// An answer from the study assistant. AI-generated: never Scripture, and
/// always shown with a label saying so.
struct StudyAnswer: Equatable, Sendable {
    let content: String
    let wasCached: Bool
}

enum StudyAssistantError: LocalizedError, Equatable {
    case signInRequired
    case premiumRequired
    case dailyLimit(Int)
    case notConfigured
    case offline
    case server(String)

    var errorDescription: String? {
        switch self {
        case .signInRequired: "Sign in to use the study assistant. A free account includes \(FreeLimits.aiRequestsPerDay) explanations a day."
        case .premiumRequired: "This study tool is part of Genesis Premium."
        case let .dailyLimit(limit): "You've used today's \(limit) study assistant answers. They reset tomorrow."
        case .notConfigured: "The study assistant isn't available right now."
        case .offline: "The study assistant needs an internet connection."
        case let .server(message): message
        }
    }
}

/// Where answers come from: the Supabase Edge Function, or canned answers in UI tests.
protocol StudyAssistantBackend: Sendable {
    /// False for the UI-test stub, which works without signing in.
    var requiresAccount: Bool { get }
    func answer(_ action: StudyAction, passage: StudyPassage, text: String, accessToken: String, signedTransaction: String?) async throws -> (answer: StudyAnswer, used: Int?, limit: Int?)
}

/// Asks the study assistant about passages and keeps the answers on the device.
///
/// Answers are the same for everyone, so they are cached locally after the
/// first request and never asked for twice from this device.
@MainActor
@Observable
final class StudyAssistant {
    /// Answers used today and today's limit, as last reported by the server.
    private(set) var usedToday: Int?
    private(set) var dailyLimit: Int?
    /// When false the app hides every study assistant entry point and never
    /// calls the server: switched off in Supabase (feature_flags.study_assistant)
    /// or by the person (Settings › Features).
    var isEnabled: Bool {
        flags.isOn(.studyAssistant) && (preferences?.isOn(.studyAssistant) ?? true)
    }

    @ObservationIgnored private let auth: AuthService
    @ObservationIgnored private let entitlements: EntitlementService
    @ObservationIgnored private let library: BibleLibrary
    @ObservationIgnored private let backend: StudyAssistantBackend?
    private let flags: FeatureFlagService
    private let preferences: FeaturePreferences?
    @ObservationIgnored private let cacheDirectory: URL

    init(auth: AuthService, entitlements: EntitlementService, library: BibleLibrary, backend: StudyAssistantBackend?, flags: FeatureFlagService, preferences: FeaturePreferences? = nil, cacheDirectory: URL = StudyAssistant.defaultCacheDirectory) {
        self.flags = flags
        self.preferences = preferences
        self.auth = auth
        self.entitlements = entitlements
        self.library = library
        self.backend = backend
        self.cacheDirectory = cacheDirectory
    }

    nonisolated static var defaultCacheDirectory: URL {
        URL.cachesDirectory.appending(path: "StudyAssistant", directoryHint: .isDirectory)
    }

    /// Live backend when Supabase is configured.
    static func liveBackend(client: SupabaseClient?) -> StudyAssistantBackend? {
        client.map(EdgeFunctionBackend.init(client:))
    }

    func canUse(_ action: StudyAction) -> Bool {
        action.isFree || entitlements.allows(.advancedAI)
    }

    /// An answer saved on this device, if there is one.
    func savedAnswer(_ action: StudyAction, passage: StudyPassage) -> StudyAnswer? {
        let url = cacheURL(passage.cacheKey(action))
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return StudyAnswer(content: text, wasCached: true)
    }

    func answer(_ action: StudyAction, passage: StudyPassage) async throws -> StudyAnswer {
        guard isEnabled else { throw StudyAssistantError.notConfigured }
        if let saved = savedAnswer(action, passage: passage) { return saved }
        guard canUse(action) else { throw StudyAssistantError.premiumRequired }
        guard let backend else { throw StudyAssistantError.notConfigured }
        var token = ""
        if backend.requiresAccount {
            guard auth.isSignedIn else { throw StudyAssistantError.signInRequired }
            do {
                token = try await auth.accessToken()
            } catch {
                throw StudyAssistantError.signInRequired
            }
        }
        let text = passageText(passage)
        let result = try await backend.answer(action, passage: passage, text: text, accessToken: token, signedTransaction: entitlements.signedTransaction)
        if let used = result.used { usedToday = used }
        if let limit = result.limit { dailyLimit = limit }
        save(result.answer.content, key: passage.cacheKey(action))
        return result.answer
    }

    /// The passage's verse text from the local database, as context for the
    /// model (which is told never to quote it).
    private func passageText(_ passage: StudyPassage) -> String {
        let verses = (try? library.current.verses(from: passage.start, through: passage.end)) ?? []
        return verses.map { "\($0.id.verse) \($0.text)" }.joined(separator: " ")
    }

    private func cacheURL(_ key: String) -> URL {
        let safe = key.replacingOccurrences(of: ":", with: "_")
        return cacheDirectory.appending(path: "\(safe).txt")
    }

    private func save(_ content: String, key: String) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? Data(content.utf8).write(to: cacheURL(key), options: .atomic)
    }
}

/// Calls the study-ai Edge Function.
struct EdgeFunctionBackend: StudyAssistantBackend {
    let client: SupabaseClient
    var requiresAccount: Bool { true }

    private struct Body: Encodable {
        let action: String
        let start: Int
        let end: Int
        let text: String
        let signedTransaction: String?
        /// The app's language; the answer is written in it.
        let language: String
    }

    private struct Reply: Decodable {
        let content: String?
        let cached: Bool?
        let usedToday: Int?
        let limit: Int?
        let error: String?
        let reason: String?
    }

    func answer(_ action: StudyAction, passage: StudyPassage, text: String, accessToken: String, signedTransaction: String?) async throws -> (answer: StudyAnswer, used: Int?, limit: Int?) {
        let body = try JSONEncoder().encode(Body(
            action: action.rawValue,
            start: passage.start.rawValue,
            end: passage.end.rawValue,
            text: text,
            signedTransaction: signedTransaction,
            language: AppLanguage.code
        ))
        let response: (data: Data, status: Int)
        do {
            response = try await client.callFunction("study-ai", body: body, accessToken: accessToken)
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw StudyAssistantError.offline
        }
        let reply = try? JSONDecoder().decode(Reply.self, from: response.data)
        switch response.status {
        case 200:
            guard let content = reply?.content, !content.isEmpty else { throw StudyAssistantError.server("The study assistant sent an empty answer.") }
            return (StudyAnswer(content: content, wasCached: reply?.cached ?? false), reply?.usedToday, reply?.limit)
        case 401:
            throw StudyAssistantError.signInRequired
        case 403 where reply?.reason == "premium_required":
            throw StudyAssistantError.premiumRequired
        case 403 where reply?.reason == "daily_limit":
            throw StudyAssistantError.dailyLimit(reply?.limit ?? FreeLimits.aiRequestsPerDay)
        case 404, 503:
            throw StudyAssistantError.notConfigured
        default:
            throw StudyAssistantError.server(reply?.error ?? "The study assistant couldn't answer just now. Please try again.")
        }
    }
}

/// Canned answers for UI tests: no network, no cost, same labels and links.
struct StubStudyBackend: StudyAssistantBackend {
    var requiresAccount: Bool { false }

    func answer(_ action: StudyAction, passage: StudyPassage, text: String, accessToken: String, signedTransaction: String?) async throws -> (answer: StudyAnswer, used: Int?, limit: Int?) {
        let content = """
        **About \(passage.title)**
        This is a sample \(action.title.lowercased()) answer used in UI tests. Compare [[John 3:16]].
        - It never quotes Scripture.
        """
        return (StudyAnswer(content: content, wasCached: false), 1, FreeLimits.aiRequestsPerDay)
    }
}
