import Foundation
import ImageIO
import PDFKit
import SwiftData
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Genesis

// Premium extras for the prayer journal and sermon notes: attachments,
// their sync, templates and PDF export.

/// Swift Testing has its own `Attachment` type.
private typealias JournalAttachment = Genesis.Attachment

@Suite("Attachment limits")
struct AttachmentLimitTests {
    @Test func prayersHoldPhotosAndRecordingsOnly() {
        #expect(AttachmentLimits.maximum(.photo, for: .prayer) == 10)
        #expect(AttachmentLimits.maximum(.audio, for: .prayer) == 5)
        #expect(AttachmentLimits.maximum(.pdf, for: .prayer) == 0)
        #expect(AttachmentLimits.maximum(.drawing, for: .prayer) == 0)
        #expect(!AttachmentLimits.canAdd(.pdf, to: .prayer, existing: []))
    }

    @Test func sermonsHoldEveryKind() {
        #expect(AttachmentLimits.maximum(.photo, for: .sermon) == 10)
        #expect(AttachmentLimits.maximum(.audio, for: .sermon) == 5)
        #expect(AttachmentLimits.maximum(.pdf, for: .sermon) == 3)
        #expect(AttachmentLimits.maximum(.drawing, for: .sermon) == 5)
    }

    @Test func countsOnlyTheSameKind() {
        let existing: [AttachmentKind] = Array(repeating: .photo, count: 9) + [.audio, .pdf, .pdf, .pdf]
        #expect(AttachmentLimits.remaining(.photo, for: .sermon, existing: existing) == 1)
        #expect(AttachmentLimits.remaining(.pdf, for: .sermon, existing: existing) == 0)
        #expect(AttachmentLimits.remaining(.audio, for: .sermon, existing: existing) == 4)
        let full = existing + [.photo, .photo]
        #expect(AttachmentLimits.remaining(.photo, for: .sermon, existing: full) == 0, "Never negative")
    }

    @Test func fileSizes() {
        #expect(AttachmentLimits.fits(byteCount: 25 * 1024 * 1024, kind: .pdf))
        #expect(!AttachmentLimits.fits(byteCount: 25 * 1024 * 1024 + 1, kind: .pdf))
        #expect(!AttachmentLimits.fits(byteCount: 0, kind: .photo))
        #expect(AttachmentLimits.maxAudioDuration == 7200)
        #expect(AttachmentLimits.audioBitRate == 64_000)
    }

    @Test func downscalingKeepsTheShape() {
        #expect(AttachmentLimits.scaledPixelSize(CGSize(width: 4032, height: 3024)) == CGSize(width: 2048, height: 1536))
        #expect(AttachmentLimits.scaledPixelSize(CGSize(width: 3024, height: 4032)) == CGSize(width: 1536, height: 2048))
        #expect(AttachmentLimits.scaledPixelSize(CGSize(width: 4096, height: 4096)) == CGSize(width: 2048, height: 2048))
    }

    @Test func smallPhotosAreNeverEnlarged() {
        #expect(AttachmentLimits.scaledPixelSize(CGSize(width: 800, height: 600)) == CGSize(width: 800, height: 600))
        #expect(AttachmentLimits.scaledPixelSize(CGSize(width: 2048, height: 10)) == CGSize(width: 2048, height: 10))
    }

    @Test func thinPanoramasKeepAtLeastOnePixel() {
        #expect(AttachmentLimits.scaledPixelSize(CGSize(width: 100_000, height: 20)) == CGSize(width: 2048, height: 1))
    }

    @Test func kindsMapToTheBucketsFileTypes() {
        #expect(AttachmentKind.photo.contentType == "image/jpeg")
        #expect(AttachmentKind.audio.contentType == "audio/mp4")
        #expect(AttachmentKind.pdf.contentType == "application/pdf")
        #expect(AttachmentKind.drawing.contentType == "application/octet-stream")
        #expect(AttachmentKind.audio.fileExtension == "m4a")
    }
}

