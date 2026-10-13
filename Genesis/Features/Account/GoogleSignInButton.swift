import SwiftUI

/// "Sign in with Google" in Google's own button style: white with a grey
/// outline in light mode, near-black with a grey outline in dark mode, the
/// four-colour G at 18 pt and dark/light text. Brand colours, never themed.
struct GoogleSignInButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GoogleLogo()
                    .frame(width: 18, height: 18)
                Text("Sign in with Google")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(fillColor, in: .rect(cornerRadius: GoogleSignInButton.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GoogleSignInButton.cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: GoogleSignInButton.cornerRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Sign in with Google"))
    }

    /// Shared with the Sign in with Apple button above it, so both look alike.
    static let cornerRadius: CGFloat = 12

    private var isDark: Bool { colorScheme == .dark }
    // Google's branding guidelines: light #FFFFFF / #747775 / #1F1F1F, dark #131314 / #8E918F / #E3E3E3.
    private var fillColor: Color {
        isDark ? Color(red: 19 / 255, green: 19 / 255, blue: 20 / 255) : .white
    }

    private var strokeColor: Color {
        isDark ? Color(red: 142 / 255, green: 145 / 255, blue: 143 / 255) : Color(red: 116 / 255, green: 119 / 255, blue: 117 / 255)
    }

    private var textColor: Color {
        isDark ? Color(red: 227 / 255, green: 227 / 255, blue: 227 / 255) : Color(red: 31 / 255, green: 31 / 255, blue: 31 / 255)
    }
}
