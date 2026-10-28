import SwiftUI

/// The first thing a new reader sees: a few pages, each with its picture,
/// showing what Versely is for. Skip goes straight to choosing a translation.
struct OnboardingWelcomeView: View {
    let onContinue: () -> Void

    @Environment(FeatureFlagService.self) private var flags
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: WelcomePage = .read

    private var pages: [WelcomePage] {
        WelcomePage.allCases.filter { $0.isAvailable(flags: flags) }
    }

    private var isLast: Bool { page == pages.last }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onContinue)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .opacity(isLast ? 0 : 1)
                    .disabled(isLast)
                    .accessibilityHidden(isLast)
                    .accessibilityIdentifier("onboarding.welcome.skip")
            }
            .padding(.horizontal, 24)
            .frame(minHeight: 44)

            TabView(selection: $page) {
                ForEach(pages) { page in
                    WelcomePageView(page: page)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 22) {
                WelcomePageDots(count: pages.count, current: pages.firstIndex(of: page) ?? 0)

                Button(action: next) {
                    Text(isLast ? "Continue" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("onboarding.welcome.next")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 560)
        }
        .background { WelcomeBackground() }
    }

    private func next() {
        guard let index = pages.firstIndex(of: page), index + 1 < pages.count else {
            onContinue()
            return
        }
        withAnimation(reduceMotion ? nil : Motion.drawer(0.35)) { page = pages[index + 1] }
    }
}

/// One page of the welcome: what the picture shows and what it's for.
enum WelcomePage: String, CaseIterable, Identifiable {
    case read, listen, pray, together

    var id: String { rawValue }

    var imageName: String {
        switch self {
        case .read: "OnboardingRead"
        case .listen: "OnboardingListen"
        case .pray: "OnboardingPray"
        case .together: "OnboardingTogether"
        }
    }

    var title: String {
        switch self {
        case .read: String(localized: "Your quiet place to read", comment: "Welcome page: reading")
        case .listen: String(localized: "Listen along", comment: "Welcome page: listening")
        case .pray: String(localized: "A place to pray", comment: "Welcome page: prayer journal")
        case .together: String(localized: "Read together", comment: "Welcome page: groups")
        }
    }

    var message: String {
        switch self {
        case .read: String(localized: "A calm reader that works offline. Highlight, take notes and pick up where you left off.")
        case .listen: String(localized: "Hear chapters read aloud and follow along, verse by verse.")
        case .pray: String(localized: "Keep a prayer journal, hold on to the verses that speak to you and look back on answered prayers.")
        case .together: String(localized: "Read a plan with friends or your church, talk it over and pray for one another.")
        }
    }

    /// Together only shows while groups or community are switched on.
    func isAvailable(flags: FeatureFlagService) -> Bool {
        self != .together || FeaturePreferences.isAvailable(.together, flags: flags)
    }
}

private struct WelcomePageView: View {
    let page: WelcomePage

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Image(page.imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 340, maxHeight: 320)
                .padding(.horizontal, 32)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundStyle(palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text(page.message)
                    .font(.body)
                    .foregroundStyle(palette.secondaryText)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 32)
            .frame(maxWidth: 520)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WelcomePageDots: View {
    let count: Int
    let current: Int

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? palette.accent : palette.secondaryText.opacity(0.3))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(Motion.change(reduceMotion: reduceMotion), value: current)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Page \(current + 1) of \(count)"))
    }
}

/// The theme's paper with a soft warm glow behind the pictures.
private struct WelcomeBackground: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.background, palette.accent.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [palette.accent.opacity(0.16), .clear],
                center: UnitPoint(x: 0.5, y: 0.35),
                startRadius: 0,
                endRadius: 320
            )
        }
        .background(palette.background)
        .ignoresSafeArea()
    }
}