@Suite("Photo preparation")
struct PhotoPreparationTests {
    /// A JPEG of the given size carrying a GPS location, like a phone photo.
    private func photoWithLocation(width: Int, height: Int) throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let cgImage = try #require(image.cgImage)
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 41.9, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 12.5, kCGImagePropertyGPSLongitudeRef: "E"]
        let properties: [CFString: Any] = [kCGImagePropertyGPSDictionary: gps]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        let finished = CGImageDestinationFinalize(destination)
        #expect(finished)
        return output as Data
    }

    @Test func largePhotosAreDownscaledAndLoseTheirLocation() throws {
        let original = try photoWithLocation(width: 3000, height: 2250)
        let hadLocation = AttachmentMedia.hasLocation(original)
        #expect(hadLocation, "The test photo carries a location")
        let prepared = try #require(AttachmentMedia.preparedPhoto(from: original))
        let size = AttachmentMedia.pixelSize(of: prepared)
        #expect(size == CGSize(width: 2048, height: 1536))
        let hasLocation = AttachmentMedia.hasLocation(prepared)
        #expect(!hasLocation, "No location leaves the device")
    }

    @Test func smallPhotosKeepTheirSize() throws {
        let original = try photoWithLocation(width: 640, height: 480)
        let prepared = try #require(AttachmentMedia.preparedPhoto(from: original))
        let size = AttachmentMedia.pixelSize(of: prepared)
        #expect(size == CGSize(width: 640, height: 480))
    }

    @Test func notAnImage() {
        let prepared = AttachmentMedia.preparedPhoto(from: Data("hello".utf8))
        #expect(prepared == nil)
        let pages = AttachmentMedia.pdfPageCount(Data("%PDF-nonsense".utf8))
        #expect(pages == nil)
    }
}

@Suite("Attachment storage paths")
struct AttachmentPathTests {
    @Test func pathsUseTheAccountsFolderInLowercase() {
        let user = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!
        let id = UUID(uuidString: "11111111-AAAA-BBBB-CCCC-222222222222")!
        let path = AttachmentPaths.storagePath(userID: user, id: id, kind: .photo)
        #expect(path == "abcdef01-2345-6789-abcd-ef0123456789/11111111-aaaa-bbbb-cccc-222222222222.jpg")
        #expect(AttachmentPaths.fileName(id: id, kind: .drawing) == "11111111-aaaa-bbbb-cccc-222222222222.drawing")
        #expect(AttachmentPaths.bucket == "attachments")
    }
}

@Suite("Attachment transfer queue")
struct AttachmentTransferQueueTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func waitsLongerAfterEachFailure() {
        #expect(AttachmentTransferQueue.wait(afterAttempts: 0) == 0)
        #expect(AttachmentTransferQueue.wait(afterAttempts: 1) == 30)
        #expect(AttachmentTransferQueue.wait(afterAttempts: 2) == 60)
        #expect(AttachmentTransferQueue.wait(afterAttempts: 3) == 120)
        #expect(AttachmentTransferQueue.wait(afterAttempts: 12) == 6 * 60 * 60, "Never more than six hours")
        #expect(AttachmentTransferQueue.wait(afterAttempts: 500) == 6 * 60 * 60)
    }

    @Test func eachOperationOnce() {
        var queue = AttachmentTransferQueue()
        let id = UUID()
        queue.enqueue(.upload(id), now: start)
        queue.enqueue(.upload(id), now: start)
        #expect(queue.entries.count == 1)
        #expect(queue.due(at: start) == [.upload(id)])
    }

    @Test func aFailureWaitsThenIsDueAgain() {
        var queue = AttachmentTransferQueue()
        let id = UUID()
        queue.enqueue(.upload(id), now: start)
        queue.failed(.upload(id), at: start)
        #expect(queue.due(at: start.addingTimeInterval(29)).isEmpty)
        #expect(queue.due(at: start.addingTimeInterval(30)) == [.upload(id)])
        #expect(queue.attempts(for: .upload(id)) == 1)
        #expect(queue.nextDue == start.addingTimeInterval(30))
        queue.failed(.upload(id), at: start.addingTimeInterval(30))
        #expect(queue.due(at: start.addingTimeInterval(89)).isEmpty)
        #expect(queue.due(at: start.addingTimeInterval(90)) == [.upload(id)])
        queue.succeeded(.upload(id))
        #expect(queue.isEmpty)
        #expect(queue.nextDue == nil)
    }

    @Test func removingAFileDropsItsWaitingUpload() {
        var queue = AttachmentTransferQueue()
        let id = UUID()
        let other = UUID()
        queue.enqueue(.upload(id), now: start)
        queue.enqueue(.upload(other), now: start)
        queue.enqueue(.remove(AttachmentPaths.fileName(id: id, kind: .photo)), now: start)
        let operations = queue.entries.map(\.operation)
        #expect(operations == [.upload(other), .remove(AttachmentPaths.fileName(id: id, kind: .photo))])
    }

    @Test func survivesARelaunch() throws {
        var queue = AttachmentTransferQueue()
        queue.enqueue(.upload(UUID()), now: start)
        queue.enqueue(.remove("abc.jpg"), now: start)
        queue.failed(.remove("abc.jpg"), at: start)
        let data = try JSONEncoder().encode(queue)
        let decoded = try JSONDecoder().decode(AttachmentTransferQueue.self, from: data)
        #expect(decoded == queue)
    }
}

