import SwiftUI

/// 7Twenty8 Studio's colors (the website's palette).
enum Studio {
    static let cream = Color(red: 0.980, green: 0.973, blue: 0.961)      // #faf8f5
    static let ink = Color(red: 0.102, green: 0.090, blue: 0.078)        // #1a1714
    static let copper = Color(red: 0.690, green: 0.553, blue: 0.392)     // #b08d64
    static let sand = Color(red: 0.784, green: 0.659, blue: 0.510)       // #c8a882
    static let surface = Color(red: 0.953, green: 0.929, blue: 0.898)    // #f3ede5
    static let warmGray = Color(red: 0.420, green: 0.376, blue: 0.329)   // #6b6054
    static let live = Color(red: 0.78, green: 0.16, blue: 0.14)
}

/// A rounded card with a small title, like the website's.
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Studio.copper)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}
