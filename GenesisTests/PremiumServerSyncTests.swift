import Foundation
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
}