@Suite("Attachment sync rows")
@MainActor
struct AttachmentSyncRowTests {
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    /// Models live in a container, as in the app.
    private func insert(_ attachment: JournalAttachment) throws -> ModelContainer {
        let container = try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.insert(attachment)
        return container
    }

    private func json(_ row: RemoteAttachment) throws -> [String: Any] {
        let data = try SupabaseCoding.encoder().encode(row)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(object)
    }

    @Test func goesUpWithItsStoragePathAndExplicitNulls() throws {
        let attachment = JournalAttachment(owner: .sermon, ownerID: UUID(), kind: .photo)
        let container = try insert(attachment)
        _ = container
        attachment.byteSize = 1234
        attachment.caption = "Bulletin"
        let object = try json(RemoteAttachment(attachment, userID: userID))
        #expect(object["owner_kind"] as? String == "sermon")
        #expect(object["kind"] as? String == "photo")
        #expect(object["storage_path"] as? String == AttachmentPaths.storagePath(userID: userID, id: attachment.id, kind: .photo))
        #expect(object["bytes"] as? Int == 1234)
        #expect(object["duration_seconds"] is NSNull)
        #expect(object["page_count"] is NSNull)
        #expect(object["caption"] as? String == "Bulletin")
        #expect(!object.keys.contains("needs_upload"), "Upload state stays on the device")
        #expect(!object.keys.contains("deleted_at"))
    }

    @Test func roundTrip() throws {
        let attachment = JournalAttachment(owner: .prayer, ownerID: UUID(), kind: .audio, date: Date(timeIntervalSince1970: 1_791_000_000))
        let container = try insert(attachment)
        _ = container
        attachment.duration = 65.5
        attachment.sortOrder = 3
        let encoded = try SupabaseCoding.encoder().encode(RemoteAttachment(attachment, userID: userID))
        let decoded = try SupabaseCoding.decoder().decode(RemoteAttachment.self, from: encoded)
        #expect(decoded.id == attachment.id)
        #expect(decoded.ownerId == attachment.ownerID)
        #expect(decoded.durationSeconds == 65.5)
        #expect(decoded.sortOrder == 3)
        #expect(decoded.known?.owner == .prayer)
        #expect(decoded.known?.kind == .audio)
    }

    @Test func rowsWithoutOptionalFieldsDecode() throws {
        let json = """
        {"id":"33333333-0000-0000-0000-000000000001","user_id":"\(userID.uuidString)",
         "owner_kind":"sermon","owner_id":"33333333-0000-0000-0000-000000000002","kind":"pdf",
         "created_at":"2026-10-04T15:00:00.000000+00:00","updated_at":"2026-10-04T16:00:00.000000+00:00",
         "server_updated_at":"2026-10-04T16:00:01.123456+00:00"}
        """
        let row = try SupabaseCoding.decoder().decode(RemoteAttachment.self, from: Data(json.utf8))
        #expect(row.caption.isEmpty)
        #expect(row.bytes == 0)
        #expect(row.pageCount == nil)
        #expect(row.durationSeconds == nil)
        #expect(row.sortOrder == 0)
        #expect(row.deletedAt == nil)
        #expect(row.known?.kind == .pdf)
    }

