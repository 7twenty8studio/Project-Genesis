import Foundation
import Observation
import StoreKit

/// Tracks whether the person has Genesis Premium, using StoreKit 2.
///
/// The App Store is the source of truth: `Transaction.currentEntitlements` is
/// checked at launch and whenever a transaction arrives (a purchase on
/// another device, a renewal, a refund). The last known answer is cached so
/// Premium features don't flicker off while StoreKit loads.
@MainActor
@Observable
final class EntitlementService {
    enum PurchaseOutcome: Equatable {
        case purchased
        case pending
        case cancelled
        case failed(String)
    }

    /// Premium from any source: the App Store, a grant from the owner, or
    /// (development builds only) the "Test as Premium" switch.
    private(set) var isPremium: Bool
    /// An App Store subscription is active.
    private(set) var hasSubscription: Bool
    /// The owner gave this account Premium (public.premium_grants).
    private(set) var hasGrant: Bool
    /// When the grant ends; nil while there's no grant or it's permanent.
    private(set) var grantExpiresAt: Date? = nil
    /// True once StoreKit has answered at least once this launch.
    private(set) var hasLoaded = false
    private(set) var products: [Product] = []
    private(set) var activeProduct: PremiumProduct?
    private(set) var renewsOrExpiresAt: Date?
    private(set) var isPurchasing = false
    /// The signed App Store transaction for the active subscription, which the
    /// study assistant's server verifies before lifting the free limit.
    private(set) var signedTransaction: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let override: Bool?
    @ObservationIgnored private var updates: Task<Void, Never>?

    private static let cacheKey = "premium.lastKnown"
    private static let grantKey = "premium.grant"
    private static let testKey = "premium.testSwitch"

    /// - Parameter override: forces Premium on or off (UI tests); StoreKit is then ignored.
    init(defaults: UserDefaults = .standard, override: Bool? = nil) {
        self.defaults = defaults
        self.override = override
        hasSubscription = defaults.bool(forKey: Self.cacheKey)
        hasGrant = defaults.bool(forKey: Self.grantKey)
        isPremium = false
        if override != nil { hasLoaded = true }
        recompute()
    }

    private func recompute() {
        if let override {
            isPremium = override
            return
        }
        isPremium = hasSubscription || hasGrant || isTestingPremium
    }

    // MARK: Testing (development builds only)

    #if DEBUG
    /// Settings › Developer › Test as Premium. Never in release builds.
    var isTestingPremium: Bool {
        get { defaults.bool(forKey: Self.testKey) }
        set {
            defaults.set(newValue, forKey: Self.testKey)
            recompute()
        }
    }
    #else
    var isTestingPremium: Bool { false }
    #endif

    // MARK: Granted Premium

    private struct GrantRow: Decodable, Sendable {
        let expires_at: String?
    }

    /// Checks public.premium_grants for the signed-in account (nil when signed
    /// out). A permanent grant has no end date.
    func refreshGrant(client: SupabaseClient?, accessToken: String?) async {
        guard override == nil else { return }
        guard let client, let accessToken else {
            setGrant(active: false, until: nil)
            return
        }
        do {
            let rows: [GrantRow] = try await client.select("premium_grants", query: [URLQueryItem(name: "select", value: "expires_at")], accessToken: accessToken)
            guard let row = rows.first else {
                setGrant(active: false, until: nil)
                return
            }
            let end = row.expires_at.flatMap(Self.parseDate)
            setGrant(active: end.map { $0 > .now } ?? true, until: end)
        } catch {
            // Offline or the table isn't there yet: keep what we knew.
        }
    }

    private func setGrant(active: Bool, until: Date?) {
        hasGrant = active
        grantExpiresAt = active ? until : nil
        defaults.set(active, forKey: Self.grantKey)
        recompute()
    }

    nonisolated private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// Starts listening for transactions and loads the current state.
    func start() {
        guard override == nil, updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case let .verified(transaction) = result {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task {
            await refresh()
            await loadProducts()
        }
    }

    // MARK: Access

    func allows(_ feature: PremiumFeature) -> Bool {
        isPremium
    }

    func canAddNote(existing count: Int) -> Bool {
        isPremium || count < FreeLimits.notes
    }

    func canAddPrayer(existing count: Int) -> Bool {
        isPremium || count < FreeLimits.prayers
    }

    func allows(_ theme: ReaderTheme) -> Bool {
        isPremium || !theme.isPremium
    }

    // MARK: Store

    /// Days of free trial this Apple Account can still get for a plan (an
    /// introductory offer set up in App Store Connect), or nil.
    func freeTrialDays(for id: PremiumProduct) async -> Int? {
        guard let product = product(id), let subscription = product.subscription,
              let offer = subscription.introductoryOffer, offer.paymentMode == .freeTrial,
              await subscription.isEligibleForIntroOffer else { return nil }
        let count = offer.period.value * offer.periodCount
        switch offer.period.unit {
        case .day: return count
        case .week: return count * 7
        case .month: return count * 30
        case .year: return count * 365
        @unknown default: return nil
        }
    }

    func product(_ id: PremiumProduct) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    func loadProducts() async {
        guard override == nil else { return }
        do {
            let loaded = try await Product.products(for: PremiumProduct.ids)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            CrashReporter.record(error, context: "StoreKit products")
        }
    }

    /// - Parameter accountID: the signed-in Genesis account, recorded on the
    ///   purchase so the study assistant's server can tie it to that account.
    func purchase(_ id: PremiumProduct, accountID: UUID? = nil) async -> PurchaseOutcome {
        if products.isEmpty { await loadProducts() }
        guard let product = product(id) else {
            return .failed(String(localized: "The App Store isn't available right now. Please try again later."))
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let options: Set<Product.PurchaseOption> = accountID.map { [.appAccountToken($0)] } ?? []
            switch try await product.purchase(options: options) {
            case let .success(verification):
                guard case let .verified(transaction) = verification else {
                    return .failed(String(localized: "The purchase couldn't be verified."))
                }
                await transaction.finish()
                await refresh()
                return .purchased
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Restores purchases made with this Apple Account.
    func restore() async -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            return false
        }
        await refresh()
        return isPremium
    }

    /// Re-reads the current entitlements from StoreKit.
    func refresh() async {
        guard override == nil else { return }
        var best: (transaction: Transaction, jws: String)?
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  PremiumProduct.ids.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  (transaction.expirationDate ?? .distantFuture) > .now
            else { continue }
            if best == nil || (transaction.expirationDate ?? .distantFuture) > (best?.transaction.expirationDate ?? .distantPast) {
                best = (transaction, result.jwsRepresentation)
            }
        }
        hasSubscription = best != nil
        recompute()
        activeProduct = best.flatMap { PremiumProduct(rawValue: $0.transaction.productID) }
        renewsOrExpiresAt = best?.transaction.expirationDate
        signedTransaction = best?.jws
        hasLoaded = true
        defaults.set(hasSubscription, forKey: Self.cacheKey)
    }
}
