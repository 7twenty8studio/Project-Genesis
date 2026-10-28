import SwiftUI

/// The very first screen: the icon and wordmark over misty mountains, with
/// Get Started. It always wears the brand's own colors, whatever the theme.
struct OnboardingHeroView: View {
    let onStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            VStack(spacing: 26) {
                Image("WelcomeIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .shadow(color: BrandColors.walnut.opacity(0.30), radius: 20, y: 12)
                    .accessibilityHidden(true)
                Image("WelcomeWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)
                    .accessibilityLabel(String(localized: "Versely, Bible Study App"))
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 40)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 10)
            Spacer(minLength: 32)
            Spacer(minLength: 32)

            VStack(spacing: 16) {
                Button(action: onStart) {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundStyle(BrandColors.cream)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(BrandColors.buttonGradient, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                        .shadow(color: BrandColors.walnut.opacity(0.35), radius: 14, y: 8)
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityIdentifier("onboarding.hero.start")

                Text("Go beyond the verse.")
                    .font(.callout)
                    .foregroundStyle(BrandColors.cream.opacity(0.92))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 28)
            .frame(maxWidth: 460)
            .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Image("WelcomeMountains")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .background(BrandColors.cream)
        .environment(\.colorScheme, .light)
        .onAppear {
            withAnimation(reduceMotion ? nil : Motion.easeOut(0.6)) { appeared = true }
        }
    }
}

/// Settles a little under the finger, then springs back.
private struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.easeOut(0.16), value: configuration.isPressed)
    }
}