    @Test func kindsFromALaterVersionAreLeftAlone() throws {
        let json = """
        {"id":"33333333-0000-0000-0000-000000000003","user_id":"\(userID.uuidString)",
         "owner_kind":"journal","owner_id":"33333333-0000-0000-0000-000000000002","kind":"video",
         "created_at":"2026-10-04T15:00:00.000000+00:00","updated_at":"2026-10-04T16:00:00.000000+00:00"}
        """
        let row = try SupabaseCoding.decoder().decode(RemoteAttachment.self, from: Data(json.utf8))
        #expect(row.known == nil)
    }
}

@Suite("Attachments in the store and their files", .serialized)
@MainActor
struct AttachmentStoreTests {
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "attachments-\(UUID())"))
    }

    @Test func addingRespectsTheLimits() throws {
        let container = try makeContainer()
        let store = StudyStore(context: container.mainContext)
        let prayer = store.createPrayer()
        let pdf = store.addAttachment(kind: .pdf, to: .prayer, ownerID: prayer.id, byteSize: 10)
        #expect(pdf == nil, "Prayers don't hold PDFs")
        for _ in 0..<10 {
            store.addAttachment(kind: .photo, to: .prayer, ownerID: prayer.id, byteSize: 10)
        }
        let eleventh = store.addAttachment(kind: .photo, to: .prayer, ownerID: prayer.id, byteSize: 10)
        #expect(eleventh == nil)
        let orders = store.attachments(for: .prayer, id: prayer.id).map(\.sortOrder)
        #expect(orders == Array(0..<10))
        let canAddRecording = store.canAttach(.audio, to: .prayer, id: prayer.id)
        #expect(canAddRecording)
    }

    @Test func movingReorders() throws {
        let container = try makeContainer()
        let store = StudyStore(context: container.mainContext)
        let owner = UUID()
        let first = try #require(store.addAttachment(kind: .photo, to: .sermon, ownerID: owner, byteSize: 1))
        let second = try #require(store.addAttachment(kind: .pdf, to: .sermon, ownerID: owner, byteSize: 1))
        store.move(second, by: -1)
        let ids = store.attachments(for: .sermon, id: owner).map(\.id)
        #expect(ids == [second.id, first.id])
    }

    @Test func deletingAPrayerSoftDeletesItsAttachmentsAndFiles() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = StudyStore(context: context)
        let files = AttachmentFiles.temporary()
        let transfers = AttachmentTransfers(files: files, storage: InMemoryAttachmentStorage(), defaults: try defaults())
        AttachmentTransfers.app = transfers
        defer { AttachmentTransfers.app = nil }

        let prayer = store.createPrayer()
        prayer.title = "Healing"
        let photo = try #require(store.addAttachment(kind: .photo, to: .prayer, ownerID: prayer.id, byteSize: 3))
        try files.write(Data([1, 2, 3]), to: photo.fileName)
        let photoID = photo.id
        let fileName = photo.fileName
        let prayerID = prayer.id

        store.delete(prayer)

        let tombstones = try context.fetch(FetchDescriptor<Tombstone>())
        let tables = Set(tombstones.map(\.table))
        #expect(tables == [SyncTable.prayers, SyncTable.attachments])
        let deletedIDs = Set(tombstones.map(\.recordID))
        #expect(deletedIDs == [photoID, prayerID])
        let remaining = try context.fetchCount(FetchDescriptor<JournalAttachment>())
        #expect(remaining == 0)
        let fileExists = files.exists(fileName)
        #expect(!fileExists, "The local file goes at once")
        let pending = transfers.pendingOperations
        #expect(pending == [.remove(fileName)], "The stored file is removed on the next sync")
    }

    @Test func uploadsRetryAfterAFailure() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = StudyStore(context: context)
        let files = AttachmentFiles.temporary()
        let storage = InMemoryAttachmentStorage(failingUploads: 1)
        let transfers = AttachmentTransfers(files: files, storage: storage, defaults: try defaults())
        let user = userID
        transfers.userID = { user }

        let attachment = try #require(store.addAttachment(kind: .photo, to: .sermon, ownerID: UUID(), byteSize: 3))
        let data = Data([7, 8, 9])
        try files.write(data, to: attachment.fileName)
        let path = AttachmentPaths.storagePath(userID: user, fileName: attachment.fileName)
        let start = Date.now

        await transfers.run(context: context, now: start)
        #expect(attachment.needsUpload, "The first try failed")
        let afterFailure = transfers.pendingOperations
        #expect(afterFailure == [.upload(attachment.id)])

        await transfers.run(context: context, now: start.addingTimeInterval(10))
        let stillWaiting = await storage.objects[path]
        #expect(stillWaiting == nil, "Not retried before its wait is over")

        await transfers.run(context: context, now: start.addingTimeInterval(31))
        let uploaded = await storage.objects[path]
        #expect(uploaded == data)
        #expect(!attachment.needsUpload)
        let pending = transfers.pendingOperations
        #expect(pending.isEmpty)
    }

    @Test func missingFilesDownloadOnDemand() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let files = AttachmentFiles.temporary()
        let storage = InMemoryAttachmentStorage()
        let transfers = AttachmentTransfers(files: files, storage: storage, defaults: try defaults())
        let user = userID
        transfers.userID = { user }
        let attachment = JournalAttachment(owner: .prayer, ownerID: UUID(), kind: .photo)
        attachment.needsUpload = false
        context.insert(attachment)
        try await storage.upload(Data([4, 5]), path: AttachmentPaths.storagePath(userID: user, fileName: attachment.fileName), contentType: "image/jpeg")

        let before = transfers.fileURL(for: attachment)
        #expect(before == nil)
        await transfers.ensureFile(for: attachment)
        let after = transfers.fileURL(for: attachment)
        #expect(after != nil)
        let saved = try files.read(attachment.fileName)
        #expect(saved == Data([4, 5]))
    }

    @Test func aFileNeverUploadedIsMarkedUnavailable() async throws {
        let files = AttachmentFiles.temporary()
        let transfers = AttachmentTransfers(files: files, storage: InMemoryAttachmentStorage(), defaults: try defaults())
        let user = userID
        transfers.userID = { user }
        let attachment = JournalAttachment(owner: .prayer, ownerID: UUID(), kind: .audio)
        await transfers.ensureFile(for: attachment)
        let unavailable = transfers.unavailable.contains(attachment.id)
        #expect(unavailable)
    }
}

