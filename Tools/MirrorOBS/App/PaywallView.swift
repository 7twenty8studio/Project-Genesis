import StoreKit
import SwiftUI

/// The trial and unlock card on the main screen.
struct AccessCard: View {
    @Environment(Store.self) private var store
    @State private var redeeming = false

    var body: some View {
        Card(title: title) {
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            switch store.access {
            case .none:
                Button { Task { await store.startTrial() } } label: {
                    Text("Start 7-Day Free Trial").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Studio.ink)
                unlockButton(prominent: false)
            case .trial, .trialOver:
                unlockButton(prominent: true)
            case .unlocked, .loading:
                EmptyView()
            }
            if store.access != .unlocked {
                HStack(spacing: 18) {
                    Button("Restore Purchases") { Task { await store.restore() } }
                    Button("Redeem Code") { redeeming = true }
                }
                .font(.footnote)
                Text("The trial is free and never charges you. Mirror OBS is a one-time purchase, with no subscription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    Link("Privacy Policy", destination: URL(string: Mirror.privacyPolicy)!)
                }
                .font(.caption)
            }
        }
        .disabled(store.busy)
        .offerCodeRedemption(isPresented: $redeeming) { _ in
            Task { await store.refresh() }
        }
        .alert("Mirror OBS", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }

    private func unlockButton(prominent: Bool) -> some View {
        Button { Task { await store.buyUnlock() } } label: {
            Text("Unlock for \(store.unlock?.displayPrice ?? "$4.99")")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(prominent ? Studio.ink : Studio.copper)
    }

    private var title: String {
        switch store.access {
        case .unlocked: "Unlocked"
        case .trial: "Free Trial"
        default: "Mirror OBS"
        }
    }

    private var detail: String {
        switch store.access {
        case .loading:
            return "Checking the App Store…"
        case .none:
            return "Try everything free for 7 days, then unlock it once for good."
        case .trial(let ends):
            let left = ends.formatted(.relative(presentation: .named))
            return "Your free trial ends \(left). Unlock any time to keep broadcasting."
        case .trialOver:
            return "Your free trial has ended. Unlock Mirror OBS once to keep broadcasting to OBS."
        case .unlocked:
            return "Thank you! Mirror OBS is yours on every iPhone with this Apple Account."
        }
    }
}
