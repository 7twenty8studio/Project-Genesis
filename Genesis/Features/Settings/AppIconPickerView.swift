import SwiftUI

/// Settings › App Icon: the standard icon, Night, the four seasons, or
/// Seasons to change with the calendar. The standard icon is free; the rest
/// are Premium and open the Premium screen when locked.
struct AppIconPickerView: View {
    @Environment(\.palette) private var palette
    @Environment(EntitlementService.self) private var entitlements
    @State private var choice = AppIcon.choice
    @State private var premium: PremiumFeature?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 18)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(AppIconChoice.allCases) { item in
                    let isLocked = !entitlements.allows(icon: item)
                    Button {
                        if isLocked {
                            premium = .premiumThemes
                        } else {
                            choice = item
                            AppIcon.choice = item
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(item.previewName)
                                .resizable()
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .overlay(alignment: .bottomTrailing) {
                                    if item == .seasons {
                                        Image(systemName: "calendar")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(palette.accent)
                                            .padding(5)
                                            .background(palette.surface, in: Circle())
                                            .offset(x: 6, y: 6)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .strokeBorder(choice == item ? palette.accent : palette.separator, lineWidth: choice == item ? 3 : 1)
                                        .padding(-4)
                                )
                                .overlay(alignment: .topTrailing) {
                                    if isLocked {
                                        PremiumBadge()
                                            .padding(5)
                                            .background(palette.background, in: Circle())
                                            .offset(x: 6, y: -6)
                                    }
                                }
                            Text(item.title)
                                .font(.caption)
                                .foregroundStyle(choice == item ? palette.accent : palette.text)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isLocked ? String(localized: "\(item.title) icon, Premium") : item.title)
                    .accessibilityAddTraits(choice == item ? .isSelected : [])
                    .accessibilityIdentifier("appIcon.\(item.rawValue)")
                }
            }
            .padding(24)

            Text("Seasons changes the icon through the year: Autumn, Winter, Spring and Summer, by where you live. iPhone shows a short notice whenever an app's icon changes.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 24)

            if !entitlements.allows(.premiumThemes) {
                Text("Night and the seasonal icons come with Genesis Premium.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
        }
        .themedScreen()
        .premiumSheet($premium)
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
    }
}
