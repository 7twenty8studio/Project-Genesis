import SwiftUI

/// First launch: choose a translation and begin reading, well within 30 seconds.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(BibleLibrary.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Translation = .kjv
    @State private var appeared = false
    @State private var choosingFeatures = false

    var body: some View {
        if choosingFeatures {
            FeatureChoicesView(onFinish: onFinish)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            translationStep
        }
    }

    private var translationStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Genesis")
                        .font(.system(size: 44, weight: .regular, design: .serif))
                        .foregroundStyle(palette.text)
                    Text("Scripture, quietly and beautifully. Everything works offline.")
                        .font(.title3)
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(.top, 60)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 12)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: String(localized: "Choose a translation"))
                    ForEach(library.translations) { translation in
                        TranslationOption(translation: translation, isSelected: translation == selection) {
                            selection = translation
                        }
                    }
                    Text("You can switch any time from the reader.")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }

                VStack(spacing: 14) {
                    Button {
                        begin(at: .genesis1)
                    } label: {
                        Text("Begin with Genesis")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("onboarding.begin")

                    Button("Or start with the Gospel of John") {
                        begin(at: .john1)
                    }
                    .font(.subheadline)
                    .foregroundStyle(palette.accent)
                    .accessibilityIdentifier("onboarding.john")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .themedScreen()
        .onAppear {
            selection = library.currentTranslation
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { appeared = true }
        }
    }

    private func begin(at chapter: ChapterID) {
        library.currentTranslation = selection
        router.read(chapter)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { choosingFeatures = true }
    }
}

private struct TranslationOption: View {
    let translation: Translation
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? palette.accent : palette.separator)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(translation.name)
                            .font(.headline)
                            .foregroundStyle(palette.text)
                        Text(translation.abbreviation)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.accent)
                    }
                    Text(translation.summary)
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? palette.accent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("onboarding.translation.\(translation.id)")
    }
}
