import StoreKit
import SwiftUI

/// The Genesis Premium screen: what it includes, the two plans, restore, and
/// the subscription terms App Review requires.
struct PremiumView: View {
    /// The feature that led here, shown first.
    var highlighted: PremiumFeature?

    @Environment(EntitlementService.self) private var entitlements
    @Environment(AuthService.self) private var auth
    @Environment(StudyAssistant.self) private var assistant
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var selected: PremiumProduct = .yearly
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if entitlements.isPremium {
                        activeCard
                    } else {
                        features
                        plans
                        purchaseButton
                    }
                    footer
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .themedScreen()
            .navigationTitle("Genesis Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("premium.close")
                }
            }
            .task { if entitlements.products.isEmpty { await entitlements.loadProducts() } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(palette.accent)
            Text(entitlements.isPremium ? "You have Genesis Premium" : "Go deeper with Premium")
                .font(.system(.title, design: .serif, weight: .semibold))
                .foregroundStyle(palette.text)
            if !entitlements.isPremium {
                Text("Reading, search and the full Bible stay free, always.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private var orderedFeatures: [PremiumFeature] {
        // The study assistant isn't offered while it's switched off.
        let offered = PremiumFeature.allCases.filter { $0 != .advancedAI || assistant.isEnabled }
        guard let highlighted, offered.contains(highlighted) else { return offered }
        return [highlighted] + offered.filter { $0 != highlighted }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(orderedFeatures) { feature in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: feature.systemImage)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.headline)
                            .foregroundStyle(palette.text)
                        Text(feature.detail)
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var plans: some View {
        VStack(spacing: 10) {
            ForEach([PremiumProduct.yearly, .monthly], id: \.self) { plan in
                let isSelected = selected == plan
                Button {
                    selected = plan
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.periodTitle)
                                .font(.headline)
                            if plan == .yearly {
                                Text(savingsText)
                                    .font(.caption)
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        Spacer()
                        Text("\(price(plan)) / \(plan.periodUnit)")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(palette.text)
                    .padding(16)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isSelected ? palette.accent : palette.separator, lineWidth: isSelected ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("premium.plan.\(plan == .yearly ? "yearly" : "monthly")")
            }
        }
    }

    private var purchaseButton: some View {
        VStack(spacing: 10) {
            Button {
                Task { await buy() }
            } label: {
                Group {
                    if entitlements.isPurchasing {
                        ProgressView()
                    } else {
                        Text("Subscribe")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(entitlements.isPurchasing)
            .accessibilityIdentifier("premium.subscribe")

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("premium.message")
            }
        }
    }

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let product = entitlements.activeProduct {
                Text("\(product.periodTitle) plan")
                    .font(.headline)
                    .foregroundStyle(palette.text)
            }
            if let date = entitlements.renewsOrExpiresAt {
                Text("Renews or ends on \(date.formatted(date: .long, time: .omitted)).")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
            Button("Manage Subscription") {
                Task { await manageSubscriptions() }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Restore Purchases") {
                Task {
                    let restored = await entitlements.restore()
                    message = restored ? "Premium restored." : "No active subscription was found for this Apple Account."
                }
            }
            .accessibilityIdentifier("premium.restore")
            Text("Payment is charged to your Apple Account. The subscription renews automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel it in Settings > Apple Account > Subscriptions.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
            HStack(spacing: 16) {
                Link("Terms of Use", destination: AppConfiguration.current.termsURL)
                if let privacy = AppConfiguration.current.privacyURL {
                    Link("Privacy Policy", destination: privacy)
                }
            }
            .font(.caption)
        }
    }

    // MARK: Helpers

    private func price(_ plan: PremiumProduct) -> String {
        entitlements.product(plan)?.displayPrice ?? plan.fallbackPrice
    }

    private var savingsText: String {
        guard let monthly = entitlements.product(.monthly), let yearly = entitlements.product(.yearly), monthly.price > 0 else {
            return "Save 33%"
        }
        let full = monthly.price * 12
        let saving = (full - yearly.price) / full * 100
        let percent = NSDecimalNumber(decimal: saving).intValue
        return percent > 0 ? "Save \(percent)%" : "Best value"
    }

    private func buy() async {
        message = nil
        switch await entitlements.purchase(selected, accountID: auth.user?.id) {
        case .purchased:
            dismiss()
        case .pending:
            message = "Your purchase is waiting for approval."
        case .cancelled:
            break
        case let .failed(reason):
            message = reason
        }
    }

    private func manageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }
}

/// A small "Premium" tag for locked options.
struct PremiumBadge: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(palette.accent)
            .accessibilityLabel("Premium")
    }
}

extension View {
    /// Presents the Premium screen while `feature` is set.
    func premiumSheet(_ feature: Binding<PremiumFeature?>) -> some View {
        sheet(item: feature) { feature in
            PremiumView(highlighted: feature)
        }
    }
}
