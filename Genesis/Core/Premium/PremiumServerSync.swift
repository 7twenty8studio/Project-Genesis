import Foundation

/// When the app tells the server (the premium-sync Edge Function) about the
/// App Store subscription, so the server knows about Premium
/// (`public.genesis_is_premium()`, used by study-ai and future server
/// features), not only from App Store notifications.
///
/// Only with a subscription and a signed-in account. Otherwise whenever the
/// subscription (a new purchase or renewal) or the account changes, and at
/// least once a day so a server that missed something catches up. Failures
/// aren't recorded, so the next launch or return to the front tries again.
enum PremiumSyncPolicy {
    static let refreshInterval: TimeInterval = 24 * 60 * 60

    /// What the server was last told: the account and the transaction.
    static func fingerprint(account: UUID, transactionKey: String) -> String {
        "\(account.uuidString.lowercased())|\(transactionKey)"
    }

    static func shouldSync(transactionKey: String?, account: UUID?, last: PremiumSyncRecord?, now: Date, force: Bool) -> Bool {
        guard let transactionKey, let account else { return false }
        if force { return true }
        guard let last, last.fingerprint == fingerprint(account: account, transactionKey: transactionKey) else { return true }
        return now.timeIntervalSince(last.date) >= refreshInterval || now < last.date
    }
}

/// The last time the server heard about the subscription (UserDefaults).
struct PremiumSyncRecord: Codable, Equatable, Sendable {
    let fingerprint: String
    let date: Date
}

/// Calls the premium-sync Edge Function with the person's token.
struct PremiumSyncClient: Sendable {
    let client: SupabaseClient

    struct Reply: Decodable, Equatable, Sendable {
        let premium: Bool
        let expiresAt: String?
        let source: String?
    }

    private struct Body: Encodable {
        let signedTransaction: String?
    }

    /// The server's answer, or nil when it couldn't be reached or refused.
    func sync(signedTransaction: String?, accessToken: String) async -> Reply? {
        guard let body = try? JSONEncoder().encode(Body(signedTransaction: signedTransaction)),
              let response = try? await client.callFunction("premium-sync", body: body, accessToken: accessToken) else { return nil }
        return Self.reply(from: response.data, status: response.status)
    }

    static func reply(from data: Data, status: Int) -> Reply? {
        guard status == 200 else { return nil }
        return try? JSONDecoder().decode(Reply.self, from: data)
    }
}
