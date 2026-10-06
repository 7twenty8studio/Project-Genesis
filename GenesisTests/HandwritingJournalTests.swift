import Foundation
import PencilKit
import SwiftData
import Testing
@testable import Genesis

@Suite("Journal prompts")
struct JournalPromptTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 9))!
    }

    @Test func aSmallCuratedListOfSingleQuestions() {
        let prompts = JournalPrompts.all
        #expect(prompts.count == 20)
        #expect(Set(prompts).count == prompts.count, "No repeats")
        for prompt in prompts {
            #expect(!prompt.isEmpty)
            #expect(!prompt.contains("\n"), "One line each")
        }
    }

    @Test func sameAllDayDifferentTomorrow() {
        let morning = JournalPrompts.prompt(on: day(6), calendar: calendar)
        let evening = JournalPrompts.prompt(on: day(6).addingTimeInterval(10 * 3600), calendar: calendar)
        let tomorrow = JournalPrompts.prompt(on: day(7), calendar: calendar)
        #expect(morning == evening)
        #expect(morning != tomorrow)
        #expect(JournalPrompts.all.contains(morning))
    }

    @Test func anotherPromptCyclesThroughEveryOne() {
        var seen: Set<String> = []
        var current = JournalPrompts.all[0]
        for _ in JournalPrompts.all {
            seen.insert(current)
            let next = JournalPrompts.prompt(after: current)
            #expect(next != current)
            current = next
        }
        #expect(seen.count == JournalPrompts.all.count)
        #expect(current == JournalPrompts.all[0], "Wraps round")
        #expect(JournalPrompts.prompt(after: "Not a prompt") == JournalPrompts.all[0])
    }

    @Test func usingAPromptMakesItTheOpeningLine() {
        let prompt = JournalPrompts.all[0]
        #expect(JournalPrompts.inserting(prompt, into: "") == prompt + "\n")
        #expect(JournalPrompts.inserting(prompt, into: "Already here") == prompt + "\nAlready here")
    }
}

@Suite("Handwritten notes sync")
@MainActor
struct HandwritingSyncTests {
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private func makeNote(drawing: Data?) throws -> (Note, ModelContainer) {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let note = StudyStore(context: container.mainContext).createNote(kind: .journal, anchor: .none, body: "Evening")
        note.drawing = drawing
        return (note, container)
    }

    private func json(_ row: RemoteNote) throws -> [String: Any] {
        let data = try SupabaseCoding.encoder().encode(row)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func drawingRoundTripsAsBase64() throws {
        let bytes = Data((0..<3000).map { UInt8($0 % 251) })
        let (note, container) = try makeNote(drawing: bytes)
        _ = container
        let row = RemoteNote(note, userID: userID)

        let object = try json(row)
        #expect(object["drawing"] as? String == bytes.base64EncodedString())

        let encoded = try SupabaseCoding.encoder().encode(row)
        let decoded = try SupabaseCoding.decoder().decode(RemoteNote.self, from: encoded)
        #expect(decoded.drawingData == bytes)
        #expect(decoded.body == "Evening")
    }

    @Test func pencilKitDataSurvivesTheTrip() throws {
        let original = PKDrawing().dataRepresentation()
        let (note, container) = try makeNote(drawing: original)
        _ = container
        let encoded = try SupabaseCoding.encoder().encode(RemoteNote(note, userID: userID))
        let decoded = try SupabaseCoding.decoder().decode(RemoteNote.self, from: encoded)
        let data = try #require(decoded.drawingData)
        #expect(data == original)
        #expect(try PKDrawing(data: data).strokes.isEmpty)
    }

    @Test func noDrawingIsSentAsAnExplicitNull() throws {
        let (note, container) = try makeNote(drawing: nil)
        _ = container
        let object = try json(RemoteNote(note, userID: userID))
        #expect(object.keys.contains("drawing"), "A cleared page must clear the server's copy")
        #expect(object["drawing"] is NSNull)
    }

    @Test func oversizedDrawingIsLeftOutOfThePush() throws {
        let tooBig = Data(count: NoteDrawing.maxSyncedBase64Length / 4 * 3 + 3)
        #expect(!NoteDrawing.fitsSync(tooBig))
        let (note, container) = try makeNote(drawing: tooBig)
        _ = container
        let row = RemoteNote(note, userID: userID)
        #expect(!row.sendsDrawing)
        #expect(row.drawing == nil)
        let object = try json(row)
        #expect(!object.keys.contains("drawing"), "The server keeps what it had")
        #expect(object["body"] as? String == "Evening", "The rest of the note still syncs")
    }

    @Test func sizeLimitMatchesTheDatabase() {
        let largestThatFits = NoteDrawing.maxSyncedBase64Length / 4 * 3
        #expect(NoteDrawing.base64Length(byteCount: largestThatFits) == 2_097_152)
        #expect(NoteDrawing.fitsSync(Data(count: largestThatFits)))
        #expect(!NoteDrawing.fitsSync(Data(count: largestThatFits + 1)))
        #expect(NoteDrawing.fitsSync(nil))
        #expect(Data(count: 1000).base64EncodedString().count == NoteDrawing.base64Length(byteCount: 1000))
    }

    @Test func rowsWithoutADrawingDecode() throws {
        let json = """
        {"id":"22222222-0000-0000-0000-000000000001","user_id":"\(userID.uuidString)","title":"","body":"Hi","kind":"journal",
         "anchor_type":"none","created_at":"2026-10-06T10:00:00.000000+00:00","updated_at":"2026-10-06T10:00:00.000000+00:00",
         "deleted_at":null,"server_updated_at":"2026-10-06T10:00:01.123456+00:00"}
        """
        let row = try SupabaseCoding.decoder().decode(RemoteNote.self, from: Data(json.utf8))
        #expect(row.drawing == nil)
        #expect(row.drawingData == nil)
    }

    @Test func pushesAreSplitByDrawingSize() {
        let ranges = SyncBatching.ranges(weights: [3, 3, 3, 0, 0, 9, 1], maxCount: 3, maxWeight: 6)
        #expect(ranges == [0..<2, 2..<5, 5..<6, 6..<7])
        #expect(SyncBatching.ranges(weights: [], maxCount: 200, maxWeight: 10) == [])
        #expect(SyncBatching.ranges(weights: Array(repeating: 0, count: 450), maxCount: 200, maxWeight: 10).count == 3)
    }
}