@Suite("Journal templates")
struct JournalTemplateTests {
    private func spanishBundle() throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: "es", ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func eachOwnerHasItsTemplates() {
        let prayer = JournalTemplate.templates(for: .prayer)
        let sermon = JournalTemplate.templates(for: .sermon)
        #expect(prayer == [.acts, .gratitude, .forOthers, .lament, .morningOffering])
        #expect(sermon == [.mainPoints, .observation, .discussion, .outline])
    }

    @Test func actsInEnglish() {
        let text = JournalTemplate.acts.text()
        #expect(text.hasPrefix("Adoration\n"))
        #expect(text.contains("Confession\n"))
        #expect(text.contains("Thanksgiving\n"))
        #expect(text.contains("Supplication\n"))
        #expect(!text.contains("## "), "Prayers are plain text")
    }

    @Test func sermonTemplatesAreMarkdown() {
        let text = JournalTemplate.observation.text()
        #expect(text.hasPrefix("## Scripture\n*"))
        let headings = SermonMarkdown.blocks(text).filter { $0.kind == .heading }.map(\.text)
        #expect(headings == ["Scripture", "Observation", "Application"])
    }

    @Test func actsInSpanish() throws {
        let spanish = try spanishBundle()
        let text = JournalTemplate.acts.text(bundle: spanish)
        #expect(text.hasPrefix("Adoración\n"))
        #expect(text.contains("Súplica\n"))
        let title = JournalTemplate.acts.title(bundle: spanish)
        #expect(title.hasPrefix("ACAS"))
        let outline = JournalTemplate.outline.text(bundle: spanish)
        #expect(outline.hasPrefix("## Introducción\n"))
    }

