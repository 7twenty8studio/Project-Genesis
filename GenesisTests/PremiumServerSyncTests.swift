import Foundation
import SwiftData
import Testing
@testable import Genesis

@Suite("Telling the server about Premium")
struct PremiumSyncPolicyTests {
    private let account = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func fingerprintsUseTheLowercaseAccount() {
        let fingerprint = PremiumSyncPolicy.fingerprint(account: account, transactionKey: "2000:2001")
        #expect(fingerprint == "6f9619ff-8b86-d011-b42d-00c04fc964ff|2000:2001")
    }

    @Test func nothingToSendWithoutASubscriptionOrAnAccount() {
        let noSubscription = PremiumSyncPolicy.shouldSync(transactionKey: nil, account: account, last: nil, now: now, force: true)
        #expect(!noSubscription)
        let signedOut = PremiumSyncPolicy.shouldSync(transactionKey: "2000:2001", account: nil, last: nil, now: now, force: true)
        #expect(!signedOut)
    }

    @Test func firstTimeAndAfterAChange() {
        let first = PremiumSyncPolicy.shouldSync(transactionKey: "2000:2001", account: account, last: nil, now: now, force: false)
        #expect(first)
        let last = PremiumSyncRecord(fingerprint: PremiumSyncPolicy.fingerprint(account: account, transactionKey: "2000:2001"), date: now)
        let renewed = PremiumSyncPolicy.shouldSync(transactionKey: "2000:2002", account: account, last: last, now: now, force: false)
        #expect(renewed, "A renewal is a new transaction")
        let otherAccount = PremiumSyncPolicy.shouldSync(transactionKey: "2000:2001", account: UUID(), last: last, now: now, force: false)
        #expect(otherAccount, "Signing in to another account")
    }

    @Test func unchangedWaitsADay() {
        let last = PremiumSyncRecord(fingerprint: PremiumSyncPolicy.fingerprint(account: account, transactionKey: "2000:2001"), date: now)
        let soon = PremiumSyncPolicy.shouldSync(transactionKey: "2000:2001", account: account, last: last, now: now.addingTimeInterval(3600), force: false)
        #expect(!soon)
        let forced = PremiumSyncPolicy.shouldSync(transactionKey: "2000:2001", account: account, last: last, now: now.addingTimeInterval(3600), force: true)
        #expect(forced)
        let nextDay = PremiumSyncPolicy.shouldSync(transactionKey: "2000:2001", account: account, last: last, now: now.addingTimeInterval(24 * 3600), force: false)
        #expect(nextDay)
        let clockMovedBack = PremiumSyncPolicy.shouldSync(transactionKey: "2000:2001", account: account, last: last, now: now.addingTimeInterval(-60), force: false)
        #expect(clockMovedBack)
    }

    @Test func readsTheServersReply() {
        let data = Data(#"{"premium":true,"expiresAt":"2026-11-15T12:00:00.000Z","source":"subscription"}"#.utf8)
        let reply = PremiumSyncClient.reply(from: data, status: 200)
        let expected = PremiumSyncClient.Reply(premium: true, expiresAt: "2026-11-15T12:00:00.000Z", source: "subscription")
        #expect(reply == expected)
        let free = PremiumSyncClient.reply(from: Data(#"{"premium":false,"expiresAt":null,"source":null}"#.utf8), status: 200)
        #expect(free?.premium == false)
        let failed = PremiumSyncClient.reply(from: Data(#"{"error":"Sign in first."}"#.utf8), status: 401)
        #expect(failed == nil)
    }

    @Test func storageRefusalsForWantOfPremium() {
        let forbidden = AttachmentUploadRefusal.isPremiumRefusal(status: 403, message: "Forbidden")
        #expect(forbidden)
        let olderStorage = AttachmentUploadRefusal.isPremiumRefusal(status: 400, message: "new row violates row-level security policy")
        #expect(olderStorage)
        let missing = AttachmentUploadRefusal.isPremiumRefusal(status: 400, message: "Object not found")
        #expect(!missing)
        let tooLarge = AttachmentUploadRefusal.isPremiumRefusal(status: 413, message: "Payload too large")
        #expect(!tooLarge)
    }
}

@Suite("Uploads refused until the server knows about Premium", .serialized)
@MainActor
struct PremiumUploadRetryTests {
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(UserDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "premium-uploads-\(UUID())"))
    }

    @Test func asksTheServerOnceThenUploads() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = StudyStore(context: context)
        let files = AttachmentFiles.temporary()
        let storage = InMemoryAttachmentStorage(premiumRecorded: false)
        let transfers = AttachmentTransfers(files: files, storage: storage, defaults: try defaults())
        let user = userID
        transfers.userID = { user }
        let calls = CallCounter()
        transfers.recordPremium = {
            calls.count += 1
            await storage.recordPremium()
            return true
        }
        let owner = UUID()
        let first = try #require(store.addAttachment(kind: .photo, to: .sermon, ownerID: owner, byteSize: 3))
        let second = try #require(store.addAttachment(kind: .pdf, to: .sermon, ownerID: owner, byteSize: 3))
        try files.write(Data([1, 2, 3]), to: first.fileName)
        try files.write(Data([4, 5, 6]), to: second.fileName)

        await transfers.run(context: context, now: .now)

        #expect(calls.count == 1)
        #expect(!first.needsUpload)
        #expect(!second.needsUpload)
        let stored = await storage.objects.count
        #expect(stored == 2)
        let pending = transfers.pendingOperations
        #expect(pending.isEmpty)
    }

    @Test func notPremiumOnTheServerWaitsAndRetriesLater() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = StudyStore(context: context)
        let files = AttachmentFiles.temporary()
        let storage = InMemoryAttachmentStorage(premiumRecorded: false)
        let transfers = AttachmentTransfers(files: files, storage: storage, defaults: try defaults())
        let user = userID
        transfers.userID = { user }
        let calls = CallCounter()
        transfers.recordPremium = {
            calls.count += 1
            return false
        }
        let owner = UUID()
        let first = try #require(store.addAttachment(kind: .photo, to: .prayer, ownerID: owner, byteSize: 3))
        let second = try #require(store.addAttachment(kind: .photo, to: .prayer, ownerID: owner, byteSize: 3))
        try files.write(Data([1]), to: first.fileName)
        try files.write(Data([2]), to: second.fileName)
        let start = Date.now

        await transfers.run(context: context, now: start)

        #expect(calls.count == 1, "Once per run, whatever the number of files")
        #expect(first.needsUpload)
        #expect(second.needsUpload)
        let pending = transfers.pendingOperations.count
        #expect(pending == 2)

        await transfers.run(context: context, now: start.addingTimeInterval(31))
        #expect(calls.count == 2, "Asked again on the next try")
    }
}

@MainActor
private final class CallCounter {
    var count = 0
}
