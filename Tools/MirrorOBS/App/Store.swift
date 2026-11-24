import Foundation
import Observation
import StoreKit

/// What Mirror OBS sells, through StoreKit only:
/// - the 7-day free trial, a $0 non-renewing subscription (Apple's way to
///   offer a trial before a one-time purchase, guideline 3.1.1): it starts
///   when it's "bought", and the 7 days are counted from that purchase;
/// - the unlock, a one-time $4.99 purchase (non-consumable), for good.
/// Free copies for the owner or friends are Apple offer codes for the unlock
/// (App Store Connect › the unlock › Offer Codes), redeemed in the app or
/// the App Store; they arrive as an ordinary unlock transaction.
/// Whatever StoreKit says is copied to the App Group for the extension.
@MainActor @Observable
final class Store {
    static let trialID = "com.7twenty8studio.mirrorobs.trial7"
    static let unlockID = "com.7twenty8studio.mirrorobs.unlock"
    static let trialLength: TimeInterval = 7 * 24 * 60 * 60

    enum Access: Equatable {
        case loading
        case none             // never tried
        case trial(ends: Date)
        case trialOver
        case unlocked

        var canBroadcast: Bool {
            switch self {
            case .unlocked: true
            case .trial(let ends): ends > Date()
            default: false
            }
        }
    }

    private(set) var access: Access = .loading
    private(set) var unlock: Product?
    private(set) var trial: Product?
    private(set) var busy = false
    var message: String?

    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { await load() }
    }

    func load() async {
        do {
            let products = try await Product.products(for: [Self.trialID, Self.unlockID])
            unlock = products.first { $0.id == Self.unlockID }
            trial = products.first { $0.id == Self.trialID }
        } catch {
            message = "The App Store can't be reached right now."
        }
        await refresh()
    }

    /// Reads every purchase this Apple Account made (both kinds stay in its history).
    func refresh() async {
        var unlocked = false
        var trialStart: Date?
        for await result in Transaction.all {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case Self.unlockID: unlocked = true
            case Self.trialID: trialStart = min(trialStart ?? transaction.purchaseDate, transaction.purchaseDate)
            default: break
            }
        }
        if unlocked {
            access = .unlocked
        } else if let trialStart {
            let ends = trialStart.addingTimeInterval(Self.trialLength)
            access = ends > Date() ? .trial(ends: ends) : .trialOver
        } else {
            access = .none
        }
        Mirror.saveAccess(unlocked: unlocked, trialEnds: trialStart?.addingTimeInterval(Self.trialLength))
    }

    func startTrial() async { await buy(trial) }
    func buyUnlock() async { await buy(unlock) }

    func restore() async {
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refresh()
            if access != .unlocked { message = "No unlock was found for this Apple Account." }
        } catch {
            message = "Restore didn't finish. Try again in a moment."
        }
    }

    private func buy(_ product: Product?) async {
        guard let product else {
            message = "The App Store can't be reached right now."
            return
        }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refresh()
            case .success(.unverified):
                message = "The App Store couldn't confirm that purchase."
            case .pending:
                message = "Waiting for approval (Ask to Buy). It unlocks once it's approved."
            default:
                break
            }
        } catch {
            message = "The purchase didn't finish. Try again in a moment."
        }
    }
}
