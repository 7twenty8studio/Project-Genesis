import Foundation
import Testing
@testable import Genesis

/// Counts calls so tests can see when the device cache answers instead.
private final class CountingBackend: StudyAssistantBackend, @unchecked Sendable {
    var requiresAccount: Bool { false }
    private let lock = NSLock()
    private var _calls: [(StudyAction, String)] = []
    var calls: [(StudyAction, String)] { lock.withLock { _calls } }

    func answer(_ action: StudyAction, passage: StudyPassage, text: String, accessToken: String, signedTransaction: String?) async throws -> (answer: StudyAnswer, used: Int?, limit: Int?) {
        lock.withLock { _calls.append((action, text)) }
        return (StudyAnswer(content: "Notes on \(passage.title). See [[Romans 8:28]].", wasCached: false), 1, 3)
    }
}

@Suite("Study assistant")
@MainActor
struct StudyAssistantTests {
    private func make(premium: Bool, backend: StudyAssistantBackend) -> StudyAssistant {
        let defaults = UserDefaults(suiteName: "StudyAssistantTests-\(UUID())")!
        let cache = URL.temporaryDirectory.appending(path: "study-\(UUID())", directoryHint: .isDirectory)
        return StudyAssistant(
            auth: AuthService(client: nil, restoresSession: false),
            entitlements: EntitlementService(defaults: defaults, override: premium),
            library: BibleLibrary(defaults: defaults),
            backend: backend,
            cacheDirectory: cache
        )
    }

    private let john3 = StudyPassage(start: VerseID(book: 43, chapter: 3, verse: 16), end: VerseID(book: 43, chapter: 3, verse: 18))

    @Test func passageTitlesAndKeys() {
        #expect(john3.title == "John 3:16\u{2013}18")
        #expect(john3.cacheKey(.explain) == "v1:explain:43003016-43003018")
        let reversed = StudyPassage(start: john3.end, end: john3.start)
        #expect(reversed == john3)
    }

    @Test func freeCanOnlyExplain() async throws {
        let backend = CountingBackend()
        let assistant = make(premium: false, backend: backend)
        #expect(assistant.canUse(.explain))
        #expect(!assistant.canUse(.questions))
        await #expect(throws: StudyAssistantError.premiumRequired) {
            _ = try await assistant.answer(.questions, passage: john3)
        }
        #expect(backend.calls.isEmpty)
    }

    @Test func sendsVerseTextAsContextAndCachesTheAnswer() async throws {
        let backend = CountingBackend()
        let assistant = make(premium: true, backend: backend)
        let first = try await assistant.answer(.context, passage: john3)
        #expect(!first.wasCached)
        let sentText = backend.calls.first?.1 ?? ""
        #expect(sentText.hasPrefix("16 For God so loved the world"))
        let second = try await assistant.answer(.context, passage: john3)
        #expect(second.wasCached)
        #expect(second.content == first.content)
        #expect(backend.calls.count == 1, "The second answer comes from the device")
        #expect(assistant.usedToday == 1)
        #expect(assistant.dailyLimit == 3)
    }

    @Test func notConfiguredWithoutBackend() async {
        let assistant = StudyAssistant(
            auth: AuthService(client: nil, restoresSession: false),
            entitlements: EntitlementService(defaults: UserDefaults(suiteName: "x-\(UUID())")!, override: true),
            library: BibleLibrary(),
            backend: nil,
            cacheDirectory: URL.temporaryDirectory.appending(path: "none-\(UUID())")
        )
        await #expect(throws: StudyAssistantError.notConfigured) {
            _ = try await assistant.answer(.explain, passage: john3)
        }
    }

    @Test func referencesBecomeReaderLinks() {
        let linked = StudyText.linked("Compare [[John 3:16]] and [[Rom 8:28-30]]; not [[Hezekiah 1:1]].")
        #expect(linked == "Compare [John 3:16](genesis://read/43003016) and [Rom 8:28-30](genesis://read/45008028); not Hezekiah 1:1.")
        let styled = StudyText.attributed("**Meaning** of [[John 3:16]]")
        let links = styled.runs.compactMap(\.link)
        #expect(links == [URL(string: "genesis://read/43003016")!])
        #expect(String(styled.characters) == "Meaning of John 3:16")
    }
}