    @Test(arguments: JournalTemplate.allCases)
    func everyTemplateHasHeadingsAndPromptsInBothLanguages(_ template: JournalTemplate) throws {
        let spanish = try spanishBundle()
        let english = template.parts()
        let translated = template.parts(bundle: spanish)
        #expect(english.count >= 3)
        let blanks = english.filter { $0.heading.isEmpty || $0.prompt.isEmpty }
        #expect(blanks.isEmpty)
        #expect(translated.count == english.count)
        #expect(translated != english, "Spanish differs from English")
    }

    @Test func fillsAnEmptyBody() {
        let result = JournalTemplate.inserting("A\nB\n", into: "  \n")
        #expect(result.text == "A\nB\n")
        #expect(result.cursor == 4)
    }

    @Test func goesAfterWhatsWrittenAsNewParagraphs() {
        let result = JournalTemplate.inserting("T\n", into: "Dear Lord")
        #expect(result.text == "Dear Lord\n\nT\n")
        #expect(result.cursor == result.text.count)
    }

    @Test func goesAtTheCursorWithoutJoiningLines() {
        let result = JournalTemplate.inserting("T\n", into: "First\nSecond", at: 6)
        #expect(result.text == "First\n\nT\n\nSecond")
        #expect(result.cursor == 9)
        let midLine = JournalTemplate.inserting("T\n", into: "AB", at: 1)
        #expect(midLine.text == "A\n\nT\n\nB")
    }
}

@Suite("Journal PDF export")
@MainActor
struct JournalPDFTests {
    private func john316() throws -> String {
        let url = try #require(Bundle.main.url(forResource: Translation.kjv.id, withExtension: "sqlite"))
        let bible = try BibleRepository(translation: .kjv, url: url)
        let found = try bible.verse(VerseID(book: 43, chapter: 3, verse: 16))
        let verse = try #require(found)
        return verse.plainText
    }

    private func words(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    @Test func rendersPagesWithTheVerseVerbatim() throws {
        let verse = try john316()
        var entry = JournalExport.Entry(title: "Grace upon grace")
        entry.details = ["Sunday 4 October 2026", "Grace Chapel · Pastor Ruth"]
        entry.body = "## Grace\n- **Full** of grace\n> Come and see\n\nA paragraph of notes."
        entry.passages = [JournalExport.Passage(reference: "John 3:16", translation: "KJV", text: verse)]
        entry.recordings = [JournalExport.Recording(duration: 185, caption: "")]
        entry.documents = [JournalExport.Document(pageCount: 4, caption: "Bulletin")]
        let export = JournalExport(title: "Grace upon grace", subtitle: "Grace Chapel", entries: [entry], font: .newYork)

        let data = JournalPDFRenderer(pageSize: CGSize(width: 612, height: 792)).render(export)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount >= 2, "A title page and the notes")
        let text = words(document.string ?? "")
        #expect(text.contains(words(verse)), "The verse is in the PDF exactly as in the Bible")
        #expect(text.contains("John 3:16 · KJV"))
        #expect(text.contains("Made with Genesis"))
        #expect(text.contains("Full of grace"), "Markdown marks are rendered, not printed")
        #expect(!text.contains("**"))
    }

    @Test func longJournalsFlowOntoMorePages() throws {
        let verse = try john316()
        let paragraph = String(repeating: "Lord, thank you for this day and for every kindness in it. ", count: 40)
        let entries = (1...6).map { index in
            var entry = JournalExport.Entry(title: "Prayer \(index)")
            entry.body = paragraph
            entry.passages = [JournalExport.Passage(reference: "John 3:16", translation: "KJV", text: verse)]
            return entry
        }
        let export = JournalExport(title: "Prayer Journal", subtitle: "", entries: entries)
        let data = JournalPDFRenderer(pageSize: CGSize(width: 595.2, height: 841.8)).render(export)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount > 4)
        let text = words(document.string ?? "")
        #expect(text.contains("Prayer 6"), "Nothing is cut off")
    }

    @Test func picturesAreScaledOntoThePage() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: format).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let jpeg = try #require(image.jpegData(compressionQuality: 0.5))
        var entry = JournalExport.Entry(title: "Photos")
        entry.pictures = [JournalExport.Picture(data: jpeg, caption: "Baptism Sunday")]
        let data = JournalPDFRenderer(pageSize: CGSize(width: 612, height: 792)).render(JournalExport(title: "Photos", subtitle: "", entries: [entry]))
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 2)
        let text = document.string ?? ""
        #expect(text.contains("Baptism Sunday"))
    }

    @Test func paperFollowsTheRegion() {
        #expect(JournalPDFRenderer.paperSize(region: Locale.Region("US")) == CGSize(width: 612, height: 792))
        #expect(JournalPDFRenderer.paperSize(region: Locale.Region("ES")).width < 600, "A4 elsewhere")
    }

    @Test func journalFilterTakesWholeDaysAndOneCategory() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        func day(_ number: Int, hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: number, hour: hour))!
        }
        let early = PrayerFacts(id: UUID(), category: .family, isAnswered: false, createdAt: day(1, hour: 0))
        let late = PrayerFacts(id: UUID(), category: .family, isAnswered: true, createdAt: day(3, hour: 23))
        let work = PrayerFacts(id: UUID(), category: .work, isAnswered: false, createdAt: day(2))
        let outside = PrayerFacts(id: UUID(), category: .family, isAnswered: false, createdAt: day(4, hour: 0))
        let empty = PrayerFacts(id: UUID(), category: .family, isAnswered: false, createdAt: day(2), hasContent: false)
        let all = [late, outside, work, early, empty]

        let everything = PrayerExportFilter(from: day(1, hour: 9), through: day(3, hour: 9), category: nil).apply(all, calendar: calendar)
        #expect(everything.map(\.id) == [early.id, work.id, late.id], "Oldest first, whole days, no empty prayers")
        let family = PrayerExportFilter(from: day(1), through: day(3), category: .family).apply(all, calendar: calendar)
        #expect(family.map(\.id) == [early.id, late.id])
    }

    @Test func exportFileNamesAreSafe() {
        #expect(JournalExportFile.name(for: "Grace / Truth: John 1") == "Grace Truth John 1.pdf")
        #expect(JournalExportFile.name(for: "  ") == "Genesis.pdf")
    }
}

@Suite("Journal extras gating")
@MainActor
struct JournalExtrasGatingTests {
    @Test func extrasArePremium() {
        let free = EntitlementService(defaults: UserDefaults(suiteName: "JournalExtras-\(UUID())")!, override: false)
        let premium = EntitlementService(defaults: UserDefaults(suiteName: "JournalExtras-\(UUID())")!, override: true)
        #expect(!free.allows(.journalExtras))
        #expect(premium.allows(.journalExtras))
        #expect(PremiumFeature.journalExtras.systemImage == "paperclip")
    }

    @Test func announcedOnce() {
        let ids = WhatsNewCatalog.all.map(\.id)
        #expect(ids.contains("journal-photos-voice-pdfs-templates"))
        #expect(Set(ids).count == ids.count, "Ids are never reused")
        #expect(WhatsNewCatalog.journalExtras.feature == .prayer)
    }

    @Test func recorderMeterAndTimes() {
        #expect(VoiceLevel.normalized(decibels: -160) == 0)
        #expect(VoiceLevel.normalized(decibels: -30) == 0.5)
        #expect(VoiceLevel.normalized(decibels: 3) == 1)
        #expect(VoiceLevel.normalized(decibels: -.infinity) == 0)
        #expect(VoiceLevel.timeText(65.9) == "1:05")
        #expect(VoiceLevel.timeText(3723) == "1:02:03")
    }
}
